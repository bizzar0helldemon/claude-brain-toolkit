---
name: brain-discover
description: Scan drives for existing creative content not yet in the brain. Finds documents, scripts, writing, and other files that should be cataloged.
argument-hint: <path-to-scan>
---

# Brain Discover — Drive Content Scanner

You are scanning a path for existing creative content that hasn't been captured in the Claude Brain yet.

## Your Task

The user provides a path to scan (as $ARGUMENTS). You must find content files, present them grouped by type, and help the user decide what to ingest.

## Step-by-Step Process

### Step 1: Scan the Path

Search the provided path recursively for content files:

**File types to look for:**
- `.md`, `.txt` — writing, notes, scripts
- `.doc`, `.docx` — documents (note: can't read contents, but can catalog)
- `.pdf` — documents, scripts
- `.py`, `.js`, `.html` — code that might be creative projects
- `.json` — structured data (comic scripts, game data, etc.)
- `.lrc`, `.srt` — lyrics, subtitles

**Ignore:**
- `node_modules/`, `.git/`, `__pycache__/`, `.obsidian/`
- Binary files (images, audio, video) — note their existence but don't try to read
- System files, configs, lockfiles

### Step 2: Categorize Findings

Group discovered files by apparent content type:

| Category | Indicators |
|----------|-----------|
| Scripts/Dialogue | Dialogue format, character names, stage directions |
| Writing | Prose, stories, essays, blog posts |
| Music/Lyrics | Song structure, verse/chorus, musical references |
| Project docs | READMEs, specs, design docs |
| Personal | Journal entries, notes, reflections |
| Unknown | Can't determine — ask user |

### Step 3: Present to User

Show findings in a clear, grouped format:

```
## Discovery Results: [path]

### Scripts / Dialogue (N files)
- `path/to/file.md` — [brief description of contents]
- `path/to/file.txt` — [brief description]

### Writing (N files)
- ...

### Already in Brain (N files)
- [files that match existing project entries]

### Skipped (N files/dirs)
- [binary files, system files, etc.]

**What would you like to ingest?** (Enter numbers, "all", or "none")
```

### Step 4: Ingest Selected Content

For each selected file:

1. **Determine destination:**
   - Scripts/dialogue → `creative/scripts/[slug].md`
   - Writing → `creative/writing/[slug].md`
   - Music ideas → `creative/music-ideas/[slug].md`
   - Video concepts → `creative/video-concepts/[slug].md`
   - Project-related → update existing `projects/` entry or create new via `/brain-scan`

2. **Create proper entry** with:
   - Frontmatter (title, date, type, tags, related)
   - `[[wiki links]]` to people, projects, groups mentioned
   - Content from the source file (reformatted to template if needed)

3. **Update indices:**
   - Add to `creative/_INDEX.md` if creative content
   - Add to `projects/_INDEX.md` if a new project
   - Update `IDENTITY.md` if personal information discovered

### Step 5: Log the Discovery

Save a discovery log to:
```
intake/discoveries/YYYY-MM-DD-[path-slug].md
```

```markdown
---
title: "Discovery: [Path Scanned]"
date: YYYY-MM-DD
path: "[full path]"
type: discovery-log
tags: [intake, discovery]
files-found: N
files-ingested: N
---

# Discovery: [Path]

## Summary
- **Scanned:** [path]
- **Files found:** N
- **Files ingested:** N
- **Files skipped:** N

## Ingested
- `source-path` → `brain-path` — [description]

## Skipped
- `source-path` — [reason: already in brain / binary / user declined]
```

### Step 6: Report

```
## Discovery Complete

**Path scanned:** [path]
**Files found:** N
**Files ingested:** N into [list of brain locations]
**Discovery log:** intake/discoveries/YYYY-MM-DD-path.md
```

## Important Notes

- **Don't move or delete source files** — only copy/create brain entries
- **Ask before ingesting** — always let the user choose what comes in
- **Add [[wiki links]]** to everything — people, projects, groups
- **Check for duplicates** — compare against existing `projects/` entries before creating new ones
- **Large directories** — if >100 files found, show counts by category and ask user to narrow scope

---

**Usage:** `/brain-discover [path]`

Examples:
- `/brain-discover ~/Documents/Writing` — scan for writing
- `/brain-discover ~/Desktop` — scan desktop for uncataloged content
- `/brain-discover /mnt/archive` — scan an archive drive (may be large)
