# Claude Brain Toolkit

A persistent knowledge layer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Brain mode gives Claude memory across sessions — it loads your past context at startup, captures what you learn as you work, and surfaces relevant knowledge when you need it. No manual commands required.

## What It Does

Without brain mode, every Claude Code session starts from zero. With it:

- **Session start:** Hooks automatically load your vault context — projects, pitfalls, patterns — into Claude's context window
- **While you work:** Error pattern recognition surfaces past solutions when you hit a known error. Git commits are detected for potential capture.
- **When you pause:** An idle detection hook gently offers to capture useful patterns from the session
- **Session end:** A smart stop hook evaluates whether the session produced something worth capturing, and only triggers when it did
- **Statusline:** Shows brain state at a glance — idle, captured, or error

Everything runs through Claude Code's hook system. You just work normally.

## Quick Start

### Prerequisites

- [Node.js](https://nodejs.org/) (for Claude Code)
- [Git](https://git-scm.com/)
- [jq](https://jqlang.github.io/jq/download/) (JSON processing)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)

### Install

```bash
git clone https://github.com/bizzar0helldemon/claude-brain-toolkit.git
cd claude-brain-toolkit
bash onboarding-kit/setup.sh
```

The setup script:
1. Deploys the `brain-mode` agent to `~/.claude/agents/`
2. Installs global skills (`/brain-capture`, `/daily-note`, `/brain-audit`, `/brain-setup`)
3. Deploys all hook scripts to `~/.claude/hooks/`
4. Registers hooks in `~/.claude/settings.json` (idempotent — safe to re-run)
5. Deploys slash commands (`/brain-add-pattern`, `/brain-relocate`)
6. Deploys the statusline script
7. Verifies everything is in place

### First Run

```bash
claude --agent brain-mode
```

On first run, `BRAIN_PATH` won't be set yet. Claude will detect this and offer to run `/brain-setup`, which walks you through:
- Choosing a vault directory
- Creating the directory structure
- Setting `BRAIN_PATH` in your shell profile and `settings.json`

After setup, restart Claude Code and brain mode is active.

## How It Works

### Hook Architecture

Brain mode uses 5 globally-deployed hook events:

| Hook | Event | What It Does |
|------|-------|-------------|
| `session-start.sh` | SessionStart | Loads vault context into Claude's context window. Caches for fast `/clear` reloads. |
| `pre-compact.sh` | PreCompact | Triggers capture before context window compaction. |
| `post-tool-use.sh` | PostToolUse | Detects git commits and suggests capture. |
| `post-tool-use-failure.sh` | PostToolUseFailure | Matches errors against stored patterns and surfaces past solutions with adaptive tier responses. |
| `notification-idle.sh` | Notification (idle) | Offers to capture when the session has content and the user pauses. One offer per session. |

A `stop.sh` hook is also included in the repo for project-level use (smart capture detection at session end) but is not deployed globally to avoid interfering with `/clear`.

### Shared Libraries

| Library | Provides |
|---------|----------|
| `brain-path.sh` | `brain_path_validate`, `emit_json`, `brain_log_error`, `has_capturable_content`, `write_brain_state`, pattern store functions |
| `brain-context.sh` | `build_brain_context`, `build_summary_block`, vault scanning, token budget enforcement |

### Error Pattern Intelligence

When a command fails, the `PostToolUseFailure` hook checks your pattern store (`$BRAIN_PATH/brain-mode/pattern-store.json`) for matches. Responses adapt based on how many times you've seen the error:

| Encounters | Response |
|-----------|----------|
| 1st time | Full explanation with solution steps |
| 2-4 times | Brief reminder |
| 5+ times | Root cause investigation flag |

Add patterns with `/brain-add-pattern` after solving a recurring error, or let Claude suggest it when it notices you fixing the same thing repeatedly.

### Statusline

The statusline shows brain state at a glance in your Claude Code terminal:

| State | Display | Meaning |
|-------|---------|---------|
| Idle | brain emoji | Brain active, no recent hook activity |
| Captured | green + brain emoji | Capture ran successfully |
| Error | red + brain emoji | A hook error or degraded state |

## Commands

| Command | What It Does |
|---------|-------------|
| `/brain-capture` | Extract patterns, prompts, and lessons from the current conversation |
| `/daily-note` | Log a journal entry to `daily_notes/` |
| `/brain-audit` | Run a vault health check (stale entries, missing indexes, broken links) |
| `/brain-add-pattern` | Add an error pattern and solution to the pattern store |
| `/brain-relocate` | Move your vault to a new path (updates settings.json and shell profile) |
| `/brain-setup` | First-time onboarding wizard |

## Vault Structure

Your vault lives at `$BRAIN_PATH` — wherever you choose during setup. The toolkit creates and uses:

```
$BRAIN_PATH/
  brain-mode/
    pattern-store.json     # Error patterns and solutions
    capture-YYYY-MM-DD.md  # Session captures
  daily_notes/
    YYYY-MM-DD.md          # Daily journal entries
  projects/                # Project summaries
  prompts/                 # Prompt and pattern library
  .brain-state             # Current hook state (idle/captured/error)
  .brain-cached-context.json  # Cached context for fast /clear
  .brain-errors.log        # Hook error log
```

The vault is Obsidian-compatible but doesn't require Obsidian. Wiki links (`[[Project Name]]`) resolve between documents, and frontmatter tags are searchable.

## Configuration

Brain mode needs one environment variable:

```bash
export BRAIN_PATH="/path/to/your/vault"
```

This is set in two places (both are needed):
1. **Shell profile** (`~/.bashrc`, `~/.zshrc`, or `~/.bash_profile`) — for interactive terminal use
2. **`~/.claude/settings.json`** under `"env"` — for hook subprocesses (which don't load shell profiles)

The `/brain-setup` wizard handles both. If you need to move your vault later, `/brain-relocate` updates both locations.

## Project Structure

This repo is the toolkit source — what gets deployed to `~/.claude/` via `setup.sh`:

```
claude-brain-toolkit/
  agents/
    brain-mode.md           # Agent definition (deployed to ~/.claude/agents/)
  hooks/
    session-start.sh        # SessionStart hook
    pre-compact.sh          # PreCompact hook
    post-tool-use.sh        # PostToolUse hook (git commit detection)
    post-tool-use-failure.sh # PostToolUseFailure hook (error patterns)
    notification-idle.sh    # Notification hook (idle capture offer)
    stop.sh                 # Stop hook (project-level, not globally deployed)
    lib/
      brain-path.sh         # Shared utilities
      brain-context.sh      # Vault context builder
    tests/
      test-stop-signals.sh  # Signal detection tests
  commands/
    brain-add-pattern.md    # /brain-add-pattern slash command
    brain-relocate.md       # /brain-relocate slash command
  global-skills/
    brain-capture/          # /brain-capture skill
    brain-audit/            # /brain-audit skill
    daily-note/             # /daily-note skill
  onboarding-kit/
    setup.sh                # Automated installer
    skills/
      brain-setup/          # /brain-setup onboarding wizard
      changelog-generator/  # Changelog generation skill
      simplification-cascades/ # Code simplification skill
      systematic-debugging/ # Structured debugging skill
  settings.json             # Template settings (merged into user's settings)
  statusline.sh             # Statusline display script
  frameworks/               # AI Fluency Framework reference
  desktop-skill/            # Brain Assistant for Claude Desktop (experimental)
```

## Developing

If you're working on the toolkit itself:

1. Clone the repo
2. Create a `CLAUDE.local.md` (gitignored) with your real `BRAIN_PATH` so brain mode works during development
3. Run `bash onboarding-kit/setup.sh` after changes to deploy to `~/.claude/`

Changes to hook scripts in the repo don't take effect until deployed — the running hooks are the copies in `~/.claude/hooks/`.

## License

MIT. See [LICENSE](LICENSE).

AI Fluency Framework content adapted from Dakan & Feller (CC BY-NC-ND 4.0). See [frameworks/ai-fluency-framework.md](frameworks/ai-fluency-framework.md) for full attribution.
