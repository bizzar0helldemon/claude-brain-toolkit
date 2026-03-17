---
name: brain-inbox
description: Process unorganized files dropped into the brain vault. Scans inbox/ and vault root, categorizes, formats, and routes files to correct locations.
argument-hint: "[--auto | --dry-run]"
---

# Brain Inbox — File Organizer & Onboarding Processor

You are processing unorganized files that have been dropped into the Claude Brain vault. Your job is to identify them, categorize them, format them to match brain templates, move them to the correct location, and update indexes.

## Your Task

Scan two locations for files that need processing:
1. **`inbox/`** — the designated drop zone for new files
2. **Vault root** — catch files dropped at the top level that don't belong there

Then present findings, get user approval, and process them.

## Arguments

Parse `$ARGUMENTS` for:
- **`--auto`** — skip confirmation prompts, process everything automatically
- **`--dry-run`** — show what WOULD happen without making changes
- No arguments = interactive mode (default)

## Vault Location

Determine the brain vault root by checking (in order):
1. The current working directory (if it contains `CLAUDE.md` and `brain-scan-templates.md`)
2. The `OBSIDIAN_VAULT` environment variable
3. Ask the user

Read `brain-scan-templates.md` from the vault root for canonical template definitions before processing any files.

## Step-by-Step Process

### Phase 1: Discovery

**Scan `inbox/`** — collect ALL files recursively (any type).

**Scan vault root (non-recursive)** — collect `.md` files and directories at the root level that are NOT structural.

**Structural files/dirs to SKIP (these belong at root):**
- `CLAUDE.md`, `IDENTITY.md`, `MASTER_INDEX.md`, `brain-scan-templates.md`, `README.md`, `LICENSE`
- `archive/`, `creative/`, `daily_notes/`, `docs/`, `frameworks/`, `intake/`, `people/`, `portfolio/`, `projects/`, `prompts/`, `inbox/`, `templates/`
- `.claude/`, `.obsidian/`, `.git/`, `node_modules/`

**Everything else at root is a candidate** — loose `.md` files, unexpected directories, non-markdown files.

For directories at root that aren't structural, scan inside them to understand what they contain before categorizing.

### Phase 2: Analysis

For each candidate file/directory, read the contents and determine:

1. **Content type** — what kind of content is this?
2. **Destination** — where should it live in the brain?
3. **Template** — which brain-scan-template applies?
4. **Formatting needed** — does it already have proper frontmatter? Does it need restructuring?

Use this routing table:

| Content Type | Destination | Template |
|---|---|---|
| Project documentation / README / CLAUDE.md | `projects/[category]/[slug].md` | Project Summary |
| Comedy script | `creative/comedy/scripts/[slug].md` | Comedy Script |
| Comedy show notes | `creative/comedy/shows/[slug].md` | Comedy Show |
| Writing / prose / essay / story | `creative/writing/[slug].md` | Creative Work |
| Music lyrics / ideas | `creative/music-ideas/[slug].md` | Creative Work |
| Video concept | `creative/video-concepts/[slug].md` | Creative Work |
| Person / bio / contact | `people/[slug].md` | *(see People format below)* |
| Prompt / AI pattern | `prompts/[domain]/[slug].md` | Prompt Pattern |
| Business document | `projects/business/[slug].md` or `portfolio/` | Project Summary |
| Framework / methodology | `frameworks/[slug].md` | *(preserve structure, add frontmatter)* |
| Journal / reflection | `daily_notes/[slug].md` | Daily Note |
| Reference / guide / tutorial | `docs/[slug].md` | *(preserve structure, add frontmatter)* |
| Unknown | `inbox/unsorted/[slug].md` | *(add minimal frontmatter, flag for user)* |

**People file format** (for person/bio content):
```markdown
---
title: [Person Name]
type: person
relation: [friend | collaborator | client | colleague | family | public-figure]
tags: [people, context-tag]
related: ["[[Related Project or Group]]"]
---

# [Person Name]

## Who They Are
[Brief description of this person and their connection to the vault owner]

## Notes
[Any additional context, history, or details]
```

### Phase 3: Present Findings

Show the user what was found and what you plan to do:

```markdown
## Inbox Processing Results

### Files Found

#### From `inbox/` (N files)
| # | File | Detected Type | Destination | Action |
|---|------|--------------|-------------|--------|
| 1 | `filename.md` | [type] | `path/to/destination.md` | [Create new / Merge with existing] |

#### From vault root (N files)
| # | File | Detected Type | Destination | Action |
|---|------|--------------|-------------|--------|
| 1 | `filename.md` | [type] | `path/to/destination.md` | [Move & format / Create new] |

### Directories at root that don't belong (N)
| # | Directory | Contents | Recommendation |
|---|-----------|----------|----------------|
| 1 | `DirName/` | [N files, description] | [Route to projects/X / Route to creative/X / Ask user] |

**Process all? (y/n/select numbers)**
```

In `--auto` mode, skip the prompt and process everything.
In `--dry-run` mode, show the table and stop.

### Phase 4: Processing

For each approved file:

**4a. Read the original content fully.**

**4b. Rename to kebab-case** if the filename has spaces or incorrect casing.

**4c. Add/fix frontmatter** based on the appropriate template:
- If the file already has frontmatter, preserve existing fields and add missing required ones
- If no frontmatter, create it from scratch based on content analysis
- Always include: `title`, `type`, `tags`, `related`
- Add type-specific fields per brain-scan-templates.md

**4d. Restructure body if needed:**
- Add required H2 sections for the content type (per templates)
- Preserve ALL original content — never delete the user's writing
- If content doesn't fit neatly into template sections, put it under the most appropriate heading or a `## Original Content` section

**4e. Add wiki links:**
- `[[wiki link]]` every person name mentioned
- `[[wiki link]]` every project referenced
- `[[wiki link]]` every group/organization mentioned
- Check existing brain files to know what entities already exist

**4f. Write the file to its destination** using Write tool.

**4g. Delete the original** from inbox/ or vault root (only after successful write to destination).

**4h. Update relevant index:**
- Projects → add row to `projects/_INDEX.md`
- Creative works → add to `creative/_INDEX.md` (create if it doesn't exist)
- People → add to `people/_INDEX.md` (create if it doesn't exist)
- Prompts → add to `prompts/_INDEX.md`

### Phase 5: Handle Directories

For directories found at root that aren't structural:

1. Read their contents to understand what they are
2. If it's a project → run the equivalent of `/brain-scan` logic on it (create project summary, archive, index entry)
3. If it's a collection of files → process each file individually per Phase 4
4. If unclear → move the whole directory to `inbox/unsorted/` and flag for user

### Phase 6: Report

```markdown
## Inbox Processing Complete

**Processed:** N files
**Moved to:**
- `projects/` — N files
- `creative/` — N files
- `people/` — N files
- `docs/` — N files
- [other destinations]

**Indexes updated:** [list]
**Unsorted (needs manual review):** N files in `inbox/unsorted/`

### Changes Made
| Original | → | Destination | Type |
|----------|---|-------------|------|
| `inbox/raw-file.md` | → | `creative/writing/raw-file.md` | writing |
| `Root-File.md` | → | `people/root-file.md` | person |
```

## Edge Cases

### Files with no clear category
- Add minimal frontmatter (`title`, `type: unclassified`, `tags: [needs-review]`)
- Move to `inbox/unsorted/`
- Flag in the report

### Files that match existing brain entries
- If a file appears to be about a project/person/topic that already has a brain entry, **do not overwrite**
- Instead, show a diff summary and ask: "Merge into existing entry, or keep as separate file?"
- In `--auto` mode, append new content under a `## Additional Notes (from inbox)` section in the existing file

### Non-markdown files
- `.txt` — convert to `.md`, add frontmatter, process normally
- `.pdf` — read with Read tool (if small), extract key info, create a `.md` summary that links to the original
- `.doc/.docx` — note in report as "needs manual conversion" unless pandoc available
- `.odt` — convert via pandoc: `pandoc "file.odt" -t markdown`
- Images/audio/video — move to `inbox/media/` with a companion `.md` file noting what it is
- `.json` — inspect structure, create `.md` summary if it's meaningful data

### Empty files
- Delete from inbox (with confirmation in interactive mode)
- Report as "Removed N empty files"

### Duplicate filenames
- If destination already has a file with the same name, suffix with `-2`, `-3`, etc.
- Report the rename in the output

## Important Notes

- **ALWAYS read `brain-scan-templates.md` first** — templates may have been updated
- **NEVER delete user content** — worst case, move to `inbox/unsorted/`
- **Preserve original content** — restructure and add structure, but never lose the user's words
- **Ask before merging** — if content overlaps with an existing entry, confirm (except in `--auto`)
- **Wiki-link everything** — use Grep to find existing entities in the brain before linking
- **Kebab-case all filenames** — `My File Name.md` → `my-file-name.md`

---

**Usage:** `/brain-inbox`

Examples:
- `/brain-inbox` — interactive processing of inbox/ and vault root
- `/brain-inbox --dry-run` — see what would happen without changes
- `/brain-inbox --auto` — process everything without prompts
