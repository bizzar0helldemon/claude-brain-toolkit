# Claude Brain Partner Kit — Setup Instructions

> **You are reading this in Claude Desktop.** Follow these instructions to set up a fully configured Claude Code CLI environment with a personal knowledge brain.
>
> **This file is for Claude to read and execute.** When the user says "set me up" or "let's get started," walk them through each section step by step.

---

## What This Kit Contains

This zip contains everything needed to set up:

1. **Claude Code CLI** — The terminal-based Claude interface (more powerful than Desktop)
2. **GSD (Get Shit Done)** — 28 slash commands for project management
3. **Superpowers** — Community skills marketplace
4. **Global Skills** — Debugging, changelog generation, daily notes, brain capture
5. **Claude Brain Vault** — A personal knowledge hub (Obsidian-compatible) that grows with the user
6. **Brain Skills** — Project scanning, intake interviews, drive discovery

## How to Use This File

When the user asks to get set up, walk them through the sections below **in order**. Check each prerequisite before moving on. Be conversational — don't dump the whole guide at once.

---

## Phase 1: Prerequisites

Ask the user to confirm they have these installed. If not, provide the download links.

### Required Software

| Tool | Check Command | Install From |
|------|--------------|-------------|
| **Node.js v22+** | `node --version` | [nodejs.org](https://nodejs.org/) — download the LTS version |
| **Git** | `git --version` | [git-scm.com](https://git-scm.com/) |
| **Python 3.12+** | `python --version` | [python.org](https://python.org/) |

Tell the user: "Open a terminal (PowerShell, Command Prompt, or Git Bash on Windows; Terminal on Mac) and run these commands to check."

If anything is missing, help them install it before continuing.

---

## Phase 2: Install Claude Code CLI

```bash
npm install -g @anthropic-ai/claude-code
```

Then have them run `claude` once to complete OAuth login. It opens a browser — they log in with their Anthropic/Claude account.

**Important:** Claude Code requires a Claude Max subscription ($100/month) or API credits. Confirm the user has one of these.

---

## Phase 3: Install GSD + Superpowers

These two commands install the project management system and skills marketplace:

```bash
npm install -g get-shit-done-cc
claude plugins install superpowers@superpowers-marketplace
```

GSD automatically sets up:
- 28 slash commands in `~/.claude/commands/gsd/`
- 11 agent definitions in `~/.claude/agents/`
- Hook scripts for session start and status line
- `~/.claude/settings.json` with hook configurations

---

## Phase 4: Install Global Skills

The user needs to copy skill files from this kit to their Claude Code skills directory.

**Ask the user:** "Where did you unzip this kit? I need the path so I can give you the exact copy commands."

Then provide these commands (replace `KIT_PATH` with their actual path):

### Windows (Git Bash or WSL):
```bash
mkdir -p ~/.claude/skills
cp -r "KIT_PATH/skills/"* ~/.claude/skills/
```

### Windows (PowerShell):
```powershell
$skillsDir = "$env:USERPROFILE\.claude\skills"
New-Item -ItemType Directory -Force -Path $skillsDir
Copy-Item -Recurse -Force "KIT_PATH\skills\*" $skillsDir
```

### Mac/Linux:
```bash
mkdir -p ~/.claude/skills
cp -r "KIT_PATH/skills/"* ~/.claude/skills/
```

This installs 5 global skills:
- `changelog-generator` — Git commits to user-friendly changelogs
- `systematic-debugging` — Four-phase debugging framework
- `simplification-cascades` — Find simplifying insights
- `daily-note` — Journal entries into the brain vault
- `brain-capture` — Extract effective prompts/patterns from conversations

---

## Phase 5: Install Brain Scan Command

```bash
mkdir -p ~/.claude/commands/brain
cp "KIT_PATH/commands/brain/scan.md" ~/.claude/commands/brain/scan.md
```

---

## Phase 6: Set Up the Brain Vault

**Ask the user:** "Where do you want your personal brain vault to live? This is where Claude stores everything it learns about you, your projects, and your work. Good locations:"
- `~/Documents/claude_brain/` (safe, usually backed up)
- `~/Desktop/memory/claude_brain/` (easy access)

Once they choose a path, clone the brain toolkit:

```bash
git clone https://github.com/bizzar0helldemon/claude-brain-toolkit.git "CHOSEN_PATH"
```

**Then copy the global skills from the brain vault to ~/.claude/skills/:**
```bash
cp -r "CHOSEN_PATH/global-skills/"* ~/.claude/skills/
```

---

## Phase 7: Configure Paths in Skills

Two skill files need the brain vault path set. The user needs to edit:

1. `~/.claude/skills/daily-note/SKILL.md`
2. `~/.claude/skills/brain-capture/SKILL.md`

In each file, replace every instance of `{{BRAIN_PATH}}` with the actual brain vault path.

**Windows path example:** `C:/Users/TheirName/Documents/claude_brain`
**Mac/Linux path example:** `/home/theirname/Documents/claude_brain`

**Important:** Use forward slashes even on Windows (`C:/Users/...` not `C:\Users\...`).

---

## Phase 8: Verify Settings

Check that `~/.claude/settings.json` exists and has the right content. GSD should have created it during Phase 3, but verify:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node \"PATH_TO_HOME/.claude/hooks/gsd-check-update.js\""
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "node \"PATH_TO_HOME/.claude/hooks/gsd-statusline.js\""
  },
  "enabledPlugins": {
    "superpowers@superpowers-marketplace": true
  }
}
```

The hook paths should point to the user's actual home directory.

---

## Phase 9: First Run + Brain Intake

Now the user opens Claude Code CLI in their brain vault:

```bash
cd "CHOSEN_PATH"
claude
```

Have them run these verification commands inside Claude Code:
1. `/gsd:help` — should list all GSD commands
2. `/daily-note test` — should create a daily note file
3. Check the status line at the bottom shows model name and context bar

**Then run the brain intake:**
```
/brain-intake
```

This starts a guided interview that teaches Claude about the user — their role, skills, interests, and communication preferences. This is the most important step. The better Claude knows them, the more useful it becomes.

---

## Phase 10: Connect Claude Desktop to the Brain

**This step lets Claude Desktop and Claude Code CLI share the same brain vault.**

In Claude Desktop:
1. Go to **Settings** (gear icon)
2. Navigate to **Projects** or **Knowledge** settings
3. Create a new Project called "My Brain" (or whatever they prefer)
4. Add the brain vault directory as a **Project Knowledge** source
5. Add the vault's `CLAUDE.md` file specifically — this gives Desktop the full context

Now when they use Claude Desktop with that project selected, it has access to the same brain vault that Claude Code CLI uses. Both tools read and write to the same directory.

**Key difference:**
- **Claude Code CLI** = full power (skills, GSD, hooks, file editing, bash commands)
- **Claude Desktop** = simpler conversations with brain context (good for quick questions, brainstorming)

---

## Important Boundaries

### Brain Vault = Personal Knowledge Hub
- The brain vault is the user's personal knowledge system
- It's NOT shared with other people unless they choose to
- All data stays on their machine (only sent to Claude API during active conversations)

### Separate Vaults for Separate Projects
- **Main brain** = the vault set up above (personal knowledge hub)
- **FishHook Synch** = a completely separate project vault — NOT part of the brain
- Other projects may have their own CLAUDE.md files — those are project-specific, not brain-wide
- When working on a specific project, open Claude Code in THAT project's directory

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `claude` command not found | `npm install -g @anthropic-ai/claude-code` |
| `/gsd:help` doesn't work | `npm install -g get-shit-done-cc` |
| Skills not showing up | Check `~/.claude/skills/` has SKILL.md files in subdirectories |
| Daily note writes to wrong path | Edit `~/.claude/skills/daily-note/SKILL.md`, fix the path |
| Status line missing | Check `~/.claude/settings.json` exists with statusLine config |
| Brain commands don't work | Make sure Claude Code is opened IN the brain vault directory |
| OAuth expired | Run `claude` and re-authenticate in browser |

---

## Quick Reference Card

Once set up, these are the most useful commands:

| Command | What It Does |
|---------|-------------|
| `/brain-intake` | Guided interview — teach Claude about yourself |
| `/brain-scan [path]` | Catalog a project into the brain |
| `/daily-note [text]` | Quick journal entry |
| `/brain-capture` | Save effective prompts from the current conversation |
| `/gsd:new-project` | Start a new project with full planning |
| `/gsd:quick` | Quick task with atomic commits |
| `/gsd:progress` | Check project status |
| `/gsd:debug` | Systematic debugging |
