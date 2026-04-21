# Standard Operating Procedure: Binding a New Project to Linear

> **Goal:** every piece of work Claude does in a directory is tracked somewhere in Linear, with the right granularity for its scope — without forcing a mid-flow decision every session.

## Core Principle

Track everything, but match the Linear hierarchy to the scope of the work. Linear's hierarchy is:

```
Workspace → Team → Project → Issue
```

Use each layer for what it's for:

| Layer | When to create a new one |
|---|---|
| **Team** | New domain / client / ongoing body of work — something you'll accumulate work against for months or years. Rare. |
| **Project** | New substantial project within an existing domain — multi-phase, multi-week, or ≥5 planned issues. Frequent. |
| **Issue in Inbox team** | One-offs, scratch work, quick fixes, exploratory investigations. Default. |

Never create a new Linear **team** for a 30-minute bash script. Never file a 6-month product build as loose issues in the Inbox. The SOP's job is to match scope to layer.

## The Three-Tier Decision Tree

When Claude encounters a directory without a `.brain.md` binding and the user asks for any Linear-related action (create ticket, list issues, file bug, etc.), walk this tree **before** calling any Linear MCP tool:

### Step 1 — Does this work belong to an existing team I already have?

Claude runs `list_teams` and shows the user the current teams. User answers:

- **"Yes, team X"** → skip to Step 2 (project-or-just-issue decision within that team)
- **"No, this is a new domain"** → go to Step 3 (new team creation)
- **"Not sure / this is a quick one-off"** → use the **Inbox** team directly, file issues there, skip `.brain.md` for now

### Step 2 — Is this substantial enough for its own Linear project?

Apply the threshold. This is a substantial project if **any** of these are true:

- It will span multiple weeks / months
- It has multiple phases or milestones planned
- You expect ≥5 issues over its lifetime
- It has a distinct scope that deserves a named initiative in Linear

If yes:
- Claude calls `save_project` with the project name, team, description, start/target dates if known
- Bind the Linear project ID in `.brain.md` alongside the team ID

If no:
- Bind only the team ID in `.brain.md` — no project needed
- Future issues get a label (e.g., `scratch:repo-name`) for loose grouping

### Step 3 — Genuinely new domain → create a new team

Claude asks the user for:
- **Team name** (e.g., "Brain Toolkit")
- **Team key** (3-5 uppercase letters, the prefix for issue IDs — e.g., `BRN`, `BRAIN`)

Then:

**If `LINEAR_API_KEY` is set in env:**
Claude calls the Linear GraphQL API directly via `curl` to create the team automatically:

```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"mutation($name: String!, $key: String!) { teamCreate(input: { name: $name, key: $key }) { success team { id name key } } }","variables":{"name":"{{name}}","key":"{{key}}"}}'
```

Then verify with `list_teams` that the team appears (sanity smoke-test per [[Smoke-Test Before Declaring a Fix Works]]) and bind the UUID in `.brain.md`.

**If `LINEAR_API_KEY` is not set:**
Claude tells the user: "Please create a team named '{{name}}' with key '{{key}}' in the Linear UI (Settings → Teams → New Team). Let me know when done and I'll bind it." User creates manually; Claude looks up the UUID via `list_teams` and binds.

## The `.brain.md` Shape

Once bound, `.brain.md` at the repo root contains:

```markdown
# Project Context: {{repo-slug}}

## Linear Binding

- **Team name:** {{Team Name}}
- **Team ID:** `{{uuid}}`
- **Team key:** `{{KEY}}`

<!-- If a Linear project was also created: -->
- **Project name:** {{Project Name}}
- **Project ID:** `{{project-uuid}}`
- **Project slug:** `{{slug}}`

When running any Linear operation from this directory, default to this team
(and project, if set) unless I explicitly name a different one.

## Repo Identity

- Brain project tag: `{{slug}}`
- GitHub: `{{owner/repo}}`
- Default branch: `main` or `master`
- Role: {{one-sentence description}}
```

## Automated Detection (Where in the Flow)

Two trigger points where Claude auto-invokes the SOP without the user having to remember:

### Trigger 1 — On first Linear-related action without a binding

Before executing any of these Linear MCP calls in a directory without `.brain.md`:
- `save_issue` (create ticket)
- `list_issues` (without an explicit `team` argument)
- `list_cycles`, `list_milestones`, `list_projects` (without explicit team)
- Any scoped Linear operation where team defaulting matters

Claude pauses and says:

> "This directory isn't bound to a Linear team yet. I can:
> 1. Run `/brain-bind-project` now (recommended — walks the decision tree)
> 2. Scope this one action to the **Inbox** team and skip binding for now
> 3. Scope this to an existing team you'll name right now
>
> Which?"

No silent default to "first team in list" — that's how work gets misfiled.

### Trigger 2 — On `/gsd-new-project`

When the GSD workflow initializes a new project, it should include a Linear-binding step in its flow so that by the time the project is set up, `.brain.md` is populated.

*Implementation note:* `gsd-new-project` is an external skill (installed via GSD, not part of this toolkit). Hooking into it requires either a companion post-hook or a PR to GSD. Tracking as a separate follow-up.

## Threshold Guidance (Fast Reference)

When you're in the moment and the SOP asks "substantial enough for its own project?", apply these heuristics:

| Signal | Leans toward |
|---|---|
| Has a README, a `PROJECT.md`, or a planned changelog | Own project |
| One script you're about to throw away | Inbox issue, no project |
| You're making a PR branch you care about | Own project |
| You opened this dir to tweak something for 5 minutes | Inbox issue |
| Multiple collaborators or milestones planned | Own team **or** own project within existing team |
| You'd be embarrassed to file it as "Misc work" | Own project |
| It's `claude-brain-toolkit` scale (long-lived, many facets, public distribution) | Own team |

When in doubt, bind to an existing team and don't create a Linear project. You can always promote later — loose issues can be moved into a new project; team → project migration is harder but possible.

## Setup Prerequisites (One-Time)

Before `/brain-bind-project` can automate team creation, the user needs:

1. **Linear API key** — generate at https://linear.app/settings/account/security (Personal API keys section). Scope: workspace access.
2. **Export in shell profile:**
   ```bash
   export LINEAR_API_KEY="lin_api_..."
   ```
   Add to `~/.bashrc` / `~/.zshrc` / shell profile so it persists.
3. **Bootstrap the Inbox team:**
   ```bash
   bash scripts/bootstrap-linear-inbox.sh
   ```
   Idempotent — creates the Inbox team if it doesn't exist, silently passes if it does.

Without `LINEAR_API_KEY`: the SOP still works, but Team creation (Step 3) requires manual Linear UI steps.

## Related Patterns

- [[Project Dir → External Service Binding via .brain.md]] — the general pattern this SOP is an instance of
- [[Smoke-Test Before Declaring a Fix Works]] — verify team/project creation with `list_teams` / `list_projects` before binding
- [[Agent Tools Allowlist Silently Filters MCP Tools]] — troubleshooting if Linear MCP tools seem to vanish

## Revision Log

- **2026-04-21 — v1.0** — initial SOP. 3-tier structure (Team/Project/Inbox), GraphQL team creation via API key, detection on first Linear action.
