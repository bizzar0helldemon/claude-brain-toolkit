# Brain Scan Templates

Canonical reference for `/brain:scan` and `/brain-scan` output formatting. All generated content must match these templates exactly.

---

## Project Summary Template

Used for files in `projects/[category]/[project-slug].md`:

```markdown
---
title: [Project Name]
type: project
category: [category]
status: [status]
location: "[drive:\path\to\project\]"
tags: [project, category-tag]
related: []
---

# [Project Name]
**Location:** `[drive:\path\to\project\]`

## What It Is
[2-4 sentence description of the project. What it does, what makes it unique, target audience or purpose.]

## Tech Stack
- [Tool/Framework] ([what it's used for])
- [Tool/Framework] ([what it's used for])

## Key Accomplishments
- [Specific achievement with measurable detail where possible]
- [Technical decision or system built]
- [Workflow or methodology developed]

## Current State
**Phase:** [Current phase]. [1-3 sentences on what's done and what remains.]

## Key Files
- `CLAUDE.md` → `[full path to source CLAUDE.md]`
- `MEMORY.md` → `[full path to MEMORY.md, if exists]`

## Lessons Learned
- **[Bold headline]** — [explanation of what was learned and why it matters]
- **[Bold headline]** — [explanation]
```

### Naming Convention
- File slug: lowercase, hyphens, no spaces: `my-project-name.md`
- Category folders: `music`, `comics`, `writing`, `video`, `hardware`, `dev-tools`, `apps`, `business`, `games`, `creative`

---

## Intake Session Template

Used for files in `intake/sessions/YYYY-MM-DD-topic.md`:

```markdown
---
title: "Intake: [Topic]"
date: YYYY-MM-DD
topic: [area explored]
type: guided-intake
tags: [intake, topic-tag]
integrated-into: []
---

# Intake: [Topic]

## Key Information Captured
[Structured summary of what was learned]

## Quotes & Voice Samples
> [Direct quotes that capture the person's voice, humor, perspective]

## Integration Notes
[Which files were updated with this information — links to [[Identity Profile]], relevant project pages, etc.]
```

---

## Creative Work Template

Used for standalone creative pieces in `creative/writing/`, `creative/music-ideas/`, `creative/video-concepts/`:

```markdown
---
title: [Title]
type: [writing | music-idea | video-concept | art]
date: YYYY-MM-DD
status: idea | in-progress | complete
related: ["[[Project or Person]]"]
tags: [creative, type-tag]
---

# [Title]

## Concept
[What this is, what inspired it]

## Content
[The actual creative content — lyrics, story, concept description]

## Related
- [[Linked project or person]]
```

---

## Project Index Row Format

Each project is one row in the `projects/_INDEX.md` table:

```
| [[Project Name]] | [Category] | [Status] | `[drive:\path\]` | [One-line summary] | [Comma-separated tech] |
```

**Column definitions:**
- **Project:** Human-readable project name as `[[wiki link]]`
- **Category:** One of: Music, Comics, Writing, Video, Hardware, Dev Tools, Apps, Business, Games, Creative
- **Status:** e.g. `Active — Lyrics phase`, `Complete (Template)`, `Early Dev`, `Paused — [reason]`, `~95% Phase 1`
- **Location:** Full path in backtick-quoted code format
- **One-Line Summary:** Max ~100 chars, describes what it is and key differentiator
- **Tech:** Key technologies, comma-separated

**Full table header:**
```markdown
| Project | Category | Status | Location | One-Line Summary | Tech |
|---------|----------|--------|----------|------------------|------|
```

**Footer format:**
```markdown
---

**Total: [N] unique projects** across [M] categories ([Category]: [count], ...)

**Status Breakdown:**
- Complete/Functional: [N] ([list])
- Active Development: [N] ([list])
- Near Complete: [N] ([list])
- Early/Paused: [N] ([list])
```

---

## Portfolio Templates

### tech-skills.md Structure

Group technologies by domain. Each domain is an H2 section:

```markdown
## [Domain Name]
- **[Technology]** ([versions if relevant]) — [What it's used for across projects]
```

**Standard domain sections (in order):**
1. Languages & Runtimes
2. AI / ML
3. Web & API Frameworks
4. Desktop & Browser
5. Databases
6. DevOps & Infrastructure
7. Hardware & IoT
8. Creative Tools
9. APIs & Integrations
10. Protocols & Networking

**Footer: Domain Expertise Summary table:**
```markdown
| Domain | Depth | Evidence |
|--------|-------|---------|
| [Domain] | Expert/Strong/Solid/Intermediate | [Brief evidence] |
```

### project-portfolio.md Structure

Each project is a numbered H2 section:

```markdown
## [N]. [Project Name] — [Tagline]
**Service:** [Service Category from services.md]

[2-3 sentence description of what was built.]

**What it proves:**
- [Capability demonstrated]
- [Capability demonstrated]

**Key technical decisions:** [Comma-separated list of notable decisions.]
```

**Footer: Portfolio Summary table:**
```markdown
| # | Project | Service Category | Complexity |
|---|---------|-----------------|------------|
| [N] | [Name] | [Category] | [Low/Medium/High (detail)] |
```

### services.md Structure

```markdown
## Service [N]: [Service Name]

**What:** [1-2 sentence description of the service.]

**Evidence:**
- **[Project Name]** — [How this project proves the capability.]

**Deliverable:** [What the client gets.]
```

**Standard service categories:**
1. Custom AI Application Development
2. AI Workflow Environment Design
3. Self-Hosted AI Interfaces
4. Book Editing & Manuscript Services
5. Creative AI Production
6. Hardware & IoT Solutions

---

## Prompt Pattern Template

Used for files in `prompts/[domain]/[pattern-slug].md`:

```markdown
---
title: [Pattern Name]
type: prompt-pattern
domain: [domain]
interaction-mode: [automation | augmentation | agency]
ai-fluency-dimensions: [delegation, description, discernment, diligence]
tags: [prompt, domain-tag]
effectiveness: [high | medium | experimental]
created: YYYY-MM-DD
last-used: YYYY-MM-DD
related: ["[[Related Entry]]"]
---

# [Pattern Name]

## When to Use
[Situation/trigger — when does this pattern apply?]

## The Prompt
[The actual prompt template with {{placeholders}} for variable content]

## Why It Works
[Brief explanation grounded in the 4 D's — what Description/Discernment technique makes this effective]

## Variations
[Alternative phrasings or adaptations for different contexts]

## What Doesn't Work
[Anti-patterns — approaches that seem similar but produce bad results]

## Examples
[1-2 real examples of this prompt producing good output]
```

### Field Definitions
- `domain` — matches subdirectory name: coding, writing, music, consulting, creative, hardware, business, general, meta
- `interaction-mode` — automation (AI executes task), augmentation (AI collaborates), agency (AI acts independently for others)
- `ai-fluency-dimensions` — which of the 4 D's this pattern relates to
- `effectiveness` — high (proven, consistent), medium (context-dependent), experimental (promising, needs testing)

---

## Archive Naming Convention

Raw CLAUDE.md copies go to `archive/raw-claude-mds/[category]/`:

- Format: `[project-slug]-CLAUDE.md`
- If a project has multiple source CLAUDE.md files, suffix them: `[project-slug]-[subproject]-CLAUDE.md`
- Examples:
  - `my-web-app-CLAUDE.md`
  - `trading-bot-v1-CLAUDE.md`
  - `trading-bot-v2-CLAUDE.md`
  - `music-album-CLAUDE.md`

---

## Deduplication Rules

When scanning, these patterns indicate duplicates or templates — NOT separate projects:

1. **Template copies:** If a CLAUDE.md references a template as its source, it's a project using the template, not a copy of the template itself.
2. **Sub-projects:** Multiple CLAUDE.md files under the same parent project should be archived separately but consolidated into ONE project summary.
3. **Claude Code memory mirrors:** Files at your Claude Code projects memory path (`.claude/projects/.../memory/MEMORY.md`) are Claude Code's copies of project memory — reference them in the project's Key Files section but don't create separate projects for them.
4. **Same project, different versions:** Multiple versioned directories (e.g., `My App v1`, `v2`, `v3`) are ONE project with multiple archived CLAUDE.md files.

---

## Obsidian Linking Checklist

When creating or updating any brain document, verify:

- [ ] Every person mentioned is a `[[wiki link]]`
- [ ] Every project referenced is a `[[wiki link]]`
- [ ] Every group/org is a `[[wiki link]]`
- [ ] Frontmatter includes `tags:` array
- [ ] Frontmatter includes `type:` field
- [ ] Related documents linked in frontmatter `related:` field
- [ ] File uses kebab-case naming
- [ ] Frontmatter `title:` uses Title Case display name
