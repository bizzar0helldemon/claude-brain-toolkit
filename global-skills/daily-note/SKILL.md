---
name: daily-note
description: Use when the user invokes /daily-note to log a journal entry, session summary, insight, or note into the Obsidian Daily Notes vault. Also use when the user says "add to daily notes", "journal this", or "log this".
---

# Daily Note

Log entries into the Claude Brain vault at `{{SET_YOUR_BRAIN_PATH}}/daily_notes/`.

## How It Works

1. **Determine today's date** from the system context (format: `YYYY-MM-DD`)
2. **Ask the user** what they want to log — unless they already provided content with the command (e.g., `/daily-note Had a breakthrough on the auth system`)
3. **Create or append** to `{{SET_YOUR_BRAIN_PATH}}/daily_notes/YYYY-MM-DD.md`
4. Get the current time by running `date +%H:%M` in bash

## File Format

### New file — include YAML frontmatter

When creating a new daily note file, start with frontmatter:

```markdown
---
date: YYYY-MM-DD
type: daily-note
tags: []
---

# YYYY-MM-DD
```

- The `tags:` array in frontmatter collects **all unique tags** from every entry that day. Update it each time you append.
- The `type: daily-note` property lets Dataview and search filter these notes easily.

### Each entry block

```markdown
## HH:MM - [brief topic]

[Entry content here]

#tag1 #tag2

---
```

- If the file **already exists**, read it first, then append the new entry at the bottom.
- Use `---` as a separator between entries.
- After appending, **update the frontmatter `tags:` array** to include any new tags from the entry.

## Wiki Links

Since daily notes live inside the Claude Brain vault, **use `[[wiki links]]` liberally**:

- Reference projects by name: `[[My Web App]]`, `[[Side Project]]`, `[[Music Production]]`
- Reference people: collaborator names, group names
- Reference other Brain notes: `[[Identity Profile]]`, `[[Project Index]]`
- When mentioning a project for the first time in an entry, always wiki-link it

This is the main benefit of daily notes living in the Brain — they connect to everything.

## Entry Content

The user may provide:
- **Freeform text** — log it as-is, lightly formatted
- **A request to summarize the session** — summarize what was accomplished in the current conversation
- **A specific insight or decision** — log it clearly with context

Keep entries concise. This is a journal, not documentation. Write in a natural, first-person voice as if the user is writing their own notes. Don't use corporate language.

### Callouts for notable items

Use Obsidian callouts when an entry contains a notable decision, idea, or bug:

```markdown
> [!decision] Switched from REST to WebSocket for live updates
> The polling approach was hammering the server. WebSocket cuts traffic by ~90%.

> [!idea] Could reuse the component system for the plugin architecture
> Same lifecycle hooks, different rendering targets.

> [!bug] Auth tokens expiring mid-session
> Root cause was timezone mismatch between server and JWT `exp` claim.
```

Available callout types: `[!decision]`, `[!idea]`, `[!bug]`, `[!insight]`, `[!todo]`

Only use callouts when they add clarity. A simple journal entry doesn't need one.

## Tags

### Inline tags (bottom of each entry)
- `#project/[name]` for project-related work
- `#insight` for realizations or learnings
- `#decision` for architectural or design decisions
- `#bug` for bug investigations
- `#idea` for future ideas
- `#session-summary` when the entry recaps a full work session

Only add tags that genuinely apply. Don't force them.

### Frontmatter tags
After writing an entry, update the frontmatter `tags:` array to include all unique tags used across every entry in that day's file. Use the short form (no `#`):

```yaml
tags: [project/webapp, decision, insight]
```

## Example

```markdown
---
date: 2026-03-09
type: daily-note
tags: [project/webapp, decision, insight, bug]
---

# 2026-03-09

## 14:32 - Auth system refactor

Finished migrating from JWT to session-based auth in [[My Web App]]. The main insight was that we didn't need stateless tokens at all — the app already hits the DB on every request for permissions anyway. Simplified the middleware significantly.

> [!decision] Dropped JWT in favor of server-side sessions
> Stateless tokens added complexity with no real benefit for this app's access patterns.

#project/webapp #decision #insight

---

## 16:45 - Quick fix on CI

The build was failing because of a stale lockfile. Deleted and regenerated it. Took 5 minutes.

#project/webapp #bug

---
```
