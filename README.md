# Claude Brain Toolkit

A persistent knowledge layer for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Brain mode gives Claude memory across sessions — it loads your past context at startup, captures what you learn as you work, and surfaces relevant knowledge when you need it.

## What It Does

Without brain mode, every Claude Code session starts from zero. With it:

- **Session start:** Hooks automatically load your vault context — projects, pitfalls, patterns — into Claude's context window
- **While you work:** Error pattern recognition surfaces past solutions. Safety hooks block dangerous commands and secret leaks before they happen. Session guardian monitors context usage and research focus.
- **When you pause:** An idle detection hook gently offers to capture useful patterns
- **Session end:** A smart stop hook evaluates whether the session produced something worth capturing
- **Statusline:** Two-row branded display with brain state, git info, context bar, lines changed, and session duration

Everything runs through Claude Code's hook system. You just work normally.

## Quick Start

### Prerequisites

- [Node.js](https://nodejs.org/) (for Claude Code)
- [Git](https://git-scm.com/)
- [jq](https://jqlang.github.io/jq/download/) (JSON processing)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)

### Platform Support

The toolkit is built on bash and POSIX tooling (`sed`, `grep`, `awk`, `mktemp`, `/tmp`, symlinks, `chmod`).

| Platform | Status | Notes |
|----------|--------|-------|
| **Linux** | ✅ Supported | |
| **macOS** | ✅ Supported | |
| **Windows (WSL)** | ✅ Supported | Use [WSL](https://learn.microsoft.com/windows/wsl/install). Keep the repo and your vault on the Linux filesystem (`~/`), **not** `/mnt/c/...`, for speed. |
| **Windows (native)** | ❌ Not supported | PowerShell/cmd lack bash; Git Bash / MSYS / Cygwin only partially work (missing GNU tools, unreliable symlinks). |

> **Windows users:** install WSL and run the toolkit from inside it. `setup.sh` runs a platform preflight — on a native Windows shell it warns, links to the WSL docs, and prompts before continuing rather than failing halfway through.

### Install

```bash
git clone https://github.com/bizzar0helldemon/claude-brain-toolkit.git
cd claude-brain-toolkit
bash onboarding-kit/setup.sh
```

The setup script:
1. Deploys the `brain-mode` agent to `~/.claude/agents/`
2. Installs all global skills (23 skills)
3. Deploys all hook scripts to `~/.claude/hooks/` (10 hooks + 2 libraries)
4. Registers hooks in `~/.claude/settings.json` (idempotent — safe to re-run)
5. Deploys slash commands and the statusline script
6. Verifies everything is in place

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

Brain mode uses hooks across 6 event types:

| Hook | Event | What It Does |
|------|-------|-------------|
| `session-start.sh` | SessionStart | Loads vault context into Claude's context window. Caches for fast `/clear` reloads. |
| `pre-compact.sh` | PreCompact | Triggers capture before context window compaction. |
| `post-tool-use.sh` | PostToolUse | Detects real git commits and appends a silent record to `brain-mode/commit-log.jsonl`. |
| `session-guardian.sh` | PostToolUse | Monitors context % (warns at 70%/85%) and detects runaway research loops (5+ reads without writes). |
| `post-tool-use-failure.sh` | PostToolUseFailure | Matches errors against stored patterns and surfaces past solutions with adaptive tier responses. |
| `risk-classifier.sh` | PreToolUse | Blocks dangerous bash commands (`git reset --hard`, `rm -rf /`, `chmod 777`, etc.). |
| `pre-commit-secrets.sh` | PreToolUse | Scans staged diffs for API keys, tokens, and private keys before allowing commits. |
| `loop-detector.sh` | PreToolUse | Catches agents repeating identical tool calls 5+ times and breaks the loop. |
| `notification-idle.sh` | Notification (idle) | Offers to capture when the session has content and the user pauses. One offer per session. |
| `stop.sh` | Stop | Writes a mechanical session receipt to `brain-mode/session-log.jsonl`, ingests new GSD `.planning/` artifacts into `inbox/captures/`, and issues one silent distillation prompt when the session had capturable content. |

Capture is **mechanical, not advisory**: `stop.sh` and `post-tool-use.sh` write to the vault themselves rather than asking you to run `/brain-capture`. The Stop hook is deployed and registered by default.

### Memory Lifecycle — the feedback loop

Capture alone just accumulates. The gardener closes the loop so notes earn or lose their place in the session-start budget based on whether they actually get used:

1. **Surface** — `session-start.sh` logs every injected note to `brain-mode/surface-log.jsonl`.
2. **Observe** — `post-tool-use.sh` logs a `used` event to `brain-mode/retrieval-log.jsonl` whenever a vault note is Read.
3. **Adjust** — `tools/brain-gardener.py` (lazy weekly trigger from `session-start.sh`, at most once per 7 days) folds those events into each note's frontmatter counters and applies status transitions:

   ```
   warm --(used ≥2×)--> hot
   hot  --(surfaced ≥8× with 0 uses, or 30d cold)--> warm
   warm --(90d idle, never used)--> archive        # skipped at session start, still searchable
   archive --(180d further idle)--> tombstone       # body kept on disk forever
   any archived/tombstoned --(any use)--> resurrected
   ```

   Exempt from decay (`decays: false`): `preference`, `identity`, `synthesis`. A **cold-start epoch** (`brain-mode/.brain-gardener-epoch`) measures idle time from when the loop began observing, so legacy notes are never archived before they've had a chance to surface. Every pass writes a dated `daily_notes/<date>-memory-health.md` report and a `brain-mode/metrics.jsonl` line, and commits the vault. Run it by hand anytime with `python3 tools/brain-gardener.py` (dry run) or `--apply`.

### Safety Hooks (PreToolUse)

Three hooks run before every tool call to prevent common mistakes:

**Risk Classifier** — hard-blocks destructive commands:
- `git reset --hard`, `git clean -f`, force push to main/master
- `rm -rf` on broad paths, `chmod 777`
- `DROP TABLE`, `TRUNCATE`, `DELETE FROM` without WHERE
- Advisory warnings for `--no-verify`, `git checkout .`

**Pre-Commit Secrets** — blocks commits containing:
- API keys (AWS, GitHub, Anthropic, OpenAI, Stripe, Google, Slack)
- Private keys (RSA, SSH, PGP), JWT tokens
- Database connection strings with embedded passwords, `.env` files

**Loop Detector** — tracks tool calls in a rolling window and blocks after 5+ identical calls with a diagnostic message.

### Session Intelligence

**Session Guardian** monitors two risks that cause partial achievement:
- **Context exhaustion:** Warns at 70% usage, urgently prompts handoff at 85%
- **Runaway research:** Flags 5+ consecutive read operations without writes

Run `/session-guardian` anytime for a status check.

### Error Pattern Intelligence

When a command fails, the `PostToolUseFailure` hook checks your pattern store for matches. Responses adapt:

| Encounters | Response |
|-----------|----------|
| 1st time | Full explanation with solution steps |
| 2-4 times | Brief reminder |
| 5+ times | Root cause investigation flag |

### Statusline

Two-row branded display with 256-color support:

```
🧠 Brain │ 📂 my-repo 🌿 main │ 🤖 Opus 4
🟢 captured │ ▓▓▓▓▓▓░░░░ 62% │ +47 -12 │ 📝 3 │ ⏱ 14m
```

Row 1: Brain branding, repo + branch (with worktree detection), model name
Row 2: Brain state, context bar (color-coded), lines changed, dirty files, session duration

## Commands

### Onboarding & Identity

| Command | What It Does |
|---------|-------------|
| `/brain-onboard` | Guided first-time walkthrough — identity → discover content → process inbox → catalog projects (`--quick` for identity only) |
| `/brain-intake` | Guided conversational interview — teach the brain who you are; populates `IDENTITY.md` |
| `/brain-discover [path]` | Scan a drive for existing writing/scripts/lyrics/audio not yet in the brain |
| `/brain-inbox` | Process loose files dropped into the vault and route them to their homes |
| `/brain-scan [path]` | Catalog a project directory into `projects/` + index |
| `/brain-update [name]` | Refresh an existing project's brain entry after more work |

### Knowledge Management

| Command | What It Does |
|---------|-------------|
| `/brain-capture` | Extract patterns, prompts, and lessons from the current conversation |
| `/brain-graduate` | Promote learnings with reliability scoring (high/medium/experimental); `--auto` mode passively extracts learnings from completed work |
| `/daily-note` | Log a journal entry to `daily_notes/` |

### Quality & Safety

| Command | What It Does |
|---------|-------------|
| `/pre-pr-scan` | Multi-agent quality gate — CI compliance, security, logic bugs, commit hygiene |
| `/brain-audit` | Vault health check — stale entries, missing indexes, broken links |
| `/brain-investigate` | Structured debugging with 3-level diagnostic (EXISTS → SUBSTANTIVE → WIRED) |

### Session & Ops

| Command | What It Does |
|---------|-------------|
| `/session-guardian` | Check session health — context usage, read/write ratio, risk assessment |
| `/daily-sync` | Fast operational snapshot — vault health, git state, drift detection, priorities |
| `/brain-handoff` | Session continuity document — accomplished, in-progress, blockers, decisions |
| `/brain-evolve` | Self-improvement cycle — 3 auditor agents, 5-axis scoring, inline proposal review |

### Workflow

| Command | What It Does |
|---------|-------------|
| `/brain-ship` | Ship completed work — push branch, create PR, update Linear, log to vault |
| `/brain-ticket` | Create work tickets in Linear from backlog |
| `/brain-linear-sync` | Sync Linear tickets with brain vault |
| `/brain-add-pattern` | Add an error pattern and solution to the pattern store |
| `/brain-setup` | First-time onboarding wizard |
| `/brain-relocate` | Move your vault to a new path |

### Play

| Command | What It Does |
|---------|-------------|
| `/brain-game` | Game night — AI Fluency games (riddles, crosswords, RPG) and resumable quest campaigns |

## Vault Structure

Your vault lives at `$BRAIN_PATH` — wherever you choose during setup:

```
$BRAIN_PATH/
  learnings/             # Graduated knowledge with reliability scores
  prompts/               # Prompt and pattern library
  projects/              # Project summaries by category
  investigations/        # Structured debugging investigations
  handoffs/              # Session continuity documents
  daily_notes/           # Daily journal entries
  evolution/             # Self-improvement proposals and synthesis
    proposals/           # EVO-*.md scored proposals
    synthesis/           # SYNTH-*.md cycle summaries
  brain-mode/
    pattern-store.json   # Error patterns and solutions
  .brain-state           # Current hook state (idle/captured/error)
  .brain-session-metrics.json  # Session guardian tracking
  .brain-cached-context.json   # Cached context for fast /clear
  .brain-errors.log      # Hook error log
```

The vault is Obsidian-compatible but doesn't require Obsidian.

## Configuration

Brain mode needs one environment variable:

```bash
export BRAIN_PATH="/path/to/your/vault"
```

This is set in two places (both are needed):
1. **Shell profile** (`~/.bashrc`, `~/.zshrc`, or `~/.bash_profile`) — for interactive terminal use
2. **`~/.claude/settings.json`** under `"env"` — for hook subprocesses (which don't load shell profiles)

The `/brain-setup` wizard handles both.

## Project Structure

```
claude-brain-toolkit/
  agents/
    brain-mode.md               # Agent definition
  hooks/
    session-start.sh            # SessionStart — vault context loading
    pre-compact.sh              # PreCompact — capture suggestion
    post-tool-use.sh            # PostToolUse — git commit detection
    post-tool-use-failure.sh    # PostToolUseFailure — error patterns
    notification-idle.sh        # Notification — idle capture offer
    session-guardian.sh         # PostToolUse — context & focus monitoring
    risk-classifier.sh          # PreToolUse — dangerous command blocking
    pre-commit-secrets.sh       # PreToolUse — secret leak prevention
    loop-detector.sh            # PreToolUse — repeated call detection
    stop.sh                     # Stop — mechanical session capture + GSD ingestion (deployed globally)
    lib/
      brain-path.sh             # Shared utilities
      brain-context.sh          # Vault context builder
  global-skills/
    brain-onboard/              # Guided first-time onboarding walkthrough
    brain-intake/               # Identity interview -> IDENTITY.md
    brain-discover/             # Drive scan for existing creative content
    brain-inbox/                # Process & route loose vault files
    brain-scan/                 # Catalog a project into the brain
    brain-update/               # Refresh an existing project entry
    brain-capture/              # Pattern extraction
    brain-graduate/             # Knowledge graduation (manual + --auto passive extraction)
    brain-investigate/          # Structured debugging
    brain-audit/                # Vault health check
    brain-evolve/               # Self-improvement cycle
    brain-handoff/              # Session continuity
    brain-ship/                 # PR shipping + Linear
    brain-ticket/               # Linear ticket creation
    brain-linear-sync/          # Linear sync
    session-guardian/            # Context & focus protection
    daily-sync/                 # Operational snapshot
    pre-pr-scan/                # Multi-agent quality gate
    brain-game/                 # Game night + quest campaigns
    daily-note/                 # Journal entries
  commands/
    brain-add-pattern.md        # Error pattern management
    brain-relocate.md           # Vault relocation
  onboarding-kit/
    setup.sh                    # Automated installer
    skills/                     # Onboarding-only skills
  settings.json                 # Template settings
  statusline.sh                 # Two-row branded statusline
  frameworks/                   # AI Fluency Framework reference
```

## Developing

If you're working on the toolkit itself:

1. Clone the repo
2. Create a `CLAUDE.local.md` (gitignored) with your real `BRAIN_PATH`
3. Run `bash onboarding-kit/setup.sh` after changes to deploy to `~/.claude/`

Changes to hook scripts in the repo don't take effect until deployed — the running hooks are the copies in `~/.claude/hooks/`.

## License

MIT. See [LICENSE](LICENSE).

AI Fluency Framework content adapted from Dakan & Feller (CC BY-NC-ND 4.0). See [frameworks/ai-fluency-framework.md](frameworks/ai-fluency-framework.md) for full attribution.
