---
name: brain-bind-project
description: Bind the current project directory to a Linear team (and optionally a Linear project) by writing .brain.md. Walks the 3-tier decision tree defined in docs/NEW-PROJECT-SOP.md. Invoke on first Linear-related action in a directory without a binding, or whenever you want to re-scope.
argument-hint: [--inbox-only]
---

# Brain Bind Project — Directory → Linear Binding

Wire the current directory to a Linear team (and optionally a Linear project) so every future brain-mode session here knows which Linear scope to use without asking.

**Usage:**
- `/brain-bind-project` — walk the full decision tree interactively
- `/brain-bind-project --inbox-only` — skip the tree, bind this directory to the Inbox team as a quick fallback

**When this runs:**
- User invokes it explicitly
- brain-mode agent auto-invokes it when a Linear MCP call is attempted in a directory without a `.brain.md` binding

## Reference

The full decision procedure lives in `docs/NEW-PROJECT-SOP.md` at the toolkit root. Read that for the *why* and threshold guidance. This skill implements the *how*.

## Prerequisites Check

Before any tree-walking, verify:

1. **Linear MCP tools are available.** Use `ToolSearch` with query `"select:mcp__claude_ai_Linear__list_teams,mcp__claude_ai_Linear__save_project,mcp__claude_ai_Linear__get_team"` to load schemas. If `list_teams` is missing, tell the user:
   > "Linear MCP tools aren't available. Make sure `claude.ai Linear` is connected (run `/mcp` in Claude Code) and re-auth if needed."
   STOP.

2. **Current directory is a git repo** (or the user confirms it's a legitimate project dir). Run `git rev-parse --show-toplevel` to find the repo root. If not a git repo, ask the user: "This directory isn't a git repo. Bind anyway using the current dir as project root? (yes/no)". If no, STOP.

3. **`.brain.md` does not already exist at the repo root.** If it does, read it, show its current binding, and ask:
   > "This directory is already bound to {{team}} (and {{project}} if set). Rebind? (yes/no/adjust)"
   If no, STOP. If adjust, ask what the user wants changed and skip to the relevant step.

4. **`LINEAR_API_KEY` detection.** Check if `$LINEAR_API_KEY` is set (`[[ -n "${LINEAR_API_KEY:-}" ]]`). Record as `HAS_API_KEY=true/false`. This determines whether Step 3 (new team creation) can be automated.

## --inbox-only Mode (Fast Path)

If the user invoked `/brain-bind-project --inbox-only`:

1. Look up the Inbox team: `list_teams` with `query: "Inbox"`. If not found, tell the user:
   > "No Inbox team exists yet. Run `bash scripts/bootstrap-linear-inbox.sh` first (requires `LINEAR_API_KEY`), then re-run this command."
   STOP.
2. Write `.brain.md` with Inbox team binding (use the template in Step 4 below).
3. Report success and exit. Do NOT walk the decision tree.

## Step 1 — Existing Team or New?

List current teams and present them to the user:

```
Current Linear teams in your workspace:

1. Brain Toolkit (key: BRN)  — [bound to: claude-brain-toolkit]
2. Inbox (key: INBOX)         — fallback for unbound work
3. [...other teams...]

For this directory ({{repo-name}}), which is right?

(a) Use an existing team — tell me the number or name
(b) New team — this is genuinely new domain work
(c) Not sure — I'll file to Inbox for now and rebind later
```

Branch based on answer:
- **(a) existing team** → jump to Step 2
- **(b) new team** → jump to Step 3
- **(c) unsure/Inbox** → use Inbox team, jump to Step 4 (skip project creation)

## Step 2 — Project-or-Just-Team?

Ask the user to apply the threshold:

```
Bound to team: {{team-name}}.

Now: does this directory deserve its own Linear *project* within that team?

Heuristic (say 'yes' if ANY of these match):
- Multi-week or multi-month scope
- Multiple phases / milestones planned
- ≥5 issues expected over its lifetime
- Has a README, PROJECT.md, or planned changelog
- You'd be embarrassed to file it as "Misc work"

(y) Yes — create a Linear project
(n) No — just bind the team; issues will be loose within it
```

Branch:
- **Yes** → ask for project metadata:
  - **Project name** (default: repo name humanized — e.g., `claude-brain-toolkit` → `Claude Brain Toolkit`)
  - **Short summary** (one line, ≤255 chars)
  - **Target date** (optional, ISO format) — "no" to skip
  - **Icon emoji** (optional) — "no" to skip
  
  Then call `save_project`:
  ```
  mcp__claude_ai_Linear__save_project
    name: "{{project-name}}"
    addTeams: ["{{team-id-or-key}}"]
    summary: "{{summary}}"
    description: "Directory: {{path-from-git-root}}\nRepo: {{github-url if found}}"
    targetDate: "{{iso-date or omit}}"
    icon: "{{:emoji: or omit}}"
  ```
  
  Capture the returned project `id` and slug. Verify creation by fetching the project back (`list_projects` with the id) — this is the smoke test per [[Smoke-Test Before Declaring a Fix Works]].

- **No** → proceed to Step 4 with only team info, no project.

## Step 3 — Create a New Team

Ask the user for:
- **Team name** — e.g., "Brain Toolkit"
- **Team key** — 2-5 uppercase letters, will prefix issue IDs (e.g., `BRN` → `BRN-42`). Suggest a default from the name (first 3-5 consonants uppercase).
- **Description** — one line, optional

### If HAS_API_KEY=true (automated creation)

Run via Bash:

```bash
curl -sS -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg name '{{team-name}}' \
    --arg key '{{team-key}}' \
    --arg desc '{{description}}' \
    --arg query 'mutation($name: String!, $key: String!, $description: String) { teamCreate(input: { name: $name, key: $key, description: $description }) { success team { id name key } } }' \
    '{query: $query, variables: {name: $name, key: $key, description: $desc}}')"
```

Check the response:
- If `.errors` present → show the error, ask the user to resolve (common: key collision, invalid characters in key). STOP or loop.
- If `.data.teamCreate.success == true` → extract `.data.teamCreate.team.id` and `.key`.

**Smoke-test:** call `list_teams` with `query: "{{team-name}}"` and confirm the new team UUID appears in results. If not, STOP and investigate — do not bind to an unconfirmed UUID.

### If HAS_API_KEY=false (manual creation)

Tell the user:

> "I don't have `LINEAR_API_KEY` set, so I can't create the team programmatically. Please:
>
> 1. Open https://linear.app/settings/teams
> 2. Create a new team: name = **{{team-name}}**, key = **{{team-key}}**
> 3. Reply 'done' when the team exists in Linear
>
> I'll then look it up and bind it."

After user confirms, run `list_teams` with `query: "{{team-name}}"` to find the UUID. If not found, tell the user to double-check and retry.

Then loop to Step 2 (project-or-just-team decision) within the newly-created team.

## Step 4 — Write `.brain.md`

Compose the binding file at `{{repo-root}}/.brain.md`:

```markdown
# Project Context: {{repo-slug}}

{{one-line-description — inferred from README or CLAUDE.md if available, else ask user}}

## Linear Binding

- **Team name:** {{Team Name}}
- **Team ID:** `{{team-uuid}}`
- **Team key:** `{{KEY}}`
{{#if project}}
- **Project name:** {{Project Name}}
- **Project ID:** `{{project-uuid}}`
- **Project slug:** `{{slug}}`
{{/if}}

When running any Linear operation from this directory, default to this team{{#if project}} and project{{/if}} unless the user explicitly names a different one.

## Repo Identity

- **Brain project tag:** `{{repo-slug}}` (for vault frontmatter / project-scoped search)
- **GitHub:** `{{owner/repo or 'local-only'}}`
- **Default branch:** `{{master or main}}`
- **Role:** {{short description from README, CLAUDE.md, or user input}}

## Operational Notes

{{any project-specific notes the user wants Claude to know at session start — build commands, deployment target, etc.}}
```

## Step 5 — Gitignore Handling

Check if `.brain.md` is gitignored in this repo:

```bash
git check-ignore -v .brain.md
```

- **If already gitignored:** nothing to do.
- **If NOT gitignored and the repo is public:** ask the user:
  > "This repo appears to be public (or has a remote on GitHub/public host). `.brain.md` contains your Linear team UUID, which is personal data you probably don't want to commit. Add `.brain.md` to `.gitignore`? (y/n — recommend y)"
  If y: append `.brain.md` to `.gitignore` with a comment like `# Project-local brain context — personal IDs`.
- **If NOT gitignored and the repo is private:** ask but default suggestion is n (private repos benefit from committing the binding so teammates' sessions inherit it).

## Step 6 — `.brain.md.example` for Public Toolkit Repos

If this directory is a toolkit-style repo (has `README.md` suggesting distribution to others, has a LICENSE, has a `setup.sh` or onboarding script), offer:

> "This looks like a repo others will clone. Want me to create a `.brain.md.example` template they can copy and fill in with their own values? (y/n)"

If y: write a generic template to `.brain.md.example` with placeholders, committed.

## Step 7 — Confirm and Report

Show the user:

```
✓ Bound {{repo-name}} to Linear.

.brain.md written at: {{path}}
Team:    {{Team Name}} ({{KEY}}) — {{uuid}}
Project: {{Project Name or '(none — team-level binding only)'}}

Future sessions in this directory will load this binding automatically.
First Linear action will default to this scope unless you override.

Next:
- Commit .brain.md.example if created (in a public repo)
- Run /daily-note or your first-action workflow to test the binding
```

## Error Handling

Common failure modes:

| Issue | Response |
|---|---|
| Linear MCP not connected | "Run `/mcp`, re-auth `claude.ai Linear`, then re-run this command." |
| LINEAR_API_KEY missing when user chose new-team path | Offer to fall back to manual UI creation (Step 3 manual branch) |
| Team key collision (`key already exists`) | Ask user for a different key; suggest the name minus vowels |
| User invokes in a non-git-repo dir | Confirm with user; use `pwd` as repo-root if they proceed |
| `.brain.md` already exists | Read it, show binding, ask if they want to rebind |
| Network error on GraphQL | Retry once; if still failing, report and let user retry |

## Related

- `docs/NEW-PROJECT-SOP.md` — the procedure this skill implements
- `scripts/bootstrap-linear-inbox.sh` — one-time Inbox team creation
- `.brain.md.example` — template shown to users cloning a toolkit repo
- Vault pattern: [[Project Dir → External Service Binding via .brain.md]]
