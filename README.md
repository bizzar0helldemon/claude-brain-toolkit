# Claude Brain Toolkit

A personal knowledge hub powered by [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skills. Capture who you are, catalog your projects, extract what works, and build a brain that grows with you.

## What This Is

Claude Brain is an Obsidian-compatible vault paired with 6 Claude Code slash commands. Together, they give Claude persistent knowledge about you — your projects, your working style, your effective prompts, and your creative history. Instead of starting every conversation from scratch, Claude can reference your brain and pick up where you left off.

The toolkit is grounded in the [AI Fluency Framework](frameworks/ai-fluency-framework.md) — a set of four competencies (Delegation, Description, Discernment, Diligence) for working effectively, efficiently, ethically, and safely with AI.

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/YOUR_USERNAME/claude-brain-toolkit.git
```

### 2. Install global skills

Two skills (`/brain-capture` and `/daily-note`) need to work from any project, not just the brain vault. Copy them to your global skills directory:

```bash
cp -r claude-brain-toolkit/global-skills/* ~/.claude/skills/
```

### 3. Set your brain path

Replace `{{SET_YOUR_BRAIN_PATH}}` with your actual brain path in two files:

- `~/.claude/skills/brain-capture/SKILL.md`
- `~/.claude/skills/daily-note/SKILL.md`

For example, if you cloned to `~/claude-brain-toolkit`, replace all instances of `{{SET_YOUR_BRAIN_PATH}}` with `~/claude-brain-toolkit`.

### 4. Start building your brain

```bash
cd claude-brain-toolkit
claude
```

Then run:

```
/brain-intake
```

Claude will start a guided interview to learn about you. Your first session might cover your career, your creative work, or what you're currently building.

## Skills Reference

| Command | What It Does |
|---------|-------------|
| `/brain-intake [topic]` | Guided interview to capture personal knowledge — career, creative work, values, communication preferences |
| `/brain-scan [path]` | Scan a project directory and catalog it into the brain with a structured summary |
| `/brain-discover [path]` | Scan a drive or directory for creative content not yet captured in the brain |
| `/brain-update [name]` | Update an existing project entry after doing more work on it |
| `/brain-capture [hint]` | Extract effective prompts and interaction patterns from the current conversation |
| `/daily-note [content]` | Log a journal entry to today's daily note |

### Usage Examples

```
/brain-intake career          # Interview about your professional history
/brain-intake creative        # Interview about your creative work and influences
/brain-scan ~/Projects/my-app # Catalog a project into the brain
/brain-discover ~/Documents   # Find creative content not yet in the brain
/brain-update my-app          # Update a project entry after new work
/brain-capture                # Extract patterns from the current conversation
/brain-capture that debug approach  # Focus on a specific technique
/daily-note Fixed the auth bug     # Quick journal entry
```

## Vault Structure

```
claude-brain-toolkit/
├── .claude/skills/        # Project-scoped skills (work when brain is open)
├── global-skills/         # Copy these to ~/.claude/skills/ during setup
├── frameworks/            # AI Fluency Framework + governance policy template
├── prompts/               # Prompt & pattern library (organized by domain)
├── projects/              # Project summaries cataloged by /brain-scan
├── creative/              # Creative works, writing, art, music concepts
├── intake/                # Interview sessions from /brain-intake
├── portfolio/             # Tech skills, services, project portfolio
├── daily_notes/           # Journal entries from /daily-note
├── people/                # Notes about collaborators and contacts
├── archive/               # Raw CLAUDE.md backups from scanned projects
├── IDENTITY.md            # Your personal profile (built via /brain-intake)
├── CLAUDE.md              # Hub document + configuration
└── brain-scan-templates.md # Canonical templates for all document types
```

### What Goes Where

| Directory | Populated By | Contains |
|-----------|-------------|---------|
| `projects/` | `/brain-scan` | Structured summaries of your dev/creative projects |
| `creative/` | `/brain-intake`, `/brain-discover` | Creative works, writing, art concepts |
| `intake/` | `/brain-intake` | Session transcripts and discovery logs |
| `prompts/` | `/brain-capture` | Effective prompt templates organized by domain |
| `daily_notes/` | `/daily-note` | Journal entries, session summaries, insights |
| `portfolio/` | `/brain-scan`, manual | Career materials — skills, services, project portfolio |
| `people/` | `/brain-intake`, manual | Notes about collaborators and contacts |
| `frameworks/` | Manual | Reference frameworks and governance docs |

## Obsidian Integration

This vault is designed to work with [Obsidian](https://obsidian.md/) but doesn't require it. If you use Obsidian:

- Open the `claude-brain-toolkit` directory as an Obsidian vault
- Wiki links (`[[Project Name]]`) will resolve between documents
- Frontmatter tags are searchable via Obsidian's tag panel
- [Dataview](https://github.com/blacksmithgu/obsidian-dataview) queries can filter by `type`, `status`, `tags`, etc.

### Linking Conventions

- **People:** `[[First Last]]` or `[[Nickname]]`
- **Projects:** `[[Project Name]]` matching the frontmatter `title:`
- **Groups:** `[[Group Name]]`
- **Tags:** kebab-case in frontmatter arrays (e.g., `tags: [project, web-dev]`)
- **File names:** kebab-case (e.g., `my-project-name.md`)

## Customization

### Adding Your Own Domains

The prompt library ships with domains like `coding/`, `writing/`, `music/`, etc. Add your own:

1. Create a new subdirectory under `prompts/` (e.g., `prompts/data-science/`)
2. The `/brain-capture` skill will detect it automatically

### Adding Templates

All document templates live in `brain-scan-templates.md`. To add a new type:

1. Add a template section to `brain-scan-templates.md`
2. Define the frontmatter fields and section structure
3. Reference it in the relevant skill's instructions

### Customizing Intake Topics

The `/brain-intake` skill has default topic areas (life story, career, creative work, etc.). To add your own:

1. Edit `.claude/skills/brain-intake/SKILL.md`
2. Add your topic to the list in the "Topic Areas" section
3. Add routing rules in the "Integrate Into Brain" section

## The AI Fluency Framework

This toolkit is built on the Framework for AI Fluency by Dakan & Feller — four competencies for effective AI interaction:

| Competency | What It Means |
|-----------|--------------|
| **Delegation** | Deciding what work belongs to you, to AI, or to both |
| **Description** | Communicating effectively — prompts, constraints, role definition |
| **Discernment** | Critically evaluating AI output — never accepting at face value |
| **Diligence** | Taking full responsibility for AI-assisted work |

See [frameworks/ai-fluency-framework.md](frameworks/ai-fluency-framework.md) for the full reference, and [frameworks/ai-governance-policy.md](frameworks/ai-governance-policy.md) for a template to define your own AI governance standards.

## Optional: Obsidian CLI

For power users, [obsidian-cli](https://github.com/jwhonce/obsidian-cli) provides command-line access to your vault. It's not required — all skills work without it.

## License

MIT. See [LICENSE](LICENSE).

AI Fluency Framework content adapted from Dakan & Feller (CC BY-NC-ND 4.0). See [frameworks/ai-fluency-framework.md](frameworks/ai-fluency-framework.md) for full attribution.
