---
name: brain-scan
description: Scan a project directory and catalog it into the Project Brain. Use when the user wants to add a new project to the brain or update an existing project entry.
argument-hint: <path-to-scan>
---

# Brain Scan Command

You are scanning a project directory to extract and catalog it into the Project Brain on this drive.

## Your Task

The user will provide a path to scan (as $ARGUMENTS). You must:

1. **Find and read all CLAUDE.md files** in the target path (recursively)
2. **Generate outputs** following the templates in `brain-scan-templates.md` (located in the brain root)
3. **Update the brain** with new or updated project information

## Step-by-Step Process

### Step 1: Gather Information
- Scan the provided path ($ARGUMENTS) for `CLAUDE.md` and `MEMORY.md` files
- Read each file to understand the project
- Identify: project name, category, tech stack, accomplishments, current state

### Step 2: Determine Category
Assign to one of these categories based on project content:
- `music` — Audio production, albums, sound design
- `comics` — Comic generation, image pipelines
- `writing` — Editorial, manuscripts, content
- `video` — Video production, streaming
- `hardware` — IoT, electronics, physical devices
- `dev-tools` — MCP servers, CLI tools, integrations
- `apps` — Desktop/web applications
- `business` — Business planning, ventures, operations
- `games` — Game design, game development

**Note:** If the scanned content is creative work (scripts, standalone writing, music ideas) rather than a dev project, route it to the `creative/` directory instead of `projects/`. Use `/brain-discover` for bulk creative content scanning.

### Step 3: Archive Raw Files
Copy the original CLAUDE.md content to:
```
archive/raw-claude-mds/[category]/[project-slug]-CLAUDE.md
```

### Step 4: Create Project Summary
Create a condensed summary at:
```
projects/[category]/[project-slug].md
```

Follow the **Project Summary Template** from `brain-scan-templates.md` exactly. Include frontmatter with `tags:`, `type:`, `status:`, and `related:` fields.

### Step 5: Update Project Index
Add or update a row in `projects/_INDEX.md` following the table format in the templates. Use `[[wiki links]]` for the project name.

### Step 6: Update Portfolio (if significant)
For substantial projects, consider updating:
- `portfolio/tech-skills.md` — Add any new technologies
- `portfolio/project-portfolio.md` — Add accomplishment narrative
- `portfolio/services.md` — Link as evidence for relevant services

### Step 7: Add Wiki Links
Ensure the new project summary contains `[[wiki links]]` to:
- All people mentioned
- All related projects
- All groups/organizations
- Technologies that have their own brain entries

## Deduplication Rules

Apply these rules from the templates:
- Template copies (referencing a shared template) are projects USING the template
- Sub-projects under the same parent = ONE consolidated project
- Versioned directories (v2, v3, etc.) = ONE project with multiple archived files
- Claude Code memory mirrors at `~/.claude/projects/...` are references, not separate projects

## Output

After scanning, report:
1. Projects found and processed
2. Files created/updated
3. Wiki links added
4. Any issues or duplicates detected

---

**Usage:** `/brain-scan [path-to-scan]`

Example: `/brain-scan ~/Projects/my-new-project`

If no path is provided, ask the user which directory they want to scan.
