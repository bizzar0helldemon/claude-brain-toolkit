---
name: brain-ship
description: Ship completed work — push branch, create PR, update Linear ticket status, and log to brain vault.
argument-hint: [--draft] [--base <branch>]
---

# Brain Ship — Push PR & Update Linear

Ship your current branch: run preflight checks, push to remote, create a pull request, update the Linear ticket to "In Review", and log everything to the brain vault.

**Usage**: `/brain-ship [--draft] [--base <branch>]`

**Examples**:
- `/brain-ship` — ship current branch, PR against main
- `/brain-ship --draft` — create a draft PR
- `/brain-ship --base develop` — PR targeting develop

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- Linear MCP tools available (for status updates — optional, will skip gracefully)
- Current branch is NOT main/master

## Paths

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}`
- **Projects dir:** `{{SET_YOUR_BRAIN_PATH}}/projects/`
- **Daily notes:** `{{SET_YOUR_BRAIN_PATH}}/daily_notes/`

## Steps

### Step 1: Preflight Checks

Run all checks and present results as a table. Abort on hard failures.

**1a. Branch safety**
```bash
git branch --show-current
```
If on `main`, `master`, or `production`: **HARD FAIL** — "Cannot ship from a protected branch."

**1b. Remote configured**
```bash
git remote -v
```
If empty: **HARD FAIL** — "No git remote configured."

**1c. gh available and authenticated**
```bash
which gh && gh auth status
```
If missing or unauthenticated: **HARD FAIL** with install/auth instructions.

**1d. Commits ahead of base**
```bash
git rev-list --count origin/{base-branch}..HEAD
```
If 0: **HARD FAIL** — "No commits to ship."

**1e. Clean working tree** (soft check)
```bash
git status --porcelain
```
If dirty: **WARN** — list the dirty files but don't block.

Present the preflight table:
```
Preflight:

  Check                  Result
  ──────────────────────────────────
  Branch safety          ✅ feat/eng-42-fix-auth
  Remote configured      ✅ origin → git@github.com:...
  gh authenticated       ✅ Logged in as user
  Commits ahead          ✅ 5 commits ahead of main
  Clean working tree     ⚠️  2 uncommitted files

Proceed?
```

Wait for confirmation.

### Step 2: Detect Linear Ticket

Extract a ticket ID from the current branch name using pattern `[A-Z]+-\d+`:
- `feat/eng-42-fix-auth` → `ENG-42`

If found:
- Use `ToolSearch` to find Linear MCP tools
- Use the `get_issue` tool to fetch the ticket details
- Store the ticket ID, title, and Linear UUID for later

If not found or Linear tools unavailable:
- Continue without Linear integration — the PR is the primary output

Also check for a vault ticket note at `{{SET_YOUR_BRAIN_PATH}}/projects/{ticket-id}.md`. If it exists, read it for context.

### Step 3: Generate PR

**3a. Build PR title**

If Linear ticket was found:
```
[{TICKET-ID}] {type}: {concise description}
```
Where `type` is inferred from the branch prefix (`feat/` → `feat`, `fix/` → `fix`, `chore/` → `chore`, etc.)

If no ticket:
```
{type}: {concise description from branch name}
```

**3b. Build PR body**

Get the changed files and commit log:
```bash
git diff --name-only origin/{base-branch}..HEAD
git log --oneline origin/{base-branch}..HEAD
```

Compose the PR body:

```markdown
## Summary

{One paragraph summarizing what this PR does and why, synthesized from:
 - Linear ticket description (if available)
 - Commit messages
 - Changed files}

## Changes

{Bullet list of key changes, grouped by area}

## Files Changed

**Source** ({count}): {list}
**Tests** ({count}): {list}
**Config** ({count}): {list}
**Docs** ({count}): {list}

## Linear

{If ticket found: "Ticket: [{TICKET-ID}] {title} — {linear-url}"}
{If no ticket: "No Linear ticket linked."}

---
🧠 Shipped with [Claude Brain Toolkit](https://github.com/your/claude-brain-toolkit)
```

**3c. Present for review**

Show the PR title and body to the user:
```
PR Title: [{TICKET-ID}] feat: fix auth token refresh

PR Body:
{body preview}

Approve this PR? You can edit inline before confirming.
```

Wait for approval. If the user edits, capture their version.

### Step 4: Push and Create PR

**4a. Push branch**
```bash
git push -u origin HEAD
```
If rejected (non-fast-forward): STOP. Show error. Do NOT force-push.

**4b. Create PR**
```bash
gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base "$BASE_BRANCH" [--draft]
```

If PR already exists:
```bash
gh pr view --json url,number -q '{url: .url, number: .number}'
```
Use the existing PR instead of failing.

Capture the PR URL and number.

### Step 5: Update Linear

If a Linear ticket was detected in Step 2:

1. Use `list_issue_statuses` to find the team's "In Review" state (type that comes after "started")
   - Look for a state with type containing "review" or the state that follows "started" in the workflow
   - If no clear "review" state, look for any state between "started" and "completed"
2. Use `save_issue` to update the ticket status
3. Optionally add a comment via `save_comment`: "PR #{number} opened: {url}"

If Linear update fails: warn and continue. The PR is already created — that's what matters.

### Step 6: Update Brain Vault

**6a. Update ticket note** (if it exists at `{{SET_YOUR_BRAIN_PATH}}/projects/{ticket-id}.md`):
- Update `status: in-review`
- Add `pr_url: "{url}"` to frontmatter
- Append to Notes section: `- {YYYY-MM-DD} — PR #{number} opened: {url}`

**6b. Append to daily note:**

File: `{{SET_YOUR_BRAIN_PATH}}/daily_notes/{YYYY-MM-DD}.md`

```markdown
- {HH:MM} — Shipped {TICKET-ID}: {title} — PR #{number} ({url})
```

### Step 7: Summary

```
Shipped:

  Branch: feat/{branch-name} → {base-branch}
  PR #{number}: {url}
  Commits: {count} shipped
  Linear: {TICKET-ID} set to "In Review" | skipped (not found)
  Vault: projects/{ticket-id}.md updated | skipped

Next steps:
  1. Share PR for review: {url}
  2. Address review feedback
  3. After merge, pick up next ticket with /brain-ticket
```

## Error Handling

| Error | Action |
|-------|--------|
| On main/master | HARD FAIL — do not proceed |
| No remote | HARD FAIL — show `git remote add` instructions |
| gh not installed | HARD FAIL — show install URL |
| gh not authenticated | HARD FAIL — show `gh auth login` |
| No commits ahead | HARD FAIL — nothing to ship |
| Push rejected | STOP — show error, never force-push |
| PR already exists | Use existing PR, continue with updates |
| Linear tools unavailable | Skip Linear updates, continue with PR |
| Linear status update fails | Warn and continue |
| Vault write fails | Warn and continue — PR is primary output |
| Dirty working tree | Soft warning only |

## Design Principles

- **PR is king.** Everything else (Linear updates, vault writes) is secondary. Never fail the command because of a secondary write.
- **Never force-push.** If push is rejected, stop and let the user decide.
- **Stay additive.** Update vault notes, don't overwrite them.
- **Detect, don't require.** Linear ticket and vault note are auto-detected from the branch name. No config files or lock files needed.
