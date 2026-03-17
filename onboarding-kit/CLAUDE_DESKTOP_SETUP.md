# Using Claude Desktop with the Brain Vault

## Overview

Claude Desktop and Claude Code CLI can **share the same brain vault**. The CLI is more powerful (skills, GSD, hooks, bash access), but Desktop is great for quick conversations with full brain context.

## How to Connect Claude Desktop to Your Brain

### Step 1: Open Claude Desktop

Launch the Claude Desktop app (download from [claude.ai/download](https://claude.ai/download) if you don't have it).

### Step 2: Create a Project

1. Click the **Projects** icon in the sidebar (or go to Settings > Projects)
2. Click **Create Project**
3. Name it something like "My Brain" or "Personal Brain"

### Step 3: Add Brain Knowledge

In your project settings:

1. Click **Add Knowledge** or **Add Files**
2. Navigate to your brain vault directory
3. Add `CLAUDE.md` — this is the master context file that tells Claude how your brain is organized
4. Optionally add `IDENTITY.md` if you've run `/brain-intake` and want Desktop to know you too

### Step 4: Set Project Instructions (Optional)

In the project's **Custom Instructions** field, add:

```
You have access to my personal brain vault. Use the CLAUDE.md file to understand the vault structure. Reference projects, daily notes, and other brain content when relevant to our conversation.

My brain vault is at: [YOUR_BRAIN_PATH]
```

## What Works in Desktop vs CLI

| Feature | Claude Desktop | Claude Code CLI |
|---------|---------------|----------------|
| Read brain context | Yes (via project knowledge) | Yes (auto-loads CLAUDE.md) |
| `/brain-intake` | No | Yes |
| `/brain-scan` | No | Yes |
| `/daily-note` | No | Yes |
| `/brain-capture` | No | Yes |
| `/gsd:*` commands | No | Yes |
| Edit files | No | Yes |
| Run bash commands | No | Yes |
| Brainstorming | Yes | Yes |
| Quick questions | Yes | Yes |
| Code review | Limited | Full |

**Bottom line:** Use Desktop for thinking and talking. Use CLI for doing.

## Can Claude Desktop Use the Brain as a Skill Zip?

Currently, Claude Desktop doesn't support the same skill/command system that Claude Code CLI uses. You can't load SKILL.md files into Desktop as executable skills.

However, you **can** upload skill files as project knowledge — Claude will read them and understand the intended behavior, even though it can't execute the slash commands directly. It can still follow the documented processes manually when you ask.

## Keeping Both in Sync

Since both Desktop and CLI point to the same vault directory:
- Daily notes created via CLI (`/daily-note`) are visible in Desktop's project knowledge
- Identity and project info from `/brain-intake` is available to both
- Any files Claude Code writes to the vault are readable by Desktop

**No sync needed — they share the same files on disk.**

## Important

- **FishHook Synch is NOT part of the brain.** Don't add FishHook files to your brain project in Desktop.
- Each project you work on can have its own separate Claude Desktop project. Keep the brain project for brain-related conversations only.
