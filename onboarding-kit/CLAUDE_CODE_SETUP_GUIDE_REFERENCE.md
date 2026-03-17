# Claude Code Portable Setup Guide

> **Purpose:** Reproduce this exact Claude Code environment on any new machine.
> **Last updated:** 2026-02-28
> **Location:** `M:\` (portable drive — plug in and go)

---

## Table of Contents

1. [Prerequisites — Core Software](#1-prerequisites--core-software)
2. [Authentication](#2-authentication)
3. [Global Settings](#3-global-settings)
4. [Hooks](#4-hooks)
5. [GSD (Get Shit Done) System](#5-gsd-get-shit-done-system)
6. [Global Slash Commands (non-GSD)](#6-global-slash-commands-non-gsd)
7. [Global Skills](#7-global-skills)
8. [Plugins](#8-plugins)
9. [Project Brain (M:\ Drive)](#9-project-brain-m-drive)
10. [Project Memory Structure](#10-project-memory-structure)
11. [Quick Setup Checklist](#11-quick-setup-checklist)

---

## 1. Prerequisites — Core Software

Install these first. Versions listed are the reference versions from the current setup.

| Tool | Version | Install Method |
|------|---------|---------------|
| Node.js | v22.19.0 (LTS) | [nodejs.org](https://nodejs.org/) |
| npm | 11.6.0 (bundled with Node) | — |
| Git | 2.53.0 | [git-scm.com](https://git-scm.com/) |
| Python | 3.13.7 | [python.org](https://python.org/) |
| Claude Code CLI | latest | `npm install -g @anthropic-ai/claude-code` |

### PATH Dependencies (install as needed)

These tools are expected to be available on PATH for various projects:

- **Docker** — container workflows
- **GitHub CLI (`gh`)** — PR/issue management from Claude Code
- **Cargo/Rust** — Rust-based tooling
- **Ollama** — local LLM inference
- **FFmpeg** — audio/video processing
- **Chocolatey** — Windows package manager

---

## 2. Authentication

Claude Code uses OAuth — no API keys to manage.

```bash
# First run triggers the login flow
claude
```

- Follow the browser-based OAuth login
- Subscription: **Claude Max** (5x rate limit)
- Auth is per-machine — each new machine needs its own login
- No keys, tokens, or config files to copy

---

## 3. Global Settings

**File:** `~/.claude/settings.json`

Create this file on the new machine (replace `USERNAME` with the actual Windows username):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"C:/Users/USERNAME/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "node \"C:/Users/USERNAME/.claude/hooks/gsd-statusline.js\""
  },
  "enabledPlugins": {
    "example-skills@anthropic-agent-skills": false,
    "superpowers@superpowers-marketplace": true
  },
  "skipDangerousModePermissionPrompt": true
}
```

> **Note:** The hook paths must use the actual home directory. On Windows, replace `USERNAME` with your Windows username. The GSD installer sets these paths automatically, so if you install GSD first (Step 5), the hooks will already be configured.

---

## 4. Hooks

**Directory:** `~/.claude/hooks/`

Two hook scripts power the session-start update check and the status line. Both are installed automatically by GSD (`npm install -g get-shit-done-cc`), but are documented here for reference and manual setup.

### 4a. `gsd-check-update.js` — SessionStart Hook

Runs once per session. Checks npm for GSD updates in the background and caches the result.

```javascript
#!/usr/bin/env node
// Check for GSD updates in background, write result to cache
// Called by SessionStart hook - runs once per session

const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawn } = require('child_process');

const homeDir = os.homedir();
const cwd = process.cwd();
const cacheDir = path.join(homeDir, '.claude', 'cache');
const cacheFile = path.join(cacheDir, 'gsd-update-check.json');

// VERSION file locations (check project first, then global)
const projectVersionFile = path.join(cwd, '.claude', 'get-shit-done', 'VERSION');
const globalVersionFile = path.join(homeDir, '.claude', 'get-shit-done', 'VERSION');

// Ensure cache directory exists
if (!fs.existsSync(cacheDir)) {
  fs.mkdirSync(cacheDir, { recursive: true });
}

// Run check in background (spawn background process, windowsHide prevents console flash)
const child = spawn(process.execPath, ['-e', `
  const fs = require('fs');
  const { execSync } = require('child_process');

  const cacheFile = ${JSON.stringify(cacheFile)};
  const projectVersionFile = ${JSON.stringify(projectVersionFile)};
  const globalVersionFile = ${JSON.stringify(globalVersionFile)};

  // Check project directory first (local install), then global
  let installed = '0.0.0';
  try {
    if (fs.existsSync(projectVersionFile)) {
      installed = fs.readFileSync(projectVersionFile, 'utf8').trim();
    } else if (fs.existsSync(globalVersionFile)) {
      installed = fs.readFileSync(globalVersionFile, 'utf8').trim();
    }
  } catch (e) {}

  let latest = null;
  try {
    latest = execSync('npm view get-shit-done-cc version', { encoding: 'utf8', timeout: 10000, windowsHide: true }).trim();
  } catch (e) {}

  const result = {
    update_available: latest && installed !== latest,
    installed,
    latest: latest || 'unknown',
    checked: Math.floor(Date.now() / 1000)
  };

  fs.writeFileSync(cacheFile, JSON.stringify(result));
`], {
  stdio: 'ignore',
  windowsHide: true
});

child.unref();
```

### 4b. `gsd-statusline.js` — Status Line

Displays model name, active task, directory, context usage bar, and GSD update indicator.

```javascript
#!/usr/bin/env node
// Claude Code Statusline - GSD Edition
// Shows: model | current task | directory | context usage

const fs = require('fs');
const path = require('path');
const os = require('os');

// Read JSON from stdin
let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const model = data.model?.display_name || 'Claude';
    const dir = data.workspace?.current_dir || process.cwd();
    const session = data.session_id || '';
    const remaining = data.context_window?.remaining_percentage;

    // Context window display (shows USED percentage scaled to 80% limit)
    // Claude Code enforces an 80% context limit, so we scale to show 100% at that point
    let ctx = '';
    if (remaining != null) {
      const rem = Math.round(remaining);
      const rawUsed = Math.max(0, Math.min(100, 100 - rem));
      // Scale: 80% real usage = 100% displayed
      const used = Math.min(100, Math.round((rawUsed / 80) * 100));

      // Build progress bar (10 segments)
      const filled = Math.floor(used / 10);
      const bar = '█'.repeat(filled) + '░'.repeat(10 - filled);

      // Color based on scaled usage (thresholds adjusted for new scale)
      if (used < 63) {        // ~50% real
        ctx = ` \x1b[32m${bar} ${used}%\x1b[0m`;
      } else if (used < 81) { // ~65% real
        ctx = ` \x1b[33m${bar} ${used}%\x1b[0m`;
      } else if (used < 95) { // ~76% real
        ctx = ` \x1b[38;5;208m${bar} ${used}%\x1b[0m`;
      } else {
        ctx = ` \x1b[5;31m💀 ${bar} ${used}%\x1b[0m`;
      }
    }

    // Current task from todos
    let task = '';
    const homeDir = os.homedir();
    const todosDir = path.join(homeDir, '.claude', 'todos');
    if (session && fs.existsSync(todosDir)) {
      try {
        const files = fs.readdirSync(todosDir)
          .filter(f => f.startsWith(session) && f.includes('-agent-') && f.endsWith('.json'))
          .map(f => ({ name: f, mtime: fs.statSync(path.join(todosDir, f)).mtime }))
          .sort((a, b) => b.mtime - a.mtime);

        if (files.length > 0) {
          try {
            const todos = JSON.parse(fs.readFileSync(path.join(todosDir, files[0].name), 'utf8'));
            const inProgress = todos.find(t => t.status === 'in_progress');
            if (inProgress) task = inProgress.activeForm || '';
          } catch (e) {}
        }
      } catch (e) {
        // Silently fail on file system errors - don't break statusline
      }
    }

    // GSD update available?
    let gsdUpdate = '';
    const cacheFile = path.join(homeDir, '.claude', 'cache', 'gsd-update-check.json');
    if (fs.existsSync(cacheFile)) {
      try {
        const cache = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
        if (cache.update_available) {
          gsdUpdate = '\x1b[33m⬆ /gsd:update\x1b[0m │ ';
        }
      } catch (e) {}
    }

    // Output
    const dirname = path.basename(dir);
    if (task) {
      process.stdout.write(`${gsdUpdate}\x1b[2m${model}\x1b[0m │ \x1b[1m${task}\x1b[0m │ \x1b[2m${dirname}\x1b[0m${ctx}`);
    } else {
      process.stdout.write(`${gsdUpdate}\x1b[2m${model}\x1b[0m │ \x1b[2m${dirname}\x1b[0m${ctx}`);
    }
  } catch (e) {
    // Silent fail - don't break statusline on parse errors
  }
});
```

---

## 5. GSD (Get Shit Done) System

**Install:**

```bash
npm install -g get-shit-done-cc
```

**Current version:** 1.12.0

This single command installs everything:

| What | Location |
|------|----------|
| 28 slash commands | `~/.claude/commands/gsd/` |
| 11 agent definitions | `~/.claude/agents/` |
| Hook scripts | `~/.claude/hooks/` |
| Reference docs, templates, workflows | `~/.claude/get-shit-done/` |

No manual file copying needed — the npm package handles all of it, including setting up the hooks in `settings.json`.

**Key slash commands:** `/gsd:new-project`, `/gsd:plan-phase`, `/gsd:execute-phase`, `/gsd:progress`, `/gsd:debug`, `/gsd:quick`, `/gsd:update`

Run `/gsd:help` inside Claude Code for a full command reference.

---

## 6. Global Slash Commands (non-GSD)

**Directory:** `~/.claude/commands/brain/`

This command is NOT part of GSD — it must be manually created.

### `scan.md` — the `/brain:scan` command

Create the file at `~/.claude/commands/brain/scan.md`:

````markdown
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
````

---

## 7. Global Skills

**Directory:** `~/.claude/skills/`

Three custom skills. Each lives in its own subdirectory with a `SKILL.md` file.

### 7a. `changelog-generator/SKILL.md`

```markdown
---
name: changelog-generator
description: Transforms technical git commits into polished, user-friendly changelogs that customers and users will understand and appreciate
---

# Changelog Generator Skill

## When to Use This Skill

- Preparing release notes for a new version
- Creating weekly or monthly product update summaries
- Documenting changes for customers
- Writing changelog entries for app store submissions
- Generating update notifications
- Creating internal release documentation
- Maintaining a public changelog/product updates page

## What This Skill Does

1. **Scans Git History**: Analyzes commits from a specific time period or between versions
2. **Categorizes Changes**: Groups commits into logical categories (features, improvements, bug fixes, breaking changes, security)
3. **Translates Technical → User-Friendly**: Converts developer commits into customer language
4. **Formats Professionally**: Creates clean, structured changelog entries
5. **Filters Noise**: Excludes internal commits (refactoring, tests, etc.)
6. **Follows Best Practices**: Applies changelog guidelines and brand voice

## How to Use

**Basic Usage:**
- "Create a changelog from commits since last release"
- "Generate changelog for all commits from the past week"
- "Create release notes for version 2.5.0"

**With Specific Date Range:**
- "Create a changelog for all commits between March 1 and March 15"

**With Custom Guidelines:**
- "Create a changelog for commits since v2.4.0, using my changelog guidelines from CHANGELOG_STYLE.md"

## Tips

- Run from your git repository root
- Specify date ranges for focused changelogs
- Use your CHANGELOG_STYLE.md for consistent formatting
- Review and adjust the generated changelog before publishing
- Save output directly to CHANGELOG.md

## Related Use Cases

- Creating GitHub release notes
- Writing app store update descriptions
- Generating email updates for users
- Creating social media announcement posts
```

### 7b. `systematic-debugging/SKILL.md`

```markdown
---
name: systematic-debugging
description: Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes - four-phase framework (root cause investigation, pattern analysis, hypothesis testing, implementation) that ensures understanding before attempting solutions
---

# Systematic Debugging

## The Iron Law

**NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST**

Random fixes waste time and create new bugs. Systematic investigation is always faster than guess-and-check, even when you're "sure" what the problem is.

**ALWAYS find root cause before attempting fixes. Symptom fixes are failure.**

## When to Use This Skill

Use this skill when encountering:
- Any bug, test failure, or unexpected behavior
- Before proposing any fix or solution
- When tempted to "just try something"
- When you think you know what's wrong but haven't verified

## The Four Phases

### Phase 1: Root Cause Investigation

**NO PROPOSED SOLUTIONS UNTIL PHASE 1 IS COMPLETE**

1. **Read error messages completely** - Don't skim. Every word matters.
2. **Reproduce the issue consistently** - If you can't reproduce it, you can't fix it.
3. **Check recent changes** - Use git history to see what changed.
4. **Gather diagnostic evidence** - Add logging/instrumentation at component boundaries.
5. **Trace data flow** - Use root-cause-tracing skill when errors occur deep in execution.

**Output:** Clear statement of root cause, not symptoms.

### Phase 2: Pattern Analysis

1. **Find similar working code** - Locate equivalent functionality that works.
2. **Compare against reference implementations** - Read documentation and examples completely.
3. **Identify ALL differences** - Between working and broken versions.
4. **Understand dependencies** - What assumptions does this code make?

**Output:** Understanding of what "correct" looks like and why current code differs.

### Phase 3: Hypothesis and Testing

1. **Form a specific, written hypothesis** - "I believe X is wrong because Y, and changing Z will fix it."
2. **Test with minimal changes** - Change ONE variable at a time.
3. **Verify results before proceeding** - Did the test confirm or disprove your hypothesis?
4. **Admit knowledge gaps** - Don't pretend to understand what you don't.

**Output:** Verified understanding of the problem mechanism.

### Phase 4: Implementation

1. **Create a failing test case first** - Proves you can detect the bug.
2. **Implement a single fix** - Address the root cause, not symptoms.
3. **Verify the fix works** - Run the test and related tests.
4. **If 3+ fixes fail** - Question the architecture, don't keep trying patches.

**Output:** Working code with test coverage.

## Red Flags (Stop and Return to Phase 1)

If you hear yourself thinking any of these, STOP and return to Phase 1:

- "Let's just try this quick fix for now, we can investigate later"
- "I don't fully understand, but this might work"
- "Just try changing X and see what happens"
- Proposing multiple fixes at once
- Each fix reveals new problems elsewhere

## Common Rationalizations (And Why They're Wrong)

| Excuse | Reality |
|--------|---------|
| "This issue is simple" | All bugs have root causes. Simple bugs have simple root causes. |
| "We're in an emergency, no time for investigation" | Random fixes in emergencies create more emergencies. Systematic is faster. |
| "Trying multiple fixes saves time" | You can't isolate what worked. You learn nothing. |
| "Just one more fix attempt" | After 3 failures, the architecture is wrong. More attempts won't help. |

## Integration with Other Skills

**Required with this skill:**
- `root-cause-tracing` - When errors occur deep in call stack
- `test-driven-development` - For creating failing tests (Phase 4)

**Complements well with:**
- `defense-in-depth` - Prevent bugs from reaching deep execution
- `condition-based-waiting` - Eliminate timing-related bugs
- `verification-before-completion` - Ensure fixes actually work

## Success Metrics

**With systematic debugging:**
- 15-30 minutes to find and fix root cause
- 95% first-time fix success rate
- Zero new bugs introduced

**With random approach:**
- 2-3 hours of trial and error
- 40% success rate
- New bugs introduced by "fixes"

## Remember

Understanding before action. Always.
```

### 7c. `simplification-cascades/SKILL.md`

```markdown
---
name: simplification-cascades
description: Find one insight that eliminates multiple components - "if this is true, we don't need X, Y, or Z"
when_to_use: when implementing the same concept multiple ways, accumulating special cases, or complexity is spiraling
version: 1.1.0
---

# Simplification Cascades

## Overview

Sometimes one insight eliminates 10 things. Look for the unifying principle that makes multiple components unnecessary.

**Core principle:** "Everything is a special case of..." collapses complexity dramatically.

## Quick Reference

| Symptom | Likely Cascade |
|---------|----------------|
| Same thing implemented 5+ ways | Abstract the common pattern |
| Growing special case list | Find the general case |
| Complex rules with exceptions | Find the rule that has no exceptions |
| Excessive config options | Find defaults that work for 95% |

## The Pattern

**Look for:**
- Multiple implementations of similar concepts
- Special case handling everywhere
- "We need to handle A, B, C, D differently..."
- Complex rules with many exceptions

**Ask:** "What if they're all the same thing underneath?"

## Examples

### Cascade 1: Stream Abstraction
**Before:** Separate handlers for batch/real-time/file/network data
**Insight:** "All inputs are streams - just different sources"
**After:** One stream processor, multiple stream sources
**Eliminated:** 4 separate implementations

### Cascade 2: Resource Governance
**Before:** Session tracking, rate limiting, file validation, connection pooling (all separate)
**Insight:** "All are per-entity resource limits"
**After:** One ResourceGovernor with 4 resource types
**Eliminated:** 4 custom enforcement systems

### Cascade 3: Immutability
**Before:** Defensive copying, locking, cache invalidation, temporal coupling
**Insight:** "Treat everything as immutable data + transformations"
**After:** Functional programming patterns
**Eliminated:** Entire classes of synchronization problems

## Process

1. **List the variations** - What's implemented multiple ways?
2. **Find the essence** - What's the same underneath?
3. **Extract abstraction** - What's the domain-independent pattern?
4. **Test it** - Do all cases fit cleanly?
5. **Measure cascade** - How many things become unnecessary?

## Red Flags You're Missing a Cascade

- "We just need to add one more case..." (repeating forever)
- "These are all similar but different" (maybe they're the same?)
- Refactoring feels like whack-a-mole (fix one, break another)
- Growing configuration file
- "Don't touch that, it's complicated" (complexity hiding pattern)

## Remember

- Simplification cascades = 10x wins, not 10% improvements
- One powerful abstraction > ten clever hacks
- The pattern is usually already there, just needs recognition
- Measure in "how many things can we delete?"
```

---

## 8. Plugins

### Enabled

| Plugin | Version | Description |
|--------|---------|-------------|
| `superpowers@superpowers-marketplace` | 3.2.3 | Community skills marketplace |

### Disabled

| Plugin | Description |
|--------|-------------|
| `example-skills@anthropic-agent-skills` | Anthropic's example skills (disabled in settings) |

### Install Command

```bash
claude plugins install superpowers@superpowers-marketplace
```

### Blocked Plugins (for reference)

These are blocklisted and will not load even if installed:

| Plugin | Reason |
|--------|--------|
| `code-review@claude-plugins-official` | Blocked (test) |
| `fizz@testmkt-marketplace` | Blocked (security test) |

---

## 9. Project Brain (M:\ Drive)

Since this guide lives on M:\, the project brain is already here. Just plug in the drive and open Claude Code at `M:\`.

### Structure

```
M:\
├── CLAUDE.md                          # Root context (auto-loads in Claude Code)
├── CLAUDE_CODE_SETUP_GUIDE.md         # This file
├── MASTER_INDEX.md                    # All 17 projects in one table
├── brain-scan-templates.md            # Formatting templates for generated content
├── projects/                          # Condensed summaries by category
│   ├── music/
│   ├── comics/
│   ├── writing/
│   ├── video/
│   ├── hardware/
│   ├── dev-tools/
│   └── apps/
├── archive/                           # Verbatim copies of source CLAUDE.md files
│   └── raw-claude-mds/
│       └── [category]/
├── portfolio/                         # Career/consulting files
│   ├── tech-skills.md
│   ├── project-portfolio.md
│   └── services.md
└── .claude/
    └── skills/
        ├── brain-scan/SKILL.md        # Portable /brain-scan skill
        └── brain-update/SKILL.md      # Portable /brain-update skill
```

### On a New Machine

Just open Claude Code at `M:\` — the `CLAUDE.md` auto-loads and everything works. The `.claude/skills/` on M:\ provide the `/brain-scan` and `/brain-update` commands specific to this drive.

---

## 10. Project Memory Structure

Claude Code maintains per-project memory files that persist across conversations.

**Location pattern:** `~/.claude/projects/[drive-slug]/memory/MEMORY.md`

These are auto-created by Claude Code as you work — **no need to copy them**. They'll rebuild naturally as you use Claude Code on each project.

### Current Memory Directories (for reference)

| Path | Project |
|------|---------|
| `~/.claude/projects/M--/memory/MEMORY.md` | M:\ Project Brain |
| `~/.claude/projects/L--Memphis-Cursed-Rap/memory/MEMORY.md` | Memphis Cursed Rap |
| `~/.claude/projects/L--Folk-Songs-For-Bad-People/memory/MEMORY.md` | Folk Songs For Bad People |
| `~/.claude/projects/G--/memory/MEMORY.md` | G:\ Drive |
| `~/.claude/projects/G--Comic-Book-Creation-Space/memory/MEMORY.md` | Comic Book Creation Space |

Additional MEMORY.md files exist within some projects themselves:
- `L:\Memphis_Cursed_Rap\docs\MEMORY.md`
- `C:\Users\srco1\Desktop\Projects\YesterdaysWeekendWorkspace\FuckMeFundMeFeedMe\docs\MEMORY.md`

---

## 11. Quick Setup Checklist

Fastest path to a fully working Claude Code environment on a new machine:

### Install (one-time)

1. Install **Node.js** v22.x LTS from [nodejs.org](https://nodejs.org/)
2. Install **Git** from [git-scm.com](https://git-scm.com/)
3. Install **Python** 3.13.x from [python.org](https://python.org/)
4. Install Claude Code:
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```
5. Run `claude` and complete the **OAuth login**

### Configure

6. Install GSD (this sets up hooks, agents, commands, and settings automatically):
   ```bash
   npm install -g get-shit-done-cc
   ```
7. Copy the `settings.json` from [Section 3](#3-global-settings) to `~/.claude/settings.json`
   - Update the hook paths to match the new machine's home directory
   - Or just let GSD's installer handle this — it writes settings.json during install
8. Create the brain scan command manually:
   ```bash
   mkdir -p ~/.claude/commands/brain
   ```
   Then create `~/.claude/commands/brain/scan.md` with the contents from [Section 6](#6-global-slash-commands-non-gsd)
9. Create the three skill directories:
   ```bash
   mkdir -p ~/.claude/skills/changelog-generator
   mkdir -p ~/.claude/skills/systematic-debugging
   mkdir -p ~/.claude/skills/simplification-cascades
   ```
   Then create each `SKILL.md` with the contents from [Section 7](#7-global-skills)
10. Install the superpowers plugin:
    ```bash
    claude plugins install superpowers@superpowers-marketplace
    ```

### Connect the Brain

11. Plug in the **M:\ drive**
12. Open Claude Code at `M:\` — the brain auto-loads via `CLAUDE.md`

### Verify

- Run `/gsd:help` — should list all GSD commands
- Run `/brain:scan` — should detect drives and show scan options
- Check the status line shows model name and context bar
- Type "use the changelog generator skill" — should activate

---

*Generated from the live environment on machine `srco1` — 2026-02-28*
