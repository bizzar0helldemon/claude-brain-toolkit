---
name: brain-handoff
description: Create a session continuity document — capture completed work, in-progress state, blockers, and decisions so the next session can pick up cleanly.
argument-hint: [--lite]
---

# Brain Handoff — Session Continuity

Create a handoff document that captures everything the next Claude session needs to continue your work seamlessly. Run this when you're wrapping up a session or approaching context limits.

**Usage**: `/brain-handoff [--lite]`

**Examples**:
- `/brain-handoff` — full handoff with context and decisions
- `/brain-handoff --lite` — quick, actionable-only handoff

## Paths

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}`
- **Handoffs dir:** `{{SET_YOUR_BRAIN_PATH}}/handoffs/`
- **Daily notes:** `{{SET_YOUR_BRAIN_PATH}}/daily_notes/`

## Steps

### Step 1: Gather Session State

Collect information from the current session and working directory:

**1a. Git state**
```bash
git branch --show-current
git log --oneline -10
git status --porcelain
git diff --stat
```

**1b. Recent file changes**
```bash
git diff --name-only HEAD~3..HEAD 2>/dev/null || git diff --name-only --cached
```

**1c. Working directory context**
- Check for `.planning/` directory — if present, read state files
- Check for any TODO/FIXME comments in recently changed files
- Note the current project and repo

**1d. Conversation context**
Scan the current conversation for:
- Decisions made (and their reasoning)
- Approaches tried that didn't work
- Open questions or blockers
- Anything the user explicitly asked to remember

### Step 2: Draft Handoff Document

**Full mode** (default):

```markdown
---
title: "Handoff — {YYYY-MM-DD}"
type: handoff
date: "{YYYY-MM-DD}"
project: "{repo-name}"
branch: "{current-branch}"
tags: [handoff, session]
---

# Handoff — {YYYY-MM-DD}

## What was accomplished

{Bullet list of completed work, with commit refs where applicable}

## What's in progress

{Bullet list of work that's started but not finished}
{Include file paths, branch state, what's left to do}

## Blockers & open questions

{Anything that's stuck or needs a decision}
{Include enough context that the next session can understand the problem}

## Key decisions made

{Decisions and their reasoning — this is critical for continuity}
{Example: "Chose to use MCP tools instead of porting Node.js scripts — simpler, no dependency"}

## What didn't work

{Approaches that were tried and abandoned, so the next session doesn't repeat them}

## Resume instructions

1. Branch: `{branch-name}`
2. Start here: {file path or task description}
3. Next step: {concrete next action}
4. Run: `{any setup commands needed}`

## Session stats

- Duration: {approximate}
- Commits: {count}
- Files changed: {count}
```

**Lite mode** (`--lite`):

```markdown
---
title: "Handoff — {YYYY-MM-DD}"
type: handoff
date: "{YYYY-MM-DD}"
branch: "{current-branch}"
tags: [handoff, lite]
---

# Handoff — {YYYY-MM-DD}

**Branch:** `{branch-name}`
**Done:** {1-2 sentence summary}
**In progress:** {what's not finished}
**Next step:** {concrete action}
**Blockers:** {if any}
```

### Step 3: Present for Review

Show the drafted handoff to the user:

```
Here's your handoff document:

{preview}

Save this? You can edit anything before I write it.
```

Wait for confirmation or edits.

### Step 4: Save

**4a. Write handoff file:**
```
{{SET_YOUR_BRAIN_PATH}}/handoffs/{YYYY-MM-DD}-handoff.md
```

If a handoff already exists for today, append a sequence number:
```
{YYYY-MM-DD}-handoff-2.md
```

Create the `handoffs/` directory if it doesn't exist.

**4b. Append to daily note:**

File: `{{SET_YOUR_BRAIN_PATH}}/daily_notes/{YYYY-MM-DD}.md`

```markdown
- {HH:MM} — Session handoff saved: [[{YYYY-MM-DD}-handoff]]
```

### Step 5: Confirm

```
Handoff saved:

  File: handoffs/{YYYY-MM-DD}-handoff.md
  Daily note: updated

Next session: open this file or tell Claude "read my last handoff" to resume.
```

## How to Resume from a Handoff

In your next session, say any of:
- "Read my last handoff"
- "Check handoffs/ for where I left off"
- "Resume from handoff"

Claude will read the most recent handoff file and pick up where you left off.

## Error Handling

| Error | Action |
|-------|--------|
| No git repo | Skip git state sections, note "not a git repo" |
| No recent commits | Skip commit history, focus on conversation context |
| BRAIN_PATH not set | Warn user, suggest `/brain-setup` |
| handoffs/ doesn't exist | Create it |

## Design Principles

- **Capture decisions, not just actions.** The *why* behind decisions is more valuable than the *what*.
- **Include negative results.** What didn't work is as important as what did — saves the next session from repeating dead ends.
- **Make resume actionable.** "Start here, do this next" — not vague summaries.
- **Stay additive.** Never overwrite existing handoff files.
