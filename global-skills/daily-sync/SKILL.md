---
name: daily-sync
description: Fast operational snapshot — scan vault health, git state, pending work, and detect drift between them.
argument-hint: [--linear]
---

# Daily Sync — Operational Snapshot

Quick-scan across vault, git, and optional external systems. Returns a concise status report with priorities, discrepancies, and a recommended next action.

**Usage**: `/daily-sync [--linear]`

**Examples**:
- `/daily-sync` — vault + git scan
- `/daily-sync --linear` — also pull active Linear tickets

## Paths

- **Brain root:** `$BRAIN_PATH`
- **Handoffs:** `$BRAIN_PATH/handoffs/`
- **Learnings:** `$BRAIN_PATH/learnings/`
- **Evolution proposals:** `$BRAIN_PATH/evolution/proposals/`
- **Daily notes:** `$BRAIN_PATH/daily_notes/`

## Steps

### Step 1: Gather State

Run these checks in parallel where possible:

**Vault health (Glob + Read):**
- Count entries: learnings, prompts, projects, investigations, handoffs
- Find stale learnings past decay window (check `last_validated` dates)
- Count pending evolution proposals (`status: proposed`)
- Find most recent handoff (read its summary)
- Check `$BRAIN_PATH/.brain-errors.log` — any errors in last 24 hours?

**Git state (Bash):**
- Current branch and repo name
- Uncommitted changes (staged + unstaged + untracked count)
- Ahead/behind upstream
- Last commit message and timestamp
- Any stash entries

**Session state:**
- Read `$BRAIN_PATH/.brain-session-metrics.json` if exists (from session guardian)
- Read `$BRAIN_PATH/.brain-state` for current brain state

**Linear (optional, if `--linear` flag):**
- Use `brain-linear-sync` patterns to fetch active tickets assigned to user
- Show ticket count, top 3 by priority

### Step 2: Detect Drift

Look for discrepancies between what the vault says and what's actually happening:

| Check | Vault Says | Reality Says | Drift? |
|-------|-----------|-------------|--------|
| Recent handoff mentions "in progress on branch X" | Branch X should exist | `git branch` | Flag if branch is gone |
| Handoff says "committed feature Y" | Commit should exist | `git log --oneline -5` | Flag if commit missing |
| Evolution proposals pending | N proposals with `status: proposed` | Still relevant? | Flag if > 7 days old |
| Learnings reference a file/tool | Referenced file should exist | Glob/Read | Flag if file moved/deleted |
| Pattern store has 0-encounter patterns | Pattern should be removed | `pattern-store.json` | Flag stale patterns |

### Step 3: Identify Priorities

Rank the top 3 priorities based on:

1. **Urgency** — errors in last 24h, context warnings, stale critical learnings
2. **Continuity** — unfinished work from last handoff, pending proposals
3. **Maintenance** — vault health issues, drift items, cleanup needed

### Step 4: Present Report

```markdown
<details>
<summary>Brain: daily sync complete</summary>

## Daily Sync — {YYYY-MM-DD}

### Vault
- **Entries:** {N} learnings | {N} prompts | {N} projects | {N} investigations
- **Stale:** {N} learnings past decay window
- **Pending:** {N} evolution proposals
- **Errors (24h):** {N}

### Git
- **Repo:** {name} on {branch} {ahead/behind}
- **Working tree:** {clean | N dirty files}
- **Last commit:** "{message}" ({time ago})
- **Stashes:** {N}

### Drift
{List of drift items, or "No drift detected."}

### Top Priorities
1. {Priority 1 — what and why}
2. {Priority 2}
3. {Priority 3}

### Recommended Action
{Single recommended next step based on priorities}

</details>
```

### Step 5: Daily Note Entry

Append to `$BRAIN_PATH/daily_notes/{YYYY-MM-DD}.md`:

```markdown
- {HH:MM} — Daily sync: {N} vault entries, {N} stale, {N} drift items. Priority: {top priority summary}
```

## Error Handling

| Error | Action |
|-------|--------|
| `BRAIN_PATH` not set | Abort with setup instructions |
| No handoffs exist | Skip continuity checks, note "no prior handoffs" |
| No learnings exist | Skip staleness checks, note "vault is fresh" |
| Linear unavailable | Skip Linear section, note in report |
| Git not in a repo | Skip git section, note in report |

## Design Principles

- **Fast.** This should complete in under 10 seconds. Use Glob counts over full file reads where possible.
- **Non-disruptive.** Output in collapsed brain block. Don't block workflow.
- **Actionable.** Every drift item and priority should suggest a specific action.
- **Complementary.** This doesn't replace session-start context loading — it adds an operational analysis layer on top.
