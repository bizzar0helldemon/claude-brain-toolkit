#!/usr/bin/env python3
"""brain-backfill.py — one-time (idempotent) frontmatter repair for legacy vaults.

Stamps the `project:` key the session-start loader requires onto vault notes
that lack it, inferring the value conservatively:

  1. frontmatter `repo:` / `source:` / `target_repo:` -> kebab basename
  2. path `projects/<category>/<name>/...` or `projects/<category>/<name>.md`
  3. filename prefix match in handoffs/ against the known-project vocabulary
  4. body `**Project:** X` line or `[[Known Project]]` wikilink
  5. `tags:` entry that exactly matches a known project tag

Vocabulary comes from `$BRAIN_PATH/brain-mode/projects.tsv` (name + path
basename, both kebab-cased). Files with no confident inference are left
untouched and reported — never guessed, never stamped `global` silently.

Usage:
  python3 brain-backfill.py            # dry run (default): report only
  python3 brain-backfill.py --apply    # write changes
"""

import os
import re
import sys
from pathlib import Path

SKIP_DIRS = {".obsidian", ".git", ".brain-search-vectors"}
INFER_KEYS = ("repo", "target_repo", "source")

# Aggregator/global files must never be pinned to one project
SKIP_NAMES = {"_index.md", "master_index.md", "identity.md", "claude.md",
              "brain-scan-templates.md"}

# Placeholder-shaped values that a template (not a real project) produced
BAD_TAGS = {"project-name", "project", "name", "your-project", "x", "n-a", "none", "tbd"}


def kebab(s: str) -> str:
    s = s.strip().strip("`\"'")
    s = re.sub(r"[\s_]+", "-", s)
    s = re.sub(r"[^A-Za-z0-9.-]", "", s)
    return s.lower().strip("-")


def load_vocab(brain: Path) -> dict:
    """Map kebab-tag -> kebab-tag, plus original display names for body matching."""
    vocab = {}
    tsv = brain / "brain-mode" / "projects.tsv"
    if tsv.exists():
        for line in tsv.read_text(errors="ignore").splitlines():
            parts = line.split("\t")
            if not parts or not parts[0].strip():
                continue
            name = parts[0].strip()
            vocab[kebab(name)] = kebab(name)
            if len(parts) > 1 and parts[1].strip():
                base = kebab(os.path.basename(parts[1].strip().rstrip("/")))
                if base:
                    vocab[base] = kebab(name)
    return vocab


def split_frontmatter(text: str):
    if not text.startswith("---"):
        return None, text
    m = re.match(r"^---\n(.*?)\n---\n?", text, re.DOTALL)
    if not m:
        return None, text
    return m.group(1), text[m.end():]


def infer(path: Path, fm: str, body: str, vocab: dict, brain: Path):
    rel = path.relative_to(brain)

    # 1. frontmatter repo/source/target_repo
    for key in INFER_KEYS:
        m = re.search(rf"^{key}:\s*(.+)$", fm, re.MULTILINE)
        if m:
            val = m.group(1).strip()
            if "/" in val or val.endswith(".git"):
                cand = kebab(os.path.basename(val.rstrip("/").removesuffix(".git")))
            else:
                cand = kebab(val)
            if cand and (cand in vocab or key != "source"):
                return vocab.get(cand, cand), f"frontmatter {key}:"

    # 2. path under projects/
    parts = rel.parts
    if parts[0] == "projects" and len(parts) >= 3:
        name = parts[2] if len(parts) > 3 or not parts[2].endswith(".md") else parts[2][:-3]
        cand = kebab(name)
        if cand and cand not in {"_index", "working-notes", "readme"}:
            return vocab.get(cand, cand), "projects/ path"

    # 3. handoffs/<project>-... filename prefix
    if parts[0] == "handoffs":
        stem = kebab(path.stem)
        for tag in sorted(vocab, key=len, reverse=True):
            if stem.startswith(tag):
                return vocab[tag], "handoff filename"

    # 4. body **Project:** or wikilink to a known project.
    # Wikilink inference only in narrow, single-subject dirs — aggregator
    # documents (portfolio, frameworks, indexes) link to many projects.
    m = re.search(r"\*\*Project:?\*\*[:\s]*([^\n|]+)", body)
    if m:
        cand = kebab(m.group(1))
        if cand and cand not in BAD_TAGS and "[" not in m.group(1):
            return vocab.get(cand, cand), "body **Project:**"
    if parts[0] in {"daily_notes", "intake", "people", "handoffs", "docs"}:
        for link in re.findall(r"\[\[([^\]|#]+)", body):
            cand = kebab(link)
            if cand in vocab:
                return vocab[cand], f"wikilink [[{link}]]"

    # 5. tags: exact known-project tag
    m = re.search(r"^tags:\s*\[([^\]]*)\]", fm, re.MULTILINE)
    if m:
        for tag in m.group(1).split(","):
            cand = kebab(tag)
            if cand in vocab:
                return vocab[cand], "tags:"

    return None, None


def main():
    apply = "--apply" in sys.argv
    brain = Path(os.environ.get("BRAIN_PATH", ""))
    if not brain.is_dir():
        sys.exit("BRAIN_PATH is not set or not a directory")

    vocab = load_vocab(brain)
    stamped, unresolved, already = [], [], 0

    for path in sorted(brain.rglob("*.md")):
        if any(p in SKIP_DIRS for p in path.parts):
            continue
        if path.name.lower() in SKIP_NAMES:
            continue
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        fm, body = split_frontmatter(text)
        if fm is None:
            continue  # no frontmatter — nothing to repair safely
        if re.search(r"^project:", fm, re.MULTILINE):
            already += 1
            continue

        tag, how = infer(path, fm, body, vocab, brain)
        rel = str(path.relative_to(brain))
        if not tag:
            unresolved.append(rel)
            continue

        stamped.append((rel, tag, how))
        if apply:
            new_fm = fm + f"\nproject: {tag}"
            path.write_text(f"---\n{new_fm}\n---\n{body}")

    mode = "APPLIED" if apply else "DRY RUN"
    print(f"[{mode}] vocab={len(vocab)} tags | already had project:={already} | "
          f"stamped={len(stamped)} | unresolved={len(unresolved)}")
    for rel, tag, how in stamped:
        print(f"  + {rel}  ->  project: {tag}   ({how})")
    if unresolved:
        print(f"\nUnresolved (left untouched): {len(unresolved)}")
        for rel in unresolved[:20]:
            print(f"  ? {rel}")
        if len(unresolved) > 20:
            print(f"  ... and {len(unresolved) - 20} more")


if __name__ == "__main__":
    main()
