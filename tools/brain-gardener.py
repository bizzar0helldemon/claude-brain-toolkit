#!/usr/bin/env python3
"""brain-gardener.py — the Phase 2 memory gardener.

Closes the capture -> surface -> observe -> adjust loop. Folds the append-only
event logs written by the hooks (surface events from session-start, use events
from post-tool-use Reads) into per-note activation counters, applies decay and
promotion transitions to each note's `status:`, and emits a health report so
"was this note ever useful" becomes a measured number instead of a hope.

Idempotent: recomputes counters from the FULL event logs every run and SETS
(never increments) frontmatter, so running twice changes nothing. Logs are the
source of truth for events; frontmatter is the materialized view.

Status lifecycle (decaying notes):
    warm --(use_count>=2)--> hot
    hot  --(surfaced>=8 w/ 0 use, or 30d since last use)--> warm
    warm --(90d idle, 0 use)--> archive
    archive --(180d further idle)--> tombstone
    any archived/tombstoned --(any use)--> resurrected to warm/hot

Exempt from decay (decays: false): preference, identity, synthesis, and any
note explicitly carrying `decays: false`. Handoffs archive after 14 days.

Nothing is ever deleted. Tombstone is the floor; the body stays on disk.

Usage:
    brain-gardener.py                 # dry run — report only, no writes
    brain-gardener.py --apply         # write status/counters, report, metrics, commit
    brain-gardener.py --now 2026-07-07  # pin the clock (tests / reproducibility)
    brain-gardener.py --brain /path/to/vault
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

# --- Tunable thresholds (all in one place, per the design) -------------------
PROMOTE_USE_COUNT = 2        # warm -> hot
DEMOTE_SURFACE_NOUSE = 8     # hot -> warm: shown this many times, never used
DEMOTE_DAYS = 30             # hot -> warm: days since last use
ARCHIVE_DAYS = 90            # warm -> archive: idle days with zero use
TOMBSTONE_DAYS = 180         # archive -> tombstone: further idle days
HANDOFF_ARCHIVE_DAYS = 14    # handoffs are messages, not knowledge

EXEMPT_TYPES = {"preference", "identity", "synthesis"}
DEFAULT_HOT_TYPES = {"preference", "identity", "handoff", "pitfall"}

SKIP_DIRS = {".obsidian", ".git", ".brain-search-vectors"}
MANAGED_KEYS = ("status", "surface_count", "last_surfaced", "use_count",
                "last_used", "decays")


# --- Frontmatter I/O ---------------------------------------------------------
def split_frontmatter(text):
    """Return (fm_dict, fm_raw, body). fm_dict is None if no frontmatter."""
    if not text.startswith("---"):
        return None, "", text
    m = re.match(r"^---\n(.*?)\n---\n?", text, re.DOTALL)
    if not m:
        return None, "", text
    raw = m.group(1)
    fm = {}
    for line in raw.splitlines():
        km = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if km:
            fm[km.group(1)] = km.group(2).strip()
    return fm, raw, text[m.end():]


def render_frontmatter(fm_raw, updates):
    """Return a new frontmatter block: existing lines with `updates` keys
    replaced in place, and any leftover new keys appended in a stable order."""
    lines = fm_raw.splitlines()
    seen = set()
    out = []
    for line in lines:
        km = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if km and km.group(1) in updates:
            key = km.group(1)
            out.append(f"{key}: {updates[key]}")
            seen.add(key)
        else:
            out.append(line)
    for key in MANAGED_KEYS:
        if key in updates and key not in seen:
            out.append(f"{key}: {updates[key]}")
    return "\n".join(out)


# --- Event folding -----------------------------------------------------------
def parse_ts(s):
    if not s:
        return None
    s = s.strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        # bare date
        try:
            return datetime.fromisoformat(s[:10])
        except ValueError:
            return None


def fold_events(brain):
    """Aggregate surface + use events per relative note path.

    Returns {relpath: {surface_count, last_surfaced, use_count, last_used,
                       use_sessions:set}}.
    """
    agg = {}

    def bump(path, field, ts, session=None):
        rec = agg.setdefault(path, {
            "surface_count": 0, "last_surfaced": None,
            "use_count": 0, "last_used": None, "use_sessions": set(),
        })
        rec[field] += 1
        tsd = ts.strip()[:10] if ts else None
        if field == "surface_count":
            if tsd and (rec["last_surfaced"] is None or tsd > rec["last_surfaced"]):
                rec["last_surfaced"] = tsd
        else:
            if tsd and (rec["last_used"] is None or tsd > rec["last_used"]):
                rec["last_used"] = tsd
            if session:
                rec["use_sessions"].add(session)

    logs = [
        (brain / "brain-mode" / "surface-log.jsonl", "surface_count"),
        (brain / "brain-mode" / "retrieval-log.jsonl", "use_count"),
    ]
    for logpath, field in logs:
        if not logpath.exists():
            continue
        for line in logpath.read_text(errors="ignore").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            # retrieval-log carries either a single path or a hits[] list
            paths = []
            if "path" in ev:
                paths = [ev["path"]]
            elif "hits" in ev and isinstance(ev["hits"], list):
                # search hits are "retrieved", not "used" — only count actual reads
                if field == "use_count" and ev.get("via") != "read":
                    continue
                paths = ev["hits"]
            for p in paths:
                rel = p
                # normalize absolute paths to vault-relative
                if os.path.isabs(p):
                    try:
                        rel = str(Path(p).resolve().relative_to(brain.resolve()))
                    except ValueError:
                        continue
                bump(rel, field, ev.get("ts", ""), ev.get("session"))
    return agg


# --- Decay / promotion engine ------------------------------------------------
def days_between(now, ymd):
    d = parse_ts(ymd)
    if d is None:
        return 10**6
    return (now - d.date()).days if isinstance(d, datetime) else (now - d).days


def _max_ymd(*vals):
    """Return the latest YYYY-MM-DD string among the args (ignoring None)."""
    present = [v[:10] for v in vals if v]
    return max(present) if present else None


def decide_status(fm, ev, note_type, now, mtime_ymd=None, epoch=None):
    """Return (new_status, reason). Pure function of frontmatter + events.

    `epoch` is the date the feedback loop began observing this vault. Idle-based
    decay measures neglect from max(created, last_surfaced, last_used, epoch), so
    legacy notes that predate the telemetry are NOT archived on day one — they
    get a full window to be surfaced-and-ignored before decaying. `mtime_ymd`
    is the file mtime, used only when a note carries no created/date.
    """
    decays = fm.get("decays", "").lower()
    exempt = decays == "false" or note_type in EXEMPT_TYPES
    cur = fm.get("status", "").strip() or ("hot" if note_type in DEFAULT_HOT_TYPES else "warm")

    use_count = ev["use_count"] if ev else 0
    use_sessions = len(ev["use_sessions"]) if ev else 0
    surface_count = ev["surface_count"] if ev else 0
    last_used = ev["last_used"] if ev else fm.get("last_used")
    last_surf = ev["last_surfaced"] if ev else fm.get("last_surfaced")
    created = fm.get("created") or fm.get("date") or mtime_ymd

    # Idle is measured from the most recent of: real activity, creation, and the
    # observation epoch. The epoch floor is the cold-start guard.
    idle_anchor = _max_ymd(last_used, last_surf, created, epoch)

    # Resurrection always wins — a used note comes back regardless of prior state.
    if use_count > 0 and cur in ("archive", "tombstone"):
        return ("hot" if use_count >= PROMOTE_USE_COUNT else "warm"), "resurrected-by-use"

    if exempt:
        # Exempt notes keep standing; default the missing status sensibly.
        target = "hot" if note_type in DEFAULT_HOT_TYPES else (cur or "warm")
        return target, "exempt"

    if note_type == "handoff":
        h_anchor = _max_ymd(last_used, last_surf, created, epoch)
        idle = days_between(now, h_anchor)
        if use_count == 0 and idle >= HANDOFF_ARCHIVE_DAYS and cur != "archive":
            return "archive", f"handoff-idle-{idle}d"

    # Promotion
    if cur == "warm" and (use_count >= PROMOTE_USE_COUNT or use_sessions >= 2):
        return "hot", f"promoted-use{use_count}"

    # hot -> warm
    if cur == "hot":
        if surface_count >= DEMOTE_SURFACE_NOUSE and use_count == 0:
            return "warm", f"shown{surface_count}-unused"
        if last_used and days_between(now, last_used) >= DEMOTE_DAYS:
            return "warm", f"cold-{days_between(now, last_used)}d"

    # warm -> archive
    if cur in ("warm", ""):
        idle = days_between(now, idle_anchor)
        if use_count == 0 and idle >= ARCHIVE_DAYS:
            return "archive", f"idle-{idle}d"

    # archive -> tombstone
    if cur == "archive":
        idle = days_between(now, idle_anchor)
        if use_count == 0 and idle >= (ARCHIVE_DAYS + TOMBSTONE_DAYS):
            return "tombstone", f"idle-{idle}d"

    return cur, "unchanged"


# --- Main pass ---------------------------------------------------------------
def read_epoch(brain, now, apply):
    """The date the feedback loop began observing this vault. Established once
    (on the first apply run) and never moved — it's the cold-start floor for
    idle-based decay so legacy content isn't archived before it's had a chance
    to surface. Absent (dry run before any apply): fall back to `now`, which
    makes idle-based archiving a no-op — dry runs never threaten mass archival."""
    stamp = brain / "brain-mode" / ".brain-gardener-epoch"
    if stamp.exists():
        val = stamp.read_text(errors="ignore").strip()[:10]
        if val:
            return val
    if apply:
        stamp.parent.mkdir(exist_ok=True)
        stamp.write_text(now.isoformat() + "\n")
    return now.isoformat()


def run(brain, apply, now):
    events = fold_events(brain)
    epoch = read_epoch(brain, now, apply)
    stats = {"scanned": 0, "no_frontmatter": 0, "changed": 0,
             "by_status": {}, "transitions": [], "used_notes": 0, "epoch": epoch}

    for path in sorted(brain.rglob("*.md")):
        if any(p in SKIP_DIRS for p in path.parts):
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        fm, fm_raw, body = split_frontmatter(text)
        if fm is None:
            stats["no_frontmatter"] += 1
            continue
        stats["scanned"] += 1

        rel = str(path.relative_to(brain))
        ev = events.get(rel)
        note_type = fm.get("type", "").strip()
        if ev and ev["use_count"] > 0:
            stats["used_notes"] += 1

        try:
            mtime_ymd = date.fromtimestamp(path.stat().st_mtime).isoformat()
        except OSError:
            mtime_ymd = None

        new_status, reason = decide_status(fm, ev, note_type, now, mtime_ymd, epoch)

        # Materialize counters + status into frontmatter (idempotent SET).
        updates = {"status": new_status}
        if ev:
            updates["surface_count"] = str(ev["surface_count"])
            updates["use_count"] = str(ev["use_count"])
            if ev["last_surfaced"]:
                updates["last_surfaced"] = ev["last_surfaced"]
            if ev["last_used"]:
                updates["last_used"] = ev["last_used"]
        if note_type in EXEMPT_TYPES and fm.get("decays", "").lower() != "false":
            updates["decays"] = "false"

        stats["by_status"][new_status] = stats["by_status"].get(new_status, 0) + 1

        # Did anything actually change vs current frontmatter?
        changed = any(str(fm.get(k, "")).strip() != str(v).strip()
                      for k, v in updates.items())
        if changed:
            stats["changed"] += 1
            if reason != "unchanged" and fm.get("status", "").strip() != new_status:
                stats["transitions"].append((rel, fm.get("status", "?") or "(new)",
                                             new_status, reason))
            if apply:
                new_fm = render_frontmatter(fm_raw, updates)
                path.write_text(f"---\n{new_fm}\n---\n{body}")

    return stats


def health_report(stats, now, apply):
    by = stats["by_status"]
    total = stats["scanned"]
    used = stats["used_notes"]
    hit_rate = (100.0 * used / total) if total else 0.0
    lines = [
        f"# Memory Health — {now.isoformat()} ({'APPLIED' if apply else 'DRY RUN'})",
        "",
        f"- Notes scanned (with frontmatter): {total}",
        f"- No-frontmatter (skipped): {stats['no_frontmatter']}",
        f"- Notes ever used (use_count>0): {used}  ({hit_rate:.1f}% of scanned)",
        f"- Frontmatter updated this pass: {stats['changed']}",
        "",
        "## Status distribution",
    ]
    for st in ("hot", "warm", "archive", "tombstone"):
        lines.append(f"- {st}: {by.get(st, 0)}")
    if stats["transitions"]:
        lines += ["", "## Transitions this pass"]
        for rel, old, new, why in stats["transitions"][:60]:
            lines.append(f"- {old} -> {new}  {rel}  ({why})")
        if len(stats["transitions"]) > 60:
            lines.append(f"- ... and {len(stats['transitions']) - 60} more")
    return "\n".join(lines), hit_rate


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    ap.add_argument("--now", default=None, help="pin date as YYYY-MM-DD")
    ap.add_argument("--brain", default=os.environ.get("BRAIN_PATH", ""))
    args = ap.parse_args()

    brain = Path(args.brain)
    if not brain.is_dir():
        sys.exit("BRAIN_PATH is not set or not a directory")
    now = date.fromisoformat(args.now) if args.now else datetime.now().date()

    stats = run(brain, args.apply, now)
    report, hit_rate = health_report(stats, now, args.apply)
    print(report)

    if args.apply:
        # Health report as a dated daily note
        (brain / "daily_notes").mkdir(exist_ok=True)
        (brain / "daily_notes" / f"{now.isoformat()}-memory-health.md").write_text(report + "\n")
        # One metrics line for longitudinal tracking
        (brain / "brain-mode").mkdir(exist_ok=True)
        metric = {
            "ts": now.isoformat(),
            "scanned": stats["scanned"],
            "used": stats["used_notes"],
            "hit_rate": round(hit_rate, 1),
            "hot": stats["by_status"].get("hot", 0),
            "warm": stats["by_status"].get("warm", 0),
            "archive": stats["by_status"].get("archive", 0),
            "tombstone": stats["by_status"].get("tombstone", 0),
            "changed": stats["changed"],
        }
        with (brain / "brain-mode" / "metrics.jsonl").open("a") as f:
            f.write(json.dumps(metric) + "\n")
        # Stamp so the lazy trigger waits another cycle
        (brain / "brain-mode" / ".brain-gardener-last").write_text(now.isoformat() + "\n")
        # Commit if the vault is a git repo (best-effort, never fatal)
        if (brain / ".git").is_dir():
            try:
                subprocess.run(["git", "-C", str(brain), "add", "-A"],
                               check=False, capture_output=True)
                subprocess.run(["git", "-C", str(brain), "commit", "-q", "-m",
                                f"gardener: {now.isoformat()} "
                                f"({stats['changed']} updated, {len(stats['transitions'])} transitions)"],
                               check=False, capture_output=True)
            except OSError:
                pass


if __name__ == "__main__":
    main()
