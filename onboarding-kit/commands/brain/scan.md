---
name: brain:scan
description: Scan system for CLAUDE.md/MEMORY.md files and update the project brain
argument-hint: "[drives...] [--target path]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion
---

<objective>
Scan the filesystem for all CLAUDE.md and MEMORY.md files, compare against the existing project brain, ingest new/updated projects, and rebuild the master index and portfolio files.

**Usage:**
```
/brain:scan                            # Auto-detect drives, update M:\
/brain:scan C:\ D:\                    # Scan specific drives only
/brain:scan --target /path/to/brain    # Use a different brain location
/brain:scan C:\ --target /x/brain     # Both: specific drives + custom target
```
</objective>

<context>
The project brain is a centralized knowledge hub that contains:
- `MASTER_INDEX.md` — Single table of all projects with status, location, tech
- `projects/[category]/[project].md` — Condensed summaries per project
- `archive/raw-claude-mds/[category]/` — Verbatim copies of source CLAUDE.md files
- `portfolio/` — tech-skills.md, project-portfolio.md, services.md
- `CLAUDE.md` — Root context file with navigation and category counts
- `brain-scan-templates.md` — Canonical formatting templates for all generated content

Categories: music, comics, writing, video, hardware, dev-tools, apps
</context>

<process>

## Step 0 — Parse Arguments

Parse `$ARGUMENTS` for:
1. **Drive paths** — any arguments that look like drive letters (`C:\`, `D:\`, `/mnt/data`, etc.)
2. **`--target` flag** — if present, the next argument is the brain location (default: `M:\`)

Set variables:
- `BRAIN_TARGET` = value of --target, or `M:\` if not specified
- `SCAN_DRIVES` = list of drives from arguments, or auto-detect if none specified

Verify the brain target exists by checking for `MASTER_INDEX.md` at the target path. If it doesn't exist, ask the user if they want to initialize a new brain at that location.

## Step 1 — Discovery

### 1a. Determine drives to scan

If no drives were specified in arguments, auto-detect:

**Windows:**
```bash
wmic logicaldisk get DeviceID,VolumeName,DriveType 2>/dev/null || powershell -Command "Get-PSDrive -PSProvider FileSystem | Select-Object Root"
```

**Linux/Mac:**
```bash
df -h --output=target | grep -E '^/' | head -20
```

Exclude the brain target drive itself from scanning (don't scan M:\ for projects if M:\ is the brain).

Report the drives found and confirm with the user before proceeding.

### 1b. Scan for CLAUDE.md and MEMORY.md files

For each drive, use the Glob tool to find files:
- Pattern: `[drive]/**/CLAUDE.md` (max practical depth ~8 levels)
- Pattern: `[drive]/**/MEMORY.md`

Use the Task tool with Explore agents to scan multiple drives in parallel when there are 2+ drives.

**Important exclusions** — skip these paths:
- `node_modules/`
- `.git/`
- `AppData/`
- `ProgramData/`
- `Windows/`
- `Program Files/`
- `Program Files (x86)/`
- `$Recycle.Bin/`
- The brain target directory itself (e.g., `M:\`)
- `.claude/` directories (these are Claude Code's own memory, not project sources)

### 1c. Deduplicate results

Apply these deduplication rules (also documented in `brain-scan-templates.md`):
1. **Claude Code memory mirrors** — Files at `.claude/projects/.../memory/MEMORY.md` are NOT separate projects. Note them as references for the parent project.
2. **Template copies** — If a CLAUDE.md is inside a directory that's clearly a copy/instance of a template (e.g., contains `suno-album-template` in path), group it with the template.
3. **Same project, multiple versions** — Directories like `v2/`, `v3/`, `v3.02/` under the same parent are ONE project with multiple CLAUDE.md archives.
4. **Sub-projects** — Multiple CLAUDE.md files under the same parent (e.g., LATV sub-genres) consolidate into one project.

Output a deduplicated list of unique projects, each with:
- Project name (inferred from directory name)
- All associated CLAUDE.md paths
- All associated MEMORY.md paths
- Inferred category (guess based on path/content, will confirm later)

## Step 2 — Diff Against Existing Brain

### 2a. Load existing brain state

Read `{BRAIN_TARGET}/MASTER_INDEX.md` to get the list of known projects and their locations.

### 2b. Categorize each discovered project

For each discovered project, classify it as:
- **Known/Unchanged** — location matches an existing project in MASTER_INDEX, and the source CLAUDE.md file modification time is not newer than the archive copy
- **Known/Updated** — location matches but the source file is newer
- **New** — location doesn't match any existing project

To check file modification times:
```bash
stat -c %Y "[source_file]" 2>/dev/null || stat -f %m "[source_file]"
```

### 2c. Report diff to user

Print a clear summary:
```
## Brain Scan Results

### New Projects Found: [N]
- [project name] at [path] (guessed category: [category])
- ...

### Updated Projects: [N]
- [project name] — source file newer than archive

### Unchanged: [N]
- [list or just count]

### Skipped: [N]
- [path] — reason (duplicate, template copy, Claude Code memory, etc.)
```

Ask the user to confirm before proceeding with ingestion. If there's nothing new or updated, report that and stop.

## Step 3 — Ingest New/Updated Projects

### 3a. Process new projects

For each new project:

1. **Read the source CLAUDE.md** (and MEMORY.md if it exists) using the Read tool
2. **Ask the user to confirm the category** — present the auto-detected category and let them choose:
   - music, comics, writing, video, hardware, dev-tools, apps
   - Or suggest a new category
3. **Generate a project summary** following the template in `{BRAIN_TARGET}/brain-scan-templates.md`
   - Read the templates file first to ensure exact format compliance
   - Infer tech stack, accomplishments, current state, and lessons from the CLAUDE.md content
   - If MEMORY.md exists, incorporate insights from it
4. **Write the summary** to `{BRAIN_TARGET}/projects/[category]/[project-slug].md`
5. **Copy the raw CLAUDE.md** to `{BRAIN_TARGET}/archive/raw-claude-mds/[category]/[project-slug]-CLAUDE.md`
   - Read the source file and Write it to the archive location
   - If there are multiple CLAUDE.md files (versions, sub-projects), archive each with appropriate suffixes

### 3b. Process updated projects

For each updated project:

1. **Read the new source CLAUDE.md**
2. **Read the existing project summary** at its current location
3. **Update the summary** — regenerate it with the new content, preserving the same format
4. **Update the archive** — overwrite the archived CLAUDE.md with the new version

### 3c. Create category directories if needed

```bash
mkdir -p "{BRAIN_TARGET}/projects/[category]"
mkdir -p "{BRAIN_TARGET}/archive/raw-claude-mds/[category]"
```

## Step 4 — Rebuild Index and Portfolio

After all ingestion is complete, rebuild the brain's aggregate files.

### 4a. Regenerate MASTER_INDEX.md

1. Read ALL project summary files from `{BRAIN_TARGET}/projects/*/`
2. Extract: project name, category, status, location, one-line summary, tech
3. Build the full table following the format in `brain-scan-templates.md`
4. Calculate the footer stats (total, per-category counts, status breakdown)
5. Write to `{BRAIN_TARGET}/MASTER_INDEX.md`

### 4b. Regenerate portfolio/tech-skills.md

1. Scan all project summaries for Tech Stack sections
2. Aggregate all technologies, grouping by domain
3. Deduplicate — same tech used in multiple projects gets combined description
4. Build the Domain Expertise Summary table
5. Write to `{BRAIN_TARGET}/portfolio/tech-skills.md`

### 4c. Regenerate portfolio/project-portfolio.md

1. Read all project summaries
2. For each project, create a portfolio entry: what was built, what it proves, key technical decisions
3. Build the Portfolio Summary table
4. Write to `{BRAIN_TARGET}/portfolio/project-portfolio.md`

### 4d. Regenerate portfolio/services.md

1. Read existing services.md to preserve the service structure
2. For each service category, scan project summaries for matching evidence
3. Update evidence lists with any new projects
4. Add new service categories if new projects reveal uncovered capabilities
5. Write to `{BRAIN_TARGET}/portfolio/services.md`

### 4e. Update root CLAUDE.md

1. Read the existing `{BRAIN_TARGET}/CLAUDE.md`
2. Update the category counts table with current numbers
3. Update the total project count
4. Write back to `{BRAIN_TARGET}/CLAUDE.md`

## Step 5 — Report

Print a final summary:

```
## Brain Scan Complete

### Added: [N] new projects
- [project name] → projects/[category]/[slug].md

### Updated: [N] projects
- [project name] — summary and archive refreshed

### Unchanged: [N] projects

### Skipped: [N] files
- [path] — [reason]

### Brain Stats
- Total projects: [N] (was [old N])
- Categories: [list with counts]
- Files regenerated: MASTER_INDEX.md, tech-skills.md, project-portfolio.md, services.md, CLAUDE.md
```

</process>

<important-notes>
- ALWAYS read `{BRAIN_TARGET}/brain-scan-templates.md` before generating any content to ensure format compliance
- NEVER overwrite a project summary without reading the existing one first
- When generating summaries, be thorough but concise — match the style and depth of existing summaries in the brain
- If a CLAUDE.md is very large (1000+ lines), focus on the most important sections for the summary
- The portfolio files should reflect ALL projects, not just new ones — regenerate from scratch each time
- If scanning takes too long on a drive, warn the user and offer to skip it
- Archive copies are verbatim — never modify the content of raw CLAUDE.md archives
- Use parallel Task agents when scanning multiple drives to speed up discovery
</important-notes>
