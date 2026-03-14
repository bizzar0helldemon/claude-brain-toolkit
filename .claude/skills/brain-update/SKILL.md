---
name: brain-update
description: Update an existing project's brain entry after doing more work on it. Re-reads source files, shows what changed, and regenerates the summary, archive, and project index row.
argument-hint: <project-name-or-path>
---

# Brain Update Command

You are updating an existing project's brain entry after the user has done more work on it. This is the fast path for "I just worked on X, update the brain."

## Your Task

The user provides a project name or path (as $ARGUMENTS). You must:

1. Find the matching project in `projects/_INDEX.md`
2. Re-read the project's source files (CLAUDE.md, MEMORY.md)
3. Compare against the existing brain entry and show what changed
4. Regenerate the summary, archive, and project index row

## Step-by-Step Process

### Step 1: Parse Arguments — Name vs Path

Examine `$ARGUMENTS` to determine if the user provided a **name** or a **path**:

- **Path** (contains `\`, `/`, or `:`): Match against the Location column in `projects/_INDEX.md`
- **Name** (anything else): Fuzzy match against the Project column in `projects/_INDEX.md` (case-insensitive, partial match — e.g., `webapp` matches "My Web App", `trading` matches "Trading Bot")
- **No argument**: Read `projects/_INDEX.md`, list all projects with their index number, and ask the user which one to update

### Step 2: Look Up the Project

Read `projects/_INDEX.md` (in the brain root directory) and find the matching row.

**Handle edge cases:**
- **No match found** → Tell the user: "Project not found in project index. Use `/brain-scan [path]` to add a new project."
- **Multiple matches** → List all matches and ask the user to clarify which one (e.g., `app` could match "Weather App" or "Chat App")
- **Source directory missing/moved** → If the Location path doesn't exist, ask the user for the new path and note that you'll update the Location field

### Step 3: Read Existing Brain Entry

From the matched project, determine the category and slug from the existing files. Read:
- **Summary**: `projects/[category]/[slug].md`
- **Archive**: `archive/raw-claude-mds/[category]/[slug]-CLAUDE.md`
- **Project index row**: The row you already found

Store these as the "before" snapshot for the changelog.

### Step 4: Re-Read Source Files

Go to the project's actual location (from the Location column) and read:
- `CLAUDE.md` (required — if missing, warn and ask the user)
- `MEMORY.md` (optional — check both the project directory and any Claude Code memory mirror paths listed in the existing summary's Key Files section)

Also check for additional CLAUDE.md files in subdirectories if the project previously had multiple archived files.

### Step 5: Show Changelog

Compare the old brain entry against the fresh source files. Report changes in these categories:

```
## What Changed

**Status:** [old status] → [new status] (or "unchanged")
**Tech Stack:** [+added, -removed, or "unchanged"]
**Key Accomplishments:** [new items added, or "unchanged"]
**Current State:** [what's different]
**Lessons Learned:** [new lessons, or "unchanged"]
**Other:** [any other notable changes — file paths, project name, etc.]
```

If **nothing has changed**, tell the user: "No changes detected in source files since last scan. The brain entry is up to date." Then offer: "Want me to force-regenerate anyway? (This rewrites the files using current templates.)"

If the user declines, stop here.

### Step 6: Regenerate Brain Entry

Using the templates from `brain-scan-templates.md` (in the brain root directory), regenerate:

1. **Archive** — Overwrite `archive/raw-claude-mds/[category]/[slug]-CLAUDE.md` with the fresh CLAUDE.md content
2. **Summary** — Overwrite `projects/[category]/[slug].md` using the Project Summary Template (include frontmatter with tags, type, status, related)
3. **Project index row** — Update the matching row in `projects/_INDEX.md` using `[[wiki links]]` for the project name (preserve all other rows, update footer counts if status changed)

**Important formatting rules:**
- Follow the templates from `brain-scan-templates.md` exactly
- Keep the same category and slug unless the project has fundamentally changed
- If the project's category has changed, move files to the new category folder and remove from the old one
- Update the project index footer (Total count, Status Breakdown) if status changed
- Ensure all `[[wiki links]]` are maintained for people, projects, and groups

### Step 7: Report Results

Summarize what you did:

```
## Update Complete

**Project:** [Project Name]
**Files updated:**
- `projects/[category]/[slug].md` — summary regenerated
- `archive/raw-claude-mds/[category]/[slug]-CLAUDE.md` — archive refreshed
- `projects/_INDEX.md` — row updated

**Key changes applied:**
- [bullet list of the most important changes]

Note: Portfolio files (tech-skills, project-portfolio, services) are not updated by this command.
Run `/brain-scan` for a full system rebuild including portfolio.
```

## What This Command Does NOT Do

- **Does NOT scan for new projects** — use `/brain-scan [path]` for that
- **Does NOT update portfolio files** (tech-skills.md, project-portfolio.md, services.md) — mention this to the user and suggest `/brain-scan` if they need portfolio updates
- **Does NOT change category assignments** unless the project has fundamentally changed scope
- **Does NOT touch other projects' entries** — only the matched project is affected

## Deduplication Rules

Same rules as brain-scan (from templates):
- Template copies (referencing a shared template) are projects USING the template
- Sub-projects under the same parent = ONE consolidated project
- Versioned directories = ONE project with multiple archived files
- Claude Code memory mirrors are references, not separate projects

---

**Usage:** `/brain-update [name-or-path]`

Examples:
- `/brain-update webapp` — fuzzy matches "My Web App", updates its entry
- `/brain-update ~/Projects/my-web-app` — matches by path, same flow
- `/brain-update trading` — fuzzy matches "Trading Bot"
- `/brain-update` — lists all projects, asks which to update
