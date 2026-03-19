# Architecture Research

**Domain:** Claude Code CLI extension — brain mode with hooks, skills, statusline, and persistent local knowledge
**Researched:** 2026-03-19
**Confidence:** HIGH (sourced from official Claude Code documentation)

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                  Claude Code CLI Session                          │
│                                                                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐   │
│  │  StatusLine  │  │   Hooks     │  │       Skills            │   │
│  │  Script      │  │   Engine    │  │  (brain-* commands)     │   │
│  │ (statusline  │  │             │  │  ~/.claude/skills/      │   │
│  │  .sh/.py)    │  │ settings.   │  │  brain-mode/            │   │
│  └──────┬───────┘  │ json hooks  │  │  brain-capture/         │   │
│         │          └──────┬──────┘  │  brain-audit/           │   │
│         │                 │         │  daily-note/             │   │
│  ┌──────▼───────┐  ┌──────▼──────┐  └───────────┬─────────────┘   │
│  │  Session JSON │  │  Shell      │              │                  │
│  │  stdin feed   │  │  Scripts    │              │                  │
│  │  (per msg)    │  │  (.claude/  │              │                  │
│  └───────────────┘  │  hooks/)    │              │                  │
│                     └─────────────┘              │                  │
└──────────────────────────────────────────────────┼─────────────────┘
                                                   │ BRAIN_PATH env var
                                       ┌───────────▼──────────────────┐
                                       │   Vault / Brain at BRAIN_PATH │
                                       │                               │
                                       │  daily_notes/   prompts/      │
                                       │  projects/      intake/        │
                                       │  pattern-store.json           │
                                       │  (encounter frequency DB)     │
                                       └───────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| StatusLine Script | Render brain emoji + color state, display context %, session cost | Shell or Python script at `~/.claude/statusline.sh`; reads JSON from stdin |
| Hooks Engine | Fire shell scripts at session lifecycle events (SessionStart, Stop, PostToolUse, PreCompact, etc.) | JSON config in `~/.claude/settings.json` `hooks` block; scripts in `~/.claude/hooks/` |
| Brain Mode Skill | Orchestrate brain mode activation — inject vault context, configure session behavior | `~/.claude/skills/brain-mode/SKILL.md` with `disable-model-invocation: true` |
| Capture Hooks | Auto-capture session output to vault before /clear (PreCompact) and on Stop | Shell scripts triggered by `PreCompact` + `Stop` hook events |
| Skill Orchestration Layer | Invoke existing brain-* skills (brain-audit, brain-capture, daily-note) automatically from hooks | Hook scripts that call `/skill-name` via Claude's Skill tool, or shell scripts that write directly to vault |
| Pattern Store | Track encounter frequency for adaptive mentoring; JSON file in vault | `BRAIN_PATH/brain-mode/pattern-store.json`; read/written by hook scripts |
| Vault I/O Layer | Read/write to BRAIN_PATH regardless of project cwd | All shell scripts reference `$BRAIN_PATH` env var; set once in `~/.claude/settings.json` or shell profile |

## Recommended Project Structure

```
~/.claude/
├── settings.json              # hooks config, statusLine config, BRAIN_PATH env
├── statusline.sh              # brain statusline script
│
├── skills/
│   ├── brain-mode/            # Master orchestration skill
│   │   ├── SKILL.md           # Activated via /brain-mode or claude --brain alias
│   │   ├── onboarding.md      # First-run guided setup content
│   │   └── patterns-ref.md    # Adaptive mentoring pattern definitions
│   │
│   ├── brain-capture/         # (existing) prompt pattern extraction
│   │   └── SKILL.md
│   │
│   ├── brain-audit/           # (existing) vault health check
│   │   └── SKILL.md
│   │
│   └── daily-note/            # (existing) journal entry logging
│       └── SKILL.md
│
└── hooks/
    ├── session-start.sh        # Load vault context on session start
    ├── pre-compact.sh          # Auto-capture before /clear compaction
    ├── stop.sh                 # Milestone capture on session stop
    ├── error-detect.sh         # PostToolUseFailure → pattern log
    └── lib/
        ├── brain-path.sh       # Shared: resolve + validate $BRAIN_PATH
        ├── pattern-store.sh    # Read/write encounter frequency
        └── vault-write.sh      # Atomic append to vault files

$BRAIN_PATH/                   # User's vault (cross-directory target)
└── brain-mode/
    ├── pattern-store.json      # Encounter frequency tracking
    ├── session-log.md          # Auto-captured session summaries
    └── onboarding-state.json   # First-run completion flags
```

### Structure Rationale

- **hooks/ with lib/ subdirectory:** Hooks fire frequently; shared helpers (brain-path.sh, vault-write.sh) prevent duplication and ensure consistent `$BRAIN_PATH` resolution across all hook scripts.
- **brain-mode/ skill directory:** This is the "entry point" skill. All session configuration (context injection, mentoring behavior config) lives here so it can be updated without touching hooks.
- **pattern-store.json in vault:** Lives at `$BRAIN_PATH/brain-mode/` so it persists across machines (if vault is synced) and survives Claude Code updates. JSON rather than SQLite because shell scripts can read/write it without dependencies.
- **statusline.sh separate from hooks:** Statusline and hooks are independent subsystems. Statusline reads session JSON from stdin on every message; hooks fire at discrete lifecycle events. They do not share state at runtime — statusline reads pattern-store.json directly from disk if it needs mentoring state color.

## Architectural Patterns

### Pattern 1: Environment Variable as Cross-Directory Bridge

**What:** All vault I/O uses `$BRAIN_PATH` rather than relative paths. The variable is set in the user's shell profile and inherited by every Claude Code session and hook subprocess.

**When to use:** Any time a hook script, statusline script, or skill needs to read from or write to the vault. This is the single mechanism that makes brain mode work cross-directory.

**Trade-offs:** Simple and reliable. Requires user to set `$BRAIN_PATH` once (handled by onboarding). Fails silently if not set — hooks must validate and surface a clear error.

**Example:**
```bash
#!/bin/bash
# lib/brain-path.sh — sourced by all hook scripts
if [ -z "$BRAIN_PATH" ]; then
  echo "BRAIN_PATH not set. Run /brain-mode to complete setup." >&2
  exit 1
fi
if [ ! -d "$BRAIN_PATH" ]; then
  echo "BRAIN_PATH directory not found: $BRAIN_PATH" >&2
  exit 1
fi
```

### Pattern 2: Session JSON Stdin for StatusLine State

**What:** The statusline script receives a JSON blob from Claude Code on every assistant message. The script reads session metadata (context %, cost, model, session_id) and renders the brain emoji + color state. Additional state (mentoring level, vault health) is read from files on disk.

**When to use:** Any information that must appear in the statusline. Color state transitions (green/yellow/red) are driven by combining session JSON data with on-disk pattern-store state.

**Trade-offs:** Statusline runs on every message — keep it fast. Cache slow disk reads (pattern-store.json) to `/tmp/brain-statusline-cache` with a 5-second TTL as the official docs recommend for slow git operations.

**Example:**
```bash
#!/bin/bash
input=$(cat)
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
SESSION_ID=$(echo "$input" | jq -r '.session_id')

# Read mentoring level from disk (cached)
CACHE="/tmp/brain-mode-state-${SESSION_ID}"
if [ ! -f "$CACHE" ] || [ $(($(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0))) -gt 5 ]; then
  MENTOR_LEVEL=$(jq -r '.current_level // "warn"' "$BRAIN_PATH/brain-mode/pattern-store.json" 2>/dev/null || echo "warn")
  echo "$MENTOR_LEVEL" > "$CACHE"
fi
MENTOR_LEVEL=$(cat "$CACHE")

# Color logic
case "$MENTOR_LEVEL" in
  warn)   COLOR='\033[33m' ;;   # yellow — will warn
  silent) COLOR='\033[32m' ;;   # green — silently fixing
  invest) COLOR='\033[31m' ;;   # red — investigating root cause
  *)      COLOR='\033[0m'  ;;
esac
RESET='\033[0m'

echo -e "${COLOR}🧠${RESET} ctx:${PCT}%"
```

### Pattern 3: Hook Scripts as Lifecycle Interceptors

**What:** Shell scripts wired to `SessionStart`, `Stop`, `PreCompact`, and `PostToolUseFailure` events handle automatic vault operations. Each script is self-contained, receives event JSON on stdin, and writes to the vault.

**When to use:** Any behavior that must happen automatically without user invocation — auto-capture before clear, session milestone logging, error pattern tracking.

**Trade-offs:** Hooks run in a subprocess and have no access to Claude's conversation context directly. To capture conversation content, hooks must read `transcript_path` from the event JSON — Claude Code passes the path to the session's `.jsonl` transcript file in every hook invocation.

**Example:**
```bash
#!/bin/bash
# hooks/pre-compact.sh — fires before /clear (PreCompact event)
source ~/.claude/hooks/lib/brain-path.sh

INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)

# Extract last N lines of conversation for capture
SUMMARY=$(tail -c 4096 "$TRANSCRIPT" 2>/dev/null | \
  jq -r 'select(.role=="assistant") | .content[0].text' 2>/dev/null | \
  tail -1)

# Append to session log
cat >> "$BRAIN_PATH/brain-mode/session-log.md" <<EOF

## $DATE $TIME — Pre-clear capture (session $SESSION_ID)

$SUMMARY

---
EOF
exit 0
```

### Pattern 4: Pattern Store as Adaptive Mentoring State Machine

**What:** A JSON file in the vault tracks how many times each error/pattern type has been encountered in the current session and historically. Hook scripts update this store; the statusline and brain-mode skill read it to determine current mentoring level.

**When to use:** Frequency-driven behavior. The adaptive mentoring system (warn once → silent fix → investigate root cause) is state that must persist across messages within a session.

**Trade-offs:** JSON file is simple and shell-scriptable but not atomic under concurrent writes. Since hooks run sequentially per event and Claude Code is single-session, true concurrency is not a concern. Use atomic write pattern (write to temp, mv) to prevent corruption.

**Example:**
```json
{
  "session_id": "abc123",
  "current_level": "warn",
  "patterns": {
    "missing-brain-path": { "count": 0, "first_seen": null },
    "vault-write-error": { "count": 0, "first_seen": null },
    "broken-wiki-link": { "count": 2, "first_seen": "2026-03-19" }
  },
  "thresholds": {
    "warn_to_silent": 2,
    "silent_to_investigate": 5
  }
}
```

## Data Flow

### SessionStart Flow

```
claude starts (any cwd)
    |
    v
SessionStart hook fires
    |
    v
session-start.sh reads $BRAIN_PATH
    |-- validate vault exists
    |-- read pattern-store.json (get mentoring level)
    |-- check first-run flag (onboarding-state.json)
    |-- if first-run: output onboarding prompt to stdout (injected as context)
    |-- else: output vault summary as context (recent daily note, active projects)
    v
Claude sees injected context in session
    |
    v
StatusLine renders brain emoji + color from session JSON + cached disk state
```

### Pre-Clear (Auto-Capture) Flow

```
user types /clear
    |
    v
PreCompact hook fires
    |
    v
pre-compact.sh reads transcript_path from event JSON
    |-- parse recent assistant messages from .jsonl transcript
    |-- format as capture entry
    |-- append to $BRAIN_PATH/brain-mode/session-log.md
    |-- optionally update pattern-store.json if patterns detected
    v
/clear proceeds normally
    |
    v
context window cleared; vault retains captured content
```

### Error Detection / Adaptive Mentoring Flow

```
Claude executes a tool (Bash, Write, Edit, etc.)
    |
    v (if tool fails)
PostToolUseFailure hook fires
    |
    v
error-detect.sh reads tool name + error from event JSON
    |-- classify error type (known pattern?)
    |-- increment count in pattern-store.json (atomic write)
    |-- compare count against thresholds
    |-- if threshold crossed: update current_level in pattern-store.json
    v
StatusLine reads updated pattern-store.json on next message
    |-- color changes reflect new mentoring level
    v
brain-mode skill (already in context) reads level from vault on next invocation
    |-- adjusts behavior: warn / silent-fix / investigate
```

### Cross-Directory Vault Write Flow

```
Hook or skill runs (cwd = any project directory)
    |
    v
Script sources lib/brain-path.sh
    |-- validates $BRAIN_PATH is set and exists
    v
Script constructs absolute path: $BRAIN_PATH/[subpath]/[file].md
    |
    v
Atomic write: write to $BRAIN_PATH/[subpath]/[file].tmp, then mv to final
    |
    v
Vault file updated regardless of current project directory
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single user, 1 vault | Current design — JSON pattern store, shell scripts, single settings.json |
| Power user with large vault | Add vault-size guard to statusline cache; defer brain-audit to explicit invocation only; index the pattern store |
| Multi-machine (shared vault via sync) | pattern-store.json may have write conflicts across machines — add machine-id prefix to session keys; session-log.md append-only so sync conflicts are safe |
| Team (multiple users) | Promote to plugin structure with `${CLAUDE_PLUGIN_DATA}` for per-user state; vault becomes shared read-only reference; pattern-store per user in plugin data dir |

### Scaling Priorities

1. **First bottleneck:** Statusline script latency. Statusline fires on every assistant message. If it runs slow git commands or reads large vault files synchronously, the UI lags. Fix: cache all disk reads with a 5-second TTL in `/tmp`.
2. **Second bottleneck:** Hook script startup time. Shell process spawning adds 20-50ms per hook. Fix: keep hook scripts thin — do minimal work and defer anything non-critical (like brain-audit) to async hooks (`async: true` in hook config).

## Anti-Patterns

### Anti-Pattern 1: Hardcoding Vault Path in Scripts

**What people do:** Write `~/brain/` or `/Users/srco1/brain/` directly in hook scripts and SKILL.md content.

**Why it's wrong:** The vault path varies per user. When the user changes their vault location or a second machine has a different path, every script breaks. The whole system relies on `$BRAIN_PATH` as the single source of truth.

**Do this instead:** Always reference `$BRAIN_PATH` environment variable. Validate it at script start via `lib/brain-path.sh`. Keep `{{SET_YOUR_BRAIN_PATH}}` as the placeholder in SKILL.md content — it gets substituted by the user's CLAUDE.md, not hardcoded.

### Anti-Pattern 2: Using context: fork for Brain Mode Skill

**What people do:** Add `context: fork` to brain-mode/SKILL.md to isolate it in a subagent.

**Why it's wrong:** Brain mode is designed to run inline — it injects persistent context and behavioral guidelines into the main session. Running it in a forked subagent means it operates in isolation with no access to the conversation history or ongoing context. The subagent finishes, returns a result, and the brain mode instructions disappear.

**Do this instead:** Brain mode skill runs inline (no `context: fork`). Skills that do discrete vault operations (brain-capture, brain-audit) can use `context: fork` with an `Explore` agent since they are bounded tasks that read/write files. The orchestrating brain-mode skill stays in main context.

### Anti-Pattern 3: Writing Vault State to Claude's Session Memory Instead of Disk

**What people do:** Ask Claude to "remember" pattern counts or mentoring state within the conversation.

**Why it's wrong:** Session memory is ephemeral. It resets on /clear. It is not accessible to hooks or the statusline script, which are separate processes. State that must survive /clear and be read by multiple components (hooks, statusline, skills) must live in files at `$BRAIN_PATH`.

**Do this instead:** Pattern store, session state, and onboarding flags are JSON files in `$BRAIN_PATH/brain-mode/`. Scripts read and write them directly. Claude's session only loads summaries of this state as injected context at SessionStart.

### Anti-Pattern 4: One Monolithic Hook Script

**What people do:** Create a single hook script that handles all events with if/else branches.

**Why it's wrong:** Claude Code calls hooks by event type. A single script mapped to multiple events grows complex and hard to debug. If it crashes on one event type, it silently breaks others. The `async: true` flag applies per-hook, so a monolithic script cannot be made async for some events but not others.

**Do this instead:** One script per event type (`session-start.sh`, `pre-compact.sh`, `stop.sh`, `error-detect.sh`). Share code via sourced library scripts in `hooks/lib/`. Each script has a single responsibility and can have its own `async`, `timeout`, and `statusMessage` configuration.

### Anti-Pattern 5: Blocking the Session with Slow Hooks

**What people do:** Run brain-audit (which reads every vault file) synchronously in a SessionStart hook.

**Why it's wrong:** SessionStart fires before Claude responds to the user. A slow hook delays the entire session startup. Brain-audit scans potentially hundreds of vault files — this can take seconds.

**Do this instead:** SessionStart hook only does cheap operations: validate `$BRAIN_PATH`, inject brief context (last daily note summary). Mark expensive operations (`async: true`) so they run in background without blocking. Expose brain-audit as a manual `/brain-audit` command the user triggers explicitly.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Obsidian vault (filesystem) | Direct file read/write via `$BRAIN_PATH` | No Obsidian API needed; vault is just a directory of markdown files |
| BRAIN_PATH env var | Set in shell profile, inherited by all Claude Code subprocesses | Must be set before launching Claude; hooks validate its presence |
| Claude Code transcript API | `transcript_path` field in hook event JSON points to `.jsonl` file | Read-only access to conversation history from hooks |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| StatusLine ↔ Pattern Store | Statusline reads `$BRAIN_PATH/brain-mode/pattern-store.json` from disk (cached) | Unidirectional read; statusline never writes to pattern store |
| Hook Scripts ↔ Pattern Store | Hooks read and write `$BRAIN_PATH/brain-mode/pattern-store.json` | Use atomic write (write tmp, mv) to prevent corruption |
| brain-mode Skill ↔ Pattern Store | Skill reads pattern store at invocation time for mentoring level | Claude reads the file via Read tool; skill instructions tell it how to interpret the data |
| Hook Scripts ↔ Vault Files | Append-only writes to `session-log.md`, `daily_notes/` | Never delete or overwrite; always append with timestamp header |
| Hook Scripts ↔ brain-* Skills | Hooks cannot directly invoke skills; skills are invoked by Claude | If a hook needs skill behavior, it writes context to vault and the brain-mode skill picks it up on next user turn |
| Session JSON ↔ StatusLine | Claude Code pipes JSON to statusline script stdin on every message | Read-only for statusline; statusline cannot write back to session state |

## Suggested Build Order

Based on component dependencies, build in this sequence:

1. **Vault I/O Foundation** — `lib/brain-path.sh`, `lib/vault-write.sh`. Everything else depends on these. Validate `$BRAIN_PATH` resolution works cross-directory before building anything else.

2. **StatusLine Script** — `~/.claude/statusline.sh`. The simplest component; only reads session JSON and a cached disk file. Build this early so brain mode has visible feedback from day one. Start with just the brain emoji + context percentage. Color states can come later once pattern-store exists.

3. **Pattern Store Schema** — Define and create `$BRAIN_PATH/brain-mode/pattern-store.json` with initial structure. Block hooks and adaptive mentoring depend on this contract.

4. **SessionStart Hook** — `hooks/session-start.sh` wired to `SessionStart` event. Validates `$BRAIN_PATH`, injects vault context. This is the "brain mode activation" hook that makes every session brain-aware.

5. **PreCompact Hook** — `hooks/pre-compact.sh` wired to `PreCompact` event. Auto-capture before /clear. Depends on vault-write.sh and transcript_path access.

6. **Stop Hook** — `hooks/stop.sh` wired to `Stop` event. Session milestone capture. Similar to pre-compact but fires on session end.

7. **Error Detection Hook** — `hooks/error-detect.sh` wired to `PostToolUseFailure`. Updates pattern-store.json. Enables statusline color changes.

8. **brain-mode Skill** — `skills/brain-mode/SKILL.md`. Now that hooks and pattern store exist, the skill can reference them. Encodes adaptive mentoring behavior as Claude instructions.

9. **Adaptive Mentoring Logic** — Update statusline color states to reflect pattern-store levels. Update brain-mode SKILL.md to encode warn/silent/investigate tiers.

10. **First-Run Onboarding** — `onboarding-state.json` check in SessionStart hook; onboarding content in `skills/brain-mode/onboarding.md`. Build last — depends on all other components being proven stable.

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — HIGH confidence. Official documentation. All hook events, input JSON schema, exit codes, output format.
- [Claude Code Skills Reference](https://code.claude.com/docs/en/skills) — HIGH confidence. Official documentation. SKILL.md frontmatter, context injection, subagent execution, string substitutions including `${CLAUDE_SESSION_ID}`.
- [Claude Code StatusLine Reference](https://code.claude.com/docs/en/statusline) — HIGH confidence. Official documentation. Full JSON schema piped to statusline stdin, update frequency, ANSI color support, caching pattern.
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) — HIGH confidence. Official documentation. Plugin directory structure, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, hook config in plugins.
- Existing brain toolkit skills (brain-capture, brain-audit, daily-note) — directly read from codebase. Established patterns for `$ARGUMENTS`, `{{SET_YOUR_BRAIN_PATH}}` substitution, and vault I/O conventions.

---
*Architecture research for: Claude Brain Mode — Claude Code CLI extension with hooks, skills, statusline, and persistent local knowledge*
*Researched: 2026-03-19*
