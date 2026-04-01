---
name: brain-linear-sync
description: Sync brain vault ticket notes with Linear — push local status to Linear, pull updates from Linear, or full bidirectional sync.
argument-hint: [push|pull|full]
---

# Brain Linear Sync — Vault ↔ Linear Synchronization

Sync the status of ticket notes in the brain vault with their corresponding Linear issues. Supports push (vault→Linear), pull (Linear→vault), and full (bidirectional with conflict detection).

**Usage**: `/brain-linear-sync [mode]`

**Examples**:
- `/brain-linear-sync` — full bidirectional sync (default)
- `/brain-linear-sync push` — push vault statuses to Linear
- `/brain-linear-sync pull` — pull Linear statuses into vault

## Prerequisites

- Linear MCP tools available (via Claude AI Linear integration)
- Ticket notes in the brain vault with `linear_id` in frontmatter

## Paths

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}`
- **Ticket notes:** `{{SET_YOUR_BRAIN_PATH}}/projects/`
- **Daily notes:** `{{SET_YOUR_BRAIN_PATH}}/daily_notes/`

## Status Mappings

### Vault → Linear (by Linear state type)

| Vault Status | Linear State Type |
|---|---|
| `pending` | `backlog` |
| `in-progress` | `started` |
| `in-review` | next state after `started` (team-specific) |
| `complete` | `completed` |
| `canceled` | `canceled` |

### Linear → Vault (by Linear state type)

| Linear State Type | Vault Status |
|---|---|
| `backlog` | `pending` |
| `unstarted` | `pending` |
| `started` | `in-progress` |
| `completed` | `complete` |
| `canceled` | `canceled` |

Unknown state types are stored in the `linear_state` frontmatter field without changing `status`.

### Priority Mapping

| Vault | Linear |
|---|---|
| `critical` | 1 (Urgent) |
| `high` | 2 (High) |
| `medium` | 3 (Normal) |
| `low` | 4 (Low) |

## Steps

### Step 0: Discover Linear Tools

Use `ToolSearch` to find available Linear MCP tools (search for "Linear"). You need:
- `list_teams` — discover teams
- `list_issue_statuses` — get team workflow states
- `get_issue` — fetch individual issue
- `list_issues` — fetch multiple issues
- `save_issue` — update issue status

If no Linear tools found:
> "Linear MCP tools are not available. Enable the Linear integration in Claude Code settings."

STOP.

### Step 1: Resolve Team and Status Map

1. Use `list_teams` to find the user's team
   - If 1 team: use it automatically
   - If multiple: present a list and ask user to pick
2. Use `list_issue_statuses` with the team ID
3. Build the status mapping table (vault status ↔ Linear state ID)

Display:
```
Linear team: {team-name}

Status mapping:
  pending     → {Linear state name} (type: backlog)
  in-progress → {Linear state name} (type: started)
  complete    → {Linear state name} (type: completed)
  canceled    → {Linear state name} (type: canceled)
```

### Step 2: Scan Vault for Ticket Notes

Search `{{SET_YOUR_BRAIN_PATH}}/projects/` for markdown files with `linear_id` in their frontmatter:

Use the Grep tool to find files containing `linear_id:` in the projects directory, then read each file's frontmatter.

Collect for each ticket note:
- File path
- `linear_id` (UUID)
- `status` (vault status)
- `linear_state` (raw Linear state name, if stored)
- `last_synced` (ISO timestamp, if stored)
- File modification time

If no ticket notes with `linear_id` found:
> "No ticket notes found with Linear IDs. Pick up a ticket first with `/brain-ticket`."

STOP.

### Step 3: Present Sync Plan

```
Linear Sync ({mode} mode)

Team: {team-name}
Tickets found: {N}

  {TICKET-ID}  {title}  vault:{status}  linear:{?}
  {TICKET-ID}  {title}  vault:{status}  linear:{?}

Proceed with {mode} sync?
```

Wait for user confirmation.

### Step 4: Execute Sync

#### Mode: PUSH (vault → Linear)

For each ticket note with a `linear_id`:
1. Read the vault `status` field
2. Map to the corresponding Linear state ID
3. Use `save_issue` to update the Linear issue status
4. Update the ticket note frontmatter:
   - `last_synced: "{ISO-8601 timestamp}"`
   - `linear_state: "{Linear state name}"`

Report each update:
```
  {TICKET-ID}: vault {status} → Linear {state-name}  ✅
```

If update fails for an issue, warn and continue to next.

#### Mode: PULL (Linear → vault)

For each ticket note with a `linear_id`:
1. Use `get_issue` to fetch the current Linear state
2. Map the Linear state type to vault status
3. If status differs from vault, update the ticket note:
   - `status: "{new-vault-status}"`
   - `linear_state: "{Linear state name}"`
   - `last_synced: "{ISO-8601 timestamp}"`

Report each update:
```
  {TICKET-ID}: Linear {state-name} → vault {status}  ✅
  {TICKET-ID}: no changes  ⏭️
```

#### Mode: FULL (bidirectional with conflict detection)

For each ticket note with a `linear_id`:
1. Fetch the Linear issue via `get_issue`
2. Compare vault status and Linear status
3. Check `last_synced` timestamp:
   - **No `last_synced`**: First sync — vault wins (push)
   - **Vault file modified after `last_synced` AND Linear updated after `last_synced`**: CONFLICT
   - **Only vault changed**: Push
   - **Only Linear changed**: Pull
   - **Neither changed**: Skip

**If conflicts detected**, present them:
```
Conflicts detected:

  {TICKET-ID}: vault says "{vault-status}" but Linear says "{linear-status}"
    1 = use vault value (push to Linear)
    2 = use Linear value (pull to vault)
    3 = skip (do nothing)

  Choose for each conflict:
```

Wait for user input before resolving conflicts.

**After conflict resolution**, execute the sync operations (push, pull, or skip for each ticket).

### Step 5: Log to Daily Note

Append to `{{SET_YOUR_BRAIN_PATH}}/daily_notes/{YYYY-MM-DD}.md`:

```markdown
- {HH:MM} — Linear sync ({mode}): {N} pushed, {N} pulled, {N} skipped, {N} conflicts resolved
```

### Step 6: Summary

```
Linear Sync Complete ({mode})

  Pushed:    {N} tickets (vault → Linear)
  Pulled:    {N} tickets (Linear → vault)
  Conflicts: {N} resolved ({N} vault wins, {N} Linear wins)
  Skipped:   {N} (no changes)

All ticket notes updated with last_synced timestamps.
```

## Error Handling

| Error | Action |
|-------|--------|
| Linear tools unavailable | STOP with setup instructions |
| No ticket notes with linear_id | STOP — suggest `/brain-ticket` first |
| Individual issue fetch fails | Warn, skip that issue, continue |
| Individual status update fails | Warn, skip that issue, continue |
| Unknown Linear state type | Store raw name in `linear_state`, don't change `status` |
| Vault write fails | Warn and continue |

## Design Principles

- **Never auto-resolve conflicts.** If both sides changed, always ask the user.
- **Fail per-issue, not per-sync.** One bad ticket shouldn't stop the whole sync.
- **Timestamps are truth.** `last_synced` drives conflict detection — always update it after successful sync.
- **Stay additive.** Only update frontmatter fields, never delete content from ticket notes.
- **No config files needed.** Team discovery and status mapping happen automatically via Linear MCP tools.
