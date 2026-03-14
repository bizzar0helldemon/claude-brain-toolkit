---
name: brain-audit
description: Run a vault health check — finds broken links, empty files, naming violations, missing frontmatter, orphaned files, and index drift. Use to maintain vault consistency after scans, intakes, and captures.
argument-hint: "[area] [fix]" — areas: links, formatting, indexes, orphans, all (default). Add "fix" to auto-repair safe issues.
---

# Brain Audit Command

You are running a health check on the Claude Brain vault to find and optionally fix structural issues.

## Arguments

Parse `$ARGUMENTS` for:
- **Area filter:** `links`, `formatting`, `indexes`, `orphans`, or `all` (default if omitted)
- **Fix mode:** if the word `fix` appears anywhere in arguments, enable fix mode

Examples:
- `/brain-audit` → full audit, report only
- `/brain-audit links` → check only wiki links
- `/brain-audit fix` → full audit with auto-fix offers
- `/brain-audit formatting fix` → check formatting and offer fixes

## Vault Location

The brain vault root is: `{{SET_YOUR_BRAIN_PATH}}`

Read `brain-scan-templates.md` from the vault root for canonical template definitions.

## Audit Process

Run checks in this order, collecting all findings before reporting. Use the Glob and Grep tools extensively — do NOT shell out to grep/find.

### Phase 1: Discovery

Collect all `.md` files in the vault recursively using Glob (`**/*.md`). Exclude:
- `.claude/` directory (skills, settings)
- `archive/raw-claude-mds/` (raw copies, not governed by templates)
- `node_modules/`, `.git/`

For each file, read its content and parse frontmatter (YAML between `---` delimiters).

### Phase 2: Critical Checks

**2a. Empty Files**
Flag any file that is 0 bytes OR has no content beyond frontmatter (empty body after the closing `---`).

**2b. Broken Wiki Links**
- Extract all `[[...]]` wiki links from every scanned file
- Build a map of all file titles (from frontmatter `title:` field) and filenames (without extension)
- A wiki link `[[Target]]` is valid if ANY of these match (case-insensitive):
  - A file's frontmatter `title:` equals "Target"
  - A filename (minus `.md`) equals "Target" or its kebab-case equivalent
  - A file exists at any path whose basename matches
- Report each broken link with the file(s) that reference it

**2c. File Naming Violations**
Flag any `.md` file whose name contains spaces (should be kebab-case). Exceptions:
- `CLAUDE.md`, `MEMORY.md`, `IDENTITY.md`, `MASTER_INDEX.md`, `_INDEX.md`, `README.md`, `_DESIGN.md`, `LICENSE` — uppercase convention files are OK
- Files in `archive/raw-claude-mds/` — those follow their own convention

**2d. Index Integrity**
For each index file (`projects/_INDEX.md`, `prompts/_INDEX.md`, `creative/_INDEX.md` if it exists):
- Extract all `[[wiki links]]` from the index
- Check each points to an existing file
- Check for files that exist in the directory but are NOT listed in the index

### Phase 3: High Priority Checks

**3a. Frontmatter Completeness**
Check required fields based on the `type:` value in frontmatter:

| type | Required fields |
|------|----------------|
| `project` | title, type, category, status, location, tags, related |
| `prompt-pattern` | title, type, domain, interaction-mode, ai-fluency-dimensions, tags, effectiveness, created, last-used, related |
| `daily-note` | date, type, tags |
| `guided-intake` | title, date, topic, type, tags |
| `identity` | title, type, tags |
| `index` | title, type, tags |
| `comedy-script` | title, date, performers, status, type, tags |
| `comedy-show` | title, date, venue, group, type, tags |

If `type:` is missing entirely, flag as "no type field."
If `type:` doesn't match any known type above, flag as "non-standard type."

**3b. Required Body Sections**
For `project` type files, check these H2 sections exist:
- `## What It Is`
- `## Tech Stack`
- `## Current State`

For `prompt-pattern` type files, check:
- `## When to Use`
- `## The Prompt`
- `## Why It Works`

**3c. Malformed Wiki Links**
Find patterns that look like broken wiki link syntax:
- `[[` without matching `]]` on the same line
- `]]` without preceding `[[` on the same line
- Empty links `[[]]`

### Phase 4: Medium Priority Checks

**4a. Frontmatter Value Validation**
- `tags:` should be an array of kebab-case values
- `status:` should be a recognized value (Active, Complete, Paused, Early Dev, or compound like "Active — Lyrics phase")
- `category:` should match one of: music, comics, writing, video, hardware, dev-tools, apps, business, games
- `effectiveness:` should be: high, medium, experimental
- `date:` and `created:` fields should be YYYY-MM-DD format

**4b. Duplicate Detection**
Flag files in the same category directory with very similar names (e.g., same project filed under two slugs).

**4c. Orphan Detection**
Find `.md` files that:
- Have no incoming wiki links from any other file
- Are not listed in any index
- Are not top-level structural files (CLAUDE.md, IDENTITY.md, brain-scan-templates.md, MASTER_INDEX.md)

## Reporting

After all checks complete, output a structured report:

```markdown
## Brain Audit Report

### Critical Issues (N)
- ❌ [Issue description with file path]

### High Issues (N)
- ⚠️ [Issue description with file path]

### Medium Issues (N)
- 💡 [Issue description with file path]

### Summary
- **Files scanned:** N
- **Issues found:** N (Critical: N, High: N, Medium: N)
- **Wiki links checked:** N (N broken)
- **Index entries verified:** N
```

If an area filter was specified, only show results for that area. Always show the summary line.

## Fix Mode

If fix mode is enabled, after showing the report, work through fixable issues:

### Auto-fixable (with confirmation per action):
1. **Empty files** — Ask "Delete [filename]? (y/n)" before each deletion
2. **Naming violations** — Rename file to kebab-case, then use Grep to find all `[[Old Name]]` references and update them to `[[new-name]]`
3. **Missing frontmatter fields** — Add missing fields with value `[NEEDS UPDATE]`
4. **Index gaps** — Add missing entries to the relevant index file with `[NEEDS AUDIT]` placeholder description

### NOT auto-fixable (report only):
- Broken wiki links (human decision: create file? remove link? fix the name?)
- Non-standard type values (needs human judgment on correct type)
- Duplicate files (needs human to decide which to keep)
- Missing body sections (needs human to write content)

For each fix action, show what will change and ask for confirmation before proceeding. Group related fixes (e.g., "Rename file AND update 3 references").

## Important Notes

- NEVER delete files without explicit user confirmation
- NEVER modify file content beyond frontmatter fixes without confirmation
- When renaming files, ALWAYS update all wiki link references
- Read `brain-scan-templates.md` at the start for current template definitions
- If the vault is large, use Glob/Grep efficiently — don't read every file line by line when a pattern search suffices
- Report real file paths relative to the vault root for readability
