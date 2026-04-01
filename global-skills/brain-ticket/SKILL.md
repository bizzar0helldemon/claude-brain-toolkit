---
name: brain-ticket
description: Pick up a Linear ticket — fetch details, create branch, update status, and log to brain vault.
argument-hint: <TICKET-ID> [--worktree]
---

# Brain Ticket — Linear Ticket Pickup

Pick up an issue from Linear, set up a working branch, update the ticket status, and log context to the brain vault.

**Usage**: `/brain-ticket TICKET-ID [--worktree]`

**Examples**:
- `/brain-ticket ENG-42` — pick up ticket ENG-42
- `/brain-ticket` — browse your backlog and choose a ticket
- `/brain-ticket ENG-42 --worktree` — pick up in an isolated git worktree

## Prerequisites

This skill uses Linear MCP tools (provided via Claude AI's Linear integration). If Linear tools are unavailable, it will tell you how to set them up.

## Paths

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}`
- **Projects dir:** `{{SET_YOUR_BRAIN_PATH}}/projects/`
- **Daily notes:** `{{SET_YOUR_BRAIN_PATH}}/daily_notes/`

## Steps

### Step 0: Discover Linear Tools

Use `ToolSearch` to find available Linear MCP tools (search for "Linear"). You need:
- `get_issue` — fetch ticket details
- `list_issues` — browse backlog
- `list_issue_statuses` — get team workflow states
- `save_issue` — update ticket status
- `list_teams` — discover teams

If no Linear tools are found:
> "Linear MCP tools are not available. To set up Linear integration:
> 1. Go to Claude Code settings
> 2. Enable the Linear integration under MCP servers
> 3. Authenticate with your Linear account
> Then try `/brain-ticket` again."

STOP. Do not proceed without Linear tools.

### Step 1: Identify Ticket

**If `$ARGUMENTS` contains a ticket ID** (pattern: `[A-Z]+-\d+`, e.g., `ENG-42`):
- Fetch the ticket using the `get_issue` tool with that ID

**If no ticket ID provided**:
- Use `list_teams` to find the user's team
- Use `list_issues` filtered to the user's assigned, unstarted issues
- Present up to 10 tickets as a numbered list:
  ```
  Your backlog:

  1. ENG-42 — Fix auth token refresh  [High]
  2. ENG-43 — Add CSV export endpoint  [Medium]
  3. ENG-45 — Update dashboard layout  [Low]

  Pick a ticket (number or ID):
  ```
- Wait for the user to select before proceeding.

### Step 2: Confirm Pickup

Present the ticket details clearly:

```
Ticket: {ID} — {title}
Status: {current status}
Priority: {priority}
Description: {first 3 lines of description}

Branch: feat/{ticket-id-lowercase}-{slug}

Pick up this ticket?
```

Wait for user confirmation before proceeding.

### Step 3: Create Branch

Derive the branch name from the ticket: `feat/{ticket-id-lowercase}-{slug}`
- Slug: lowercase title, spaces to hyphens, max 40 chars, strip special chars

```bash
git checkout -b feat/{branch-name}
```

If `--worktree` flag is set:
```bash
git worktree add ../brain-worktrees/feat/{branch-name} -b feat/{branch-name}
```
Then tell the user:
```
Worktree created at ../brain-worktrees/feat/{branch-name}

Next steps:
  cd ../brain-worktrees/feat/{branch-name} && claude

Start a new Claude session in that directory to continue.
```
STOP here if worktree mode — the user continues in the new session.

### Step 4: Update Linear Status

Use the `save_issue` tool to update the ticket status to "In Progress":
1. First, use `list_issue_statuses` to find the team's "started" type state
2. Then use `save_issue` with the issue ID and the started state ID

If the update fails, warn but continue — Linear status is nice-to-have, not blocking.

### Step 5: Log to Brain Vault

**5a. Create or update a ticket note** in the brain vault:

File: `{{SET_YOUR_BRAIN_PATH}}/projects/{ticket-id}.md`

```markdown
---
title: "{ticket-id} — {title}"
type: ticket
status: in-progress
linear_id: "{linear-uuid}"
linear_url: "https://linear.app/issue/{ticket-id}"
branch: "feat/{branch-name}"
started: "{YYYY-MM-DD}"
tags: [ticket, linear]
---

# {ticket-id} — {title}

## Description

{ticket description from Linear}

## Priority

{priority}

## Notes

_Work notes will accumulate here._
```

If the file already exists, read it and update the `status` and `started` fields instead of overwriting.

**5b. Append to daily note:**

File: `{{SET_YOUR_BRAIN_PATH}}/daily_notes/{YYYY-MM-DD}.md`

If the file exists, append. If not, create it with a header first:

```markdown
- {HH:MM} — Started ticket {TICKET-ID}: {title} (branch: feat/{branch-name})
```

### Step 6: Summary

```
Ticket picked up:

  {TICKET-ID}: {title}
  Branch: feat/{branch-name}
  Linear: In Progress
  Vault: projects/{ticket-id}.md

You're ready to work. When done, run /brain-ship to push a PR and update Linear.
```

## Error Handling

| Error | Action |
|-------|--------|
| Ticket not found in Linear | Show error, ask user to verify the ID |
| Branch already exists | Ask if user wants to check it out instead |
| Linear status update fails | Warn and continue — don't block work |
| No write access to brain vault | Show BRAIN_PATH error, suggest running `/brain-setup` |
| Git working tree dirty | Warn about uncommitted changes, ask to proceed or stash |

## Design Principles

- **Don't block work.** Linear updates and vault writes are helpful but not mandatory. If they fail, warn and move on.
- **Suggest, don't dictate.** Propose the branch name and let the user adjust.
- **Stay additive.** Never delete or overwrite existing vault notes. Append or update fields.
- **Keep it simple.** No lock files, no daemon, no autonomous mode. Just pick up a ticket and go.
