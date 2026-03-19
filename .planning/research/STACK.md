# Stack Research

**Domain:** Claude Code CLI extension — brain mode with hooks, skills, statusline, and persistent local knowledge
**Researched:** 2026-03-19
**Confidence:** HIGH (sourced from official Claude Code documentation, verified against live CLI v2.1.79)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Claude Code Skills (`SKILL.md`) | v2.1.79+ (current) | Define brain-mode command, brain-capture, brain-audit, daily-note, brain-intake, brain-inbox, brain-scan | The canonical extension point for user-invocable and Claude-invocable commands. Skills are the successor to `.claude/commands/`; they support supporting files, frontmatter control over invocation mode, and context injection. All existing brain toolkit skills are already in this format. |
| Claude Code Hooks (settings.json) | v2.1.79+ (current) | Session lifecycle automation — SessionStart context injection, PreCompact auto-capture, Stop milestone save, PostToolUseFailure error detection | The only mechanism in Claude Code for automatic, event-driven behavior. Hooks fire shell commands or HTTP endpoints at specific lifecycle points without any user invocation. This is how brain mode becomes autonomous rather than passive. |
| Claude Code StatusLine (settings.json) | v2.1.79+ (current) | Persistent statusbar with brain emoji, color states, context %, session cost | Native Claude Code feature. Shell script receives JSON on stdin after every assistant message and prints to the status bar. No third-party terminal integration required — works in any terminal that runs Claude Code. |
| Claude Code Subagents (`agents/AGENT.md`) | v2.1.79+ (current) | `brain-mode` as a launchable agent via `claude --agent brain-mode` | Subagents replace the concept of a custom `--brain` launch mode. An agent file at `~/.claude/agents/brain-mode.md` gives the session a custom system prompt, preloaded skills, and lifecycle hooks. The `--agent` flag activates it. This is the correct way to implement a dedicated "mode." |
| Bash (POSIX sh) | System shell (bash 3.2+) | All hook scripts and the statusline script | Shell scripts are the execution layer for hooks and statusline. They receive JSON on stdin, write to the vault, and exit with structured JSON output. Bash is the universal language here — available on macOS, Linux, and Windows (via Git Bash, which is how Claude Code runs on Windows). No Node.js or Python required for hooks unless preferred. |
| `jq` (JSON processor) | 1.6+ | Parse Claude Code's JSON event payloads in hook scripts and statusline | Claude Code pipes JSON to every hook and statusline script. `jq` is the standard tool for extracting fields from that JSON in shell scripts. The official Claude Code docs use `jq` in all their Bash examples. It is not bundled with Claude Code — must be installed by the user. |
| BRAIN_PATH environment variable | N/A (env var convention) | Cross-directory vault reference for all hooks and skills | The vault lives at an arbitrary path the user controls. Every hook subprocess, statusline script, and skill needs to find it. Setting `BRAIN_PATH` in the user's shell profile and referencing it in scripts is the only reliable cross-directory mechanism. Claude Code's `settings.json` `env` block can also inject it into every session. |

### Supporting Libraries / Tools

| Library/Tool | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `jq` | 1.6+ | Parse JSON in shell hooks; required for extracting `transcript_path`, `session_id`, `tool_input`, and error details from hook event JSON | Always — every hook script that reads Claude Code event data needs it |
| Python 3 (standard library only) | 3.8+ | Alternative statusline implementation; preferred when statusline logic becomes complex (multi-line, color thresholds, caching) | When the statusline grows beyond 30 lines of Bash. Official docs provide Python examples alongside Bash. No `pip install` needed — only `json`, `sys`, `subprocess`, `os` from stdlib. |
| `stat` (coreutils) | System | File modification time for cache invalidation in statusline script | Any time the statusline needs to cache a slow disk read (e.g., reading `pattern-store.json`). Use `-f %m` on macOS, `-c %Y` on Linux — handle both. |
| `mktemp` + `mv` (atomic write) | System | Atomic write pattern for `pattern-store.json` to prevent corruption | Every hook that writes to `pattern-store.json` must use this pattern: write to a temp file, then `mv` to the final path. `mv` is atomic on the same filesystem. |

### Configuration Files

| File | Location | Purpose | Notes |
|------|----------|---------|-------|
| `~/.claude/settings.json` | User scope | Declare hooks, statusLine config, BRAIN_PATH env injection | User-scope so settings apply to all projects. Project scope (`.claude/settings.json`) is for team-shareable config only — brain mode is personal. |
| `~/.claude/agents/brain-mode.md` | User scope | Define the brain-mode subagent: system prompt, preloaded skills, hooks, memory | Activated via `claude --agent brain-mode`. Body becomes the system prompt. `skills` frontmatter field preloads existing brain-* skills into context at startup. |
| `~/.claude/skills/brain-mode/SKILL.md` | User scope | User-invocable `/brain-mode` command for one-off activation within a regular session | Complement to the `--agent` launch path. Set `disable-model-invocation: true` so Claude does not trigger this autonomously. |
| `~/.claude/statusline.sh` | User-level file | Statusline script reading session JSON and rendering brain emoji + color state | Referenced from `statusLine.command` in `settings.json`. Keep under 50 lines of Bash; cache slow reads to `/tmp`. |
| `~/.claude/hooks/` | User-level directory | All hook shell scripts (`session-start.sh`, `pre-compact.sh`, `stop.sh`, `error-detect.sh`) | Organized by event. Shared code in `hooks/lib/`. |
| `$BRAIN_PATH/brain-mode/pattern-store.json` | Vault (user-controlled) | Adaptive mentoring state: encounter counts by pattern type, current mentoring level | Lives in the vault so it persists across machines if vault is synced. JSON not SQLite because shell scripts need to read/write without dependencies. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `claude --debug` | See hook execution details during development: which hooks matched, exit codes, stdout/stderr | Run with `--debug` flag. Shows hook status for every event. Essential for debugging hook scripts that silently fail. |
| `echo '{"model":{"display_name":"Opus"},...}' \| ./statusline.sh` | Test statusline script locally without launching a full session | Use mock JSON matching the full schema from the official docs. Test color states, null handling, and caching logic in isolation. |
| `chmod +x` | Make hook and statusline scripts executable | Required before Claude Code can run them. Scripts that are not executable fail silently — statusline goes blank, hooks do nothing. |
| `/hooks` (built-in command) | Browse configured hooks in read-only view from within a Claude Code session | Quick sanity check that hooks are registered. Does not show execution results — use `--debug` for that. |
| `/statusline <description>` (built-in command) | Generate a statusline script via Claude Code's built-in statusline agent | Useful for rapid prototyping. The agent writes the script and updates `settings.json` automatically. Override with manual edits afterward. |
| `jq` (command line) | Test JSON parsing expressions interactively before embedding in hook scripts | Run `echo '<json>' \| jq '.field'` to verify extraction before writing the script. |

---

## Installation

```bash
# 1. Install jq (required for hook scripts that parse Claude Code event JSON)
# macOS:
brew install jq
# Ubuntu/Debian:
sudo apt-get install jq
# Windows (via scoop, inside Git Bash):
scoop install jq

# 2. Create the hook scripts directory
mkdir -p ~/.claude/hooks/lib

# 3. Create the brain mode agent
mkdir -p ~/.claude/agents

# 4. Set BRAIN_PATH in your shell profile (one-time setup)
echo 'export BRAIN_PATH="/path/to/your/vault"' >> ~/.zshrc
# or ~/.bashrc for bash users

# 5. Inject BRAIN_PATH into Claude Code sessions via settings.json
# Add to ~/.claude/settings.json:
# {
#   "env": { "BRAIN_PATH": "/path/to/your/vault" },
#   "statusLine": { "type": "command", "command": "~/.claude/statusline.sh" },
#   "hooks": { ... }
# }

# No npm install needed — no Node.js packages are required for this stack.
# Claude Code itself is already installed as the user has v2.1.79.
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Bash hook scripts | Node.js hook scripts | Node.js is justified when hook logic exceeds ~100 lines, requires HTTP requests (prefer `type: "http"` hooks instead), or needs complex JSON transformation that `jq` makes ugly. Not needed for this project — vault I/O and JSON parsing are both well-handled by Bash + jq. |
| Bash hook scripts | Python hook scripts | Python is the right choice if the hook needs complex data manipulation (e.g., NLP-based pattern classification). For brain mode's needs (read JSON, check thresholds, write a file), Bash is sufficient and has zero startup overhead vs Python. |
| `claude --agent brain-mode` | Custom `claude --brain` alias | There is no `--brain` flag in Claude Code. A shell alias `alias claude-brain='claude --agent brain-mode'` achieves the same UX. The `--agent` mechanism is the supported extension point for custom launch modes. |
| `type: "command"` hooks (shell scripts) | `type: "http"` hooks | HTTP hooks are better when the hook logic is complex, stateful, or needs to share state across events via a running server. For brain mode, shell scripts are sufficient and require no running daemon. Use HTTP hooks if a future version adds real-time vault sync to a remote service. |
| `type: "command"` hooks (shell scripts) | `type: "prompt"` hooks | Prompt hooks let Claude evaluate decisions (e.g., "should this tool call be blocked?"). For brain mode's error detection and pattern tracking, deterministic shell logic is more reliable than LLM judgment. Reserve prompt hooks for ambiguous permission decisions. |
| Skills in `~/.claude/skills/` (user scope) | Skills in `.claude/skills/` (project scope) | Use project scope for team-shareable brain skills. The personal brain-mode skills belong at user scope because they reference `BRAIN_PATH` which is personal configuration. |
| Pattern store as JSON file | Pattern store as SQLite | SQLite would be more robust under multi-process writes. However: (1) hook scripts running sequentially per event do not create concurrent writes, (2) shell scripts cannot query SQLite without the `sqlite3` binary, (3) the added complexity is not justified at this scale. Revisit if vault scales to many concurrent writers. |
| Auto memory (`autoMemoryDirectory`) | Custom `pattern-store.json` | Claude Code's built-in auto memory (`~/.claude/projects/.../memory/MEMORY.md`) is not readable by hook scripts or the statusline — it is only injected into Claude's context at session start. For state that must be read by hooks and the statusline script (separate processes), a custom JSON file in `$BRAIN_PATH` is required. Auto memory is still useful for Claude's own cross-session learning separate from the pattern store. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `context: fork` in brain-mode `SKILL.md` | Brain mode must run inline in the main session to inject persistent behavioral context. A forked subagent runs in isolation, finishes, returns a result, and disappears — the injected instructions do not persist in the main conversation. | Run brain-mode skill inline (no `context: fork`). Use `context: fork` only for discrete bounded tasks like brain-capture or brain-audit that produce a result and return. |
| Hardcoded vault paths in scripts | Any hardcoded path (e.g., `~/brain/`, `/Users/srco1/Obsidian/`) breaks on a different machine, different username, or if the user moves their vault. | Always reference `$BRAIN_PATH`. Validate it at script start with a shared `lib/brain-path.sh`. |
| `async: false` (blocking) for expensive hooks | A blocking hook at `SessionStart` that reads many vault files delays the entire session startup. The user sees Claude Code hang before any response. | Mark expensive operations `async: true` so they run in the background without blocking. Only SessionStart context injection needs to be synchronous. |
| Storing mentoring state in Claude's session memory | Session memory (auto memory) resets on `/clear`, is not accessible to hook scripts (separate processes), and is not accessible to the statusline script. | Store pattern counts and mentoring level in `$BRAIN_PATH/brain-mode/pattern-store.json`. This file survives `/clear` and is readable by all components. |
| A single monolithic hook script for all events | One script mapped to multiple events grows complex, cannot be made async for some events but not others, and fails silently if it crashes on one event. | One script per event type. Share reusable logic via sourced library scripts in `hooks/lib/`. |
| `.claude/commands/` format for new skills | The commands format is legacy. Skills (`SKILL.md` in a directory) are the current format and support additional features: supporting files, frontmatter control over model invocation, string substitutions including `${CLAUDE_SKILL_DIR}`. When a skill and command share the same name, the skill wins. | Use `SKILL.md` in `~/.claude/skills/<name>/` for all new commands. Existing brain-toolkit skills already use this format. |
| Bundled Claude Code skills (`/batch`, `/loop`, etc.) as alternatives | These are Anthropic-defined prompt skills, not extension mechanisms. They are not configurable or subclassable. | Use custom `SKILL.md` files to define brain mode behavior. Reference bundled skills in documentation only. |

---

## Stack Patterns by Variant

**If the user has no shell profile configured for `BRAIN_PATH`:**
- Fall back to reading `BRAIN_PATH` from `~/.claude/settings.json` `env` block
- Hook scripts can read it from the environment without shell profile changes
- Onboarding must write the `env.BRAIN_PATH` entry to `settings.json` as part of first-run setup

**If running on Windows:**
- Claude Code runs hook scripts through Git Bash on Windows
- Use forward slashes in script paths within `settings.json`
- `stat` flags differ: macOS uses `-f %m`, Linux/Git Bash uses `-c %Y` — detect OS in `lib/brain-path.sh` and branch accordingly
- `jq` must be installed and accessible from Git Bash; recommend Scoop or manual install to Git Bash's `/usr/local/bin`

**If the vault is an Obsidian vault:**
- No Obsidian API or `obsidian-cli` is required for brain mode's core operation — the vault is just a directory of markdown files
- `obsidian-cli` is optional for features that need Obsidian's page resolution (finding notes by title across the vault). Install only if `/brain-discover` or similar skills need it.
- All hook scripts and statusline use direct file I/O via `$BRAIN_PATH` — Obsidian does not need to be running

**If the pattern-store needs to be shared across machines:**
- Use the vault as the sync mechanism (Obsidian Sync, iCloud, Dropbox, git)
- Add a machine-id prefix to session keys in `pattern-store.json` to avoid conflicting session counts
- `session-log.md` is append-only so sync conflicts are safe; pattern-store may conflict — keep a merge strategy (last-write-wins on `current_level` is acceptable)

---

## Version Compatibility

| Package/Feature | Compatible With | Notes |
|-----------|-----------------|-------|
| Skill `hooks` frontmatter field | Claude Code v2.1+ | Skills can define their own lifecycle hooks. Requires v2.1+ — confirm with `claude --version`. |
| `SessionStart` / `SessionEnd` hook events | Claude Code v2.0+ | Lifecycle hook events. Both available in current v2.1.79. |
| `PreCompact` / `PostCompact` hook events | Claude Code v2.0+ | Fire before/after `/clear` context compaction. Available in current v2.1.79. |
| `PostToolUseFailure` hook event | Claude Code v2.0+ | Fires when a tool call fails. Key event for error detection. Available in current v2.1.79. |
| `statusLine` in `settings.json` | Claude Code v2.0+ | StatusLine configuration. Available in current v2.1.79. `agent.name` field in statusline JSON is available and shows active `--agent` name. |
| `agent` frontmatter field in `settings.json` | Claude Code v2.0+ | Set default agent for a project. Used to activate brain-mode by default in specific directories. |
| `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` env var | Claude Code v2.1+ | Load CLAUDE.md from `--add-dir` directories. Relevant if using `--add-dir $BRAIN_PATH` to inject vault context. |
| `jq` 1.6 | Bash 3.2+ | Compatible. Avoid `jq` 1.5 — `// default` fallback syntax for null fields was less reliable in 1.5. Use `jq 1.6+`. |

---

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — HIGH confidence. Official documentation. All hook event types, configuration JSON schema, input/output formats, exit code behavior, async mode, environment variables (`$CLAUDE_PROJECT_DIR`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`).
- [Claude Code Skills Reference](https://code.claude.com/docs/en/skills) — HIGH confidence. Official documentation. SKILL.md frontmatter fields, string substitutions (`$ARGUMENTS`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}`), `context: fork`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, supporting files pattern.
- [Claude Code StatusLine Reference](https://code.claude.com/docs/en/statusline) — HIGH confidence. Official documentation. Full stdin JSON schema, update trigger conditions (after each assistant message, permission mode change, vim mode toggle), 300ms debounce, ANSI color support, multi-line output, caching pattern for slow operations, Windows configuration.
- [Claude Code Subagents Reference](https://code.claude.com/docs/en/sub-agents) — HIGH confidence. Official documentation. `--agent` flag, agent file frontmatter (`name`, `description`, `tools`, `model`, `skills`, `hooks`, `memory`, `permissionMode`), `~/.claude/agents/` location, `claude --agent <name>` activation.
- [Claude Code Memory Reference](https://code.claude.com/docs/en/memory) — HIGH confidence. Official documentation. CLAUDE.md locations, auto memory (`autoMemoryDirectory`, `autoMemoryEnabled`), `@path` import syntax, `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` env var.
- [Claude Code Settings Reference](https://code.claude.com/docs/en/settings) — HIGH confidence. Official documentation. `settings.json` schema, `env` block for injecting environment variables, `statusLine` field, `hooks` field, scope hierarchy (managed > user > project > local).
- Live Claude Code v2.1.79 — confirmed via `claude --version` on the development machine (Windows 10, 2026-03-19).
- Existing brain toolkit skills (`brain-capture/SKILL.md`, `brain-audit/SKILL.md`) — directly read from codebase. Confirms current skill format, `$ARGUMENTS` usage, `{{SET_YOUR_BRAIN_PATH}}` substitution pattern, and vault I/O conventions.

---
*Stack research for: Claude Brain Mode — Claude Code CLI extension with hooks, skills, statusline, and persistent local knowledge*
*Researched: 2026-03-19*
