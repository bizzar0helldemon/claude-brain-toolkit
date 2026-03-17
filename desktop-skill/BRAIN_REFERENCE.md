# Brain Reference — Vault Structure & Formats

This document is the technical reference for the Brain Assistant skill. It contains the vault structure, file formats, frontmatter specs, and CLI command mapping. The SKILL.md file references this document for all formatting decisions.

---

## Vault Directory Structure

```
claude_brain/
├── CLAUDE.md                   # Root hub document — routing table, project categories, active focus
├── IDENTITY.md                 # Personal profile (populated by /brain-intake)
├── brain-scan-templates.md     # Canonical formatting templates
├── daily_notes/                # Journal entries (one file per day)
│   └── YYYY-MM-DD.md
├── projects/
│   ├── _INDEX.md               # Master project table
│   └── [category]/             # Summaries by category
│       └── [project-slug].md
├── creative/
│   └── _INDEX.md               # Creative works index
├── prompts/
│   ├── _INDEX.md               # Prompt & pattern library index
│   └── [domain]/               # Patterns by domain
│       └── [pattern-slug].md
├── intake/
│   ├── _INDEX.md               # Intake session index
│   ├── sessions/               # Interview transcripts
│   └── discoveries/            # Drive scan results
├── people/                     # People notes
│   └── [person-slug].md
├── portfolio/                  # Career/consulting portfolio
│   ├── tech-skills.md
│   ├── project-portfolio.md
│   └── services.md
├── archive/
│   └── raw-claude-mds/         # Verbatim copies of source CLAUDE.md files
│       └── [category]/
├── frameworks/                 # Reference frameworks (AI fluency, governance)
└── .claude/
    └── skills/                 # Project-scoped CLI skills
        ├── brain-scan/SKILL.md
        ├── brain-update/SKILL.md
        ├── brain-intake/SKILL.md
        ├── brain-discover/SKILL.md
        └── brain-audit/SKILL.md
```

---

## File Formats

### Daily Note (`daily_notes/YYYY-MM-DD.md`)

```markdown
---
date: YYYY-MM-DD
type: daily-note
tags: [tag1, tag2]
---

# YYYY-MM-DD

## HH:MM - [brief topic]

[Entry content here. Write in first person, natural voice. Not corporate.]

> [!decision] Optional callout for notable decisions
> Context for why this matters.

> [!idea] Optional callout for ideas
> What makes this worth remembering.

> [!bug] Optional callout for bugs
> Root cause and resolution.

> [!insight] Optional callout for insights
> What was learned.

> [!todo] Optional callout for todos
> What needs to happen next.

#project/[name] #decision #insight

---
```

**Tag conventions:**
- `#project/[name]` — project-related work
- `#insight` — realizations or learnings
- `#decision` — architectural or design decisions
- `#bug` — bug investigations
- `#idea` — future ideas
- `#session-summary` — full session recaps

**Frontmatter `tags:` array** collects all unique tags from every entry that day (without `#`).

### Project Summary (`projects/[category]/[slug].md`)

```markdown
---
title: Project Name
category: [music|comics|writing|video|hardware|dev-tools|apps|business|games]
status: [Active|Complete|Paused|Planned|Abandoned]
location: [path to project directory]
tags: [relevant, tags]
---

# Project Name

**One-line:** [Brief description]

## What It Is
[2-3 sentences describing the project]

## Tech Stack
[Technologies used]

## Current State
[What's done, what's in progress, what's next]

## Key Accomplishments
- [Notable achievement 1]
- [Notable achievement 2]

## Lessons Learned
- [Insight from building this]
```

### Identity Profile (`IDENTITY.md`)

```markdown
---
title: Identity Profile
type: identity
tags: [identity, personal]
---

# Identity Profile

## Who I Am
[Name, role, what you do]

## Career
[Professional background, current work]

## Skills & Expertise
[Technical and non-technical capabilities]

## Creative Interests
[Hobbies, artistic pursuits, side projects]

## Communication Preferences
[How you like to work with AI — direct, detailed, casual, etc.]

## Values & Principles
[What matters to you in work and life]
```

### Prompt Pattern (`prompts/[domain]/[slug].md`)

```markdown
---
title: Pattern Name
domain: [coding|writing|music|consulting|creative|hardware|business|general|meta]
effectiveness: [high|medium|experimental]
created: YYYY-MM-DD
last-used: YYYY-MM-DD
tags: [relevant, tags]
---

# Pattern Name

## When to Use
[Trigger or situation]

## The Prompt
[Reusable prompt template with {{placeholders}}]

## Why It Works
[What technique makes it effective]

## Variations
[Alternative phrasings]

## What Doesn't Work
[Anti-patterns]
```

---

## Obsidian Conventions

### Wiki Links
- **Projects:** `[[Project Name]]` — matches frontmatter `title:`
- **People:** `[[First Last]]` or `[[Nickname]]`
- **Groups:** `[[Group Name]]`
- Always wiki-link a project/person the first time it's mentioned in an entry

### File Naming
- **Files:** kebab-case (`my-project-name.md`)
- **Display:** Title Case via frontmatter `title:` field
- **Daily notes:** `YYYY-MM-DD.md` (date-based)

### Tags
- Frontmatter `tags:` array uses kebab-case values without `#`
- Inline tags use `#` prefix: `#project/name`, `#insight`

### Cross-Linking
- Scripts link to performers
- Shows link to scripts
- Identity links to groups
- Daily notes link to projects discussed

---

## CLI Command Mapping

Use this table when introducing CLI equivalents in conversation.

| Desktop Action | CLI Command | What It Does |
|---|---|---|
| "Log a daily note" | `/daily-note [text]` | Creates/appends to daily note file with timestamp |
| "Catalog a project" | `/brain-scan [path]` | Reads project dir, creates summary, updates index |
| "Tell me about myself" | `/brain-intake [topic]` | Guided interview, populates IDENTITY.md |
| "Find uncataloged work" | `/brain-discover [path]` | Scans drives for content not in the brain |
| "Update a project" | `/brain-update [name]` | Re-reads source, updates summary and archive |
| "Save this prompt" | `/brain-capture [hint]` | Extracts patterns from current conversation |
| "Audit vault health" | `/brain-audit` | Checks for broken links, missing frontmatter, etc. |
| "Start a new project" | `/gsd:new-project` | Full project init with research and roadmap |
| "Plan a phase" | `/gsd:plan-phase` | Creates detailed execution plan |
| "Execute work" | `/gsd:execute-phase` | Runs plan with atomic commits and verification |
| "Quick task" | `/gsd:quick` | Fast task with GSD guarantees |
| "Debug something" | `/gsd:debug` | Systematic debugging with state tracking |
| "Check progress" | `/gsd:progress` | Show project status and next actions |

---

## CLAUDE.md Template (For Bootstrap Mode)

When generating a CLAUDE.md for a new vault, use this template:

```markdown
# Claude Brain — Personal Knowledge Hub

## Identity Snapshot

> [Run `/brain-intake` or ask the Brain Assistant to interview you to fill this section]

---

## Routing Table

| Need | Go To |
|------|-------|
| Full personal profile | [[Identity Profile]] (`IDENTITY.md`) |
| All dev/creative projects | [[Project Index]] (`projects/_INDEX.md`) |
| Daily journal / session logs | `daily_notes/` directory |
| Prompt & pattern library | [[Prompt & Pattern Library]] (`prompts/_INDEX.md`) |
| Career portfolio | `portfolio/` directory |

---

## Project Categories

| Category | Count | Summary |
|----------|-------|---------|
| [Add categories as you catalog projects] | 0 | |

---

## Active Focus Areas

1. [What are you working on right now?]
2. [Update this as priorities change]

---

## Working With This Person

> [Run brain intake to fill this section with communication preferences]

---

## Obsidian Linking Conventions

- **People** — always `[[First Last]]` or `[[Nickname]]`
- **Projects** — `[[Project Name]]` matching the .md filename's frontmatter title
- **Tags** — consistent frontmatter `tags:` array (kebab-case values)
- **File naming** — kebab-case for files, Title Case for display via frontmatter `title:`
```

---

## Project Index Template (`projects/_INDEX.md`)

```markdown
---
title: Project Index
type: index
tags: [index, projects]
---

# Project Index

| Project | Category | Status | Location | One-Line Summary | Tech |
|---------|----------|--------|----------|------------------|------|
| | | | | | |

---

**Total: 0 projects**
```

---

## Prompt Library Index Template (`prompts/_INDEX.md`)

```markdown
---
title: Prompt & Pattern Library
type: index
tags: [index, prompts]
---

# Prompt & Pattern Library

| Pattern | Domain | Effectiveness | Summary |
|---------|--------|--------------|---------|
| | | | |

---

**Total: 0 patterns**
```
