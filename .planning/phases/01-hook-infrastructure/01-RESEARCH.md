# Phase 1: Hook Infrastructure - Research

**Researched:** 2026-03-19
**Domain:** Claude Code Hooks API, Shell Scripting, Statusline Configuration
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Error experience
- Contextual explanation style: when BRAIN_PATH is unset, show what it is, why it matters, and the exact fix command — not just a one-liner
- When BRAIN_PATH directory doesn't exist: offer to create it (prompt user), don't auto-create or hard-fail
- Error messages are self-contained — no forward references to commands/features that don't exist yet (e.g., no "run /brain-setup")
- Dual-channel errors: stderr for the human in the terminal, JSON error field for the LLM to read and act on

#### Failure behavior
- Per-hook degradation: Claude decides whether to degrade-with-warning or stop brain mode based on which hook failed and severity
- Stop-loop guard: strict — 1 retry allowed, then immediately kill the hook. Zero tolerance for loops
- Log all hook failures to a persistent file in the vault (BRAIN_PATH/.brain-errors.log) for post-mortem debugging
- Recovery attempts: each hook event re-checks prerequisites — if the problem is fixed mid-session, brain mode recovers automatically

#### Shell output hygiene
- JSON isolation approach: Claude's discretion (delimiter markers, clean subshell, or redirect strategy — pick most robust)
- Self-validate: each hook validates its own JSON output before returning — catches corruption early
- Shell support: bash + zsh (covers macOS default zsh, Linux default bash, Windows Git Bash)
- When shell noise detected: strip silently and extract the JSON — don't bother the user about their shell profile

### Claude's Discretion
- Statusline display design (emoji, text, what info to show)
- JSON isolation implementation approach
- Per-hook degradation vs stop decisions (severity-based)
- Exact error message wording and formatting

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 1 delivers the mechanical foundation that all future brain mode features run on: four lifecycle hook scripts (SessionStart, PreCompact, Stop, PostToolUseFailure), a shared BRAIN_PATH validation library, a stop-loop guard, exit code discipline, and a brain statusline indicator. Everything is verified shell scaffold — no vault reading or writing, no session logic.

The Claude Code hooks API is mature and well-documented. All four required hook events exist, are stable, and work exactly as described in the CONTEXT.md decisions. The critical technical details that make or break this phase are: (1) how the Stop hook loop guard works (`stop_hook_active` field in the JSON payload), (2) the three-exit-code contract (exit 0 = pass, exit 2 = block, anything else = non-blocking), and (3) JSON isolation on stdout. These are fully verified against the official Claude Code docs and the project's prior stack research.

The statusline is a separate mechanism from hooks — it uses its own `statusLine` field in `settings.json`, runs a shell script that reads JSON from stdin, and prints to the status bar. Showing a brain emoji is trivially simple once the script exists. The main challenge is making the statusline detect "brain mode is active" — the cleanest signal available is checking whether `agent.name` equals `"brain-mode"` in the stdin JSON (present only when launched with `--agent brain-mode`).

**Primary recommendation:** Build `~/.claude/hooks/lib/brain-path.sh` as a sourced validation library first — every other hook sources it. All four event hooks are thin wrappers that validate BRAIN_PATH via the library, do their minimal Phase 1 work, then exit cleanly. This keeps the scaffold modular and testable.

---

## Standard Stack

### Core

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| Claude Code Hooks (`settings.json`) | v2.1.79+ | Lifecycle event dispatch to shell scripts | The only mechanism for autonomous, event-driven behavior in Claude Code. No alternative. |
| Bash + zsh | bash 3.2+ / zsh 5.0+ | Hook script execution layer | Claude Code spawns hooks through the user's shell. Scripts must be POSIX-compatible for bash/zsh portability. |
| `jq` | 1.6+ | Parse Claude Code's JSON event payloads in hook scripts | Official docs use `jq` in all Bash examples. Required for reading `stop_hook_active`, `hook_event_name`, `tool_name`, etc. |
| Claude Code StatusLine (`settings.json`) | v2.1.79+ | Brain emoji indicator in status bar | Native CLI feature. Script receives session JSON on stdin, prints plain text (or ANSI) to the status bar. No terminal integration needed. |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `mktemp` + `mv` | System (POSIX) | Atomic writes to `.brain-errors.log` | Whenever hooks append to the log file — prevents corruption on concurrent writes |
| `chmod +x` | System | Make hook scripts executable | Required before Claude Code can run them; failing silently is a real pitfall |
| `claude --debug` | v2.1.79+ | See hook execution, exit codes, stdout/stderr during development | Use during testing of every hook — shows which hooks matched and what they output |
| `/hooks` (built-in) | v2.1.79+ | Verify hooks are loaded in `settings.json` | Quick sanity check inside a running session |

### Alternatives Considered

| Standard | Alternative | Tradeoff |
|----------|-------------|----------|
| Bash hook scripts | Node.js / Python scripts | Both are supported. Bash is simpler for this phase's needs (env var check, JSON output, file append). Switch to Python if hook logic exceeds ~100 lines. |
| `type: "command"` hooks | `type: "prompt"` hooks | Prompt hooks let Claude evaluate decisions. Not appropriate here — BRAIN_PATH validation is deterministic, not judgment-based. |
| Shared lib via `source` | Inline validation in each hook | Inline means inconsistent behavior and diverging logic over time. Single sourced library is the correct pattern. |

**Installation:**

```bash
# Install jq (required)
brew install jq            # macOS
sudo apt-get install jq    # Ubuntu/Debian
scoop install jq           # Windows (Git Bash via Scoop)

# Create hook directories
mkdir -p ~/.claude/hooks/lib

# Make all hook scripts executable (required — silent failure otherwise)
chmod +x ~/.claude/hooks/*.sh ~/.claude/hooks/lib/*.sh
```

---

## Architecture Patterns

### Recommended Project Structure

```
~/.claude/
├── settings.json                    # Hooks + statusLine declarations
├── statusline.sh                    # Brain emoji statusline script
└── hooks/
    ├── lib/
    │   └── brain-path.sh            # Sourced validation library (BRAIN_PATH guard)
    ├── session-start.sh             # SessionStart event handler
    ├── pre-compact.sh               # PreCompact event handler
    ├── stop.sh                      # Stop event handler (with loop guard)
    └── post-tool-use-failure.sh     # PostToolUseFailure event handler
```

All hooks live at user scope (`~/.claude/`), not project scope. Brain mode is personal configuration; project scope is for team-shareable settings only.

### Pattern 1: BRAIN_PATH Validation Library (sourced)

**What:** A single `brain-path.sh` library that all hooks source at the top. It validates BRAIN_PATH exists and is set, emits dual-channel errors (stderr + JSON), and sets a `BRAIN_VALID` flag. If invalid, it exits with the appropriate code so the caller hook returns cleanly.

**When to use:** Every hook sources this library before doing anything else.

```bash
# Source: verified against official docs JSON output format
# ~/.claude/hooks/lib/brain-path.sh

brain_path_validate() {
  # Check: is BRAIN_PATH set?
  if [ -z "$BRAIN_PATH" ]; then
    cat >&2 <<'EOF'
Brain mode requires BRAIN_PATH.

BRAIN_PATH tells brain mode where your knowledge vault lives. Without it,
brain mode cannot read or write any vault data.

To fix, add this to your shell profile (~/.zshrc or ~/.bashrc):
  export BRAIN_PATH="/path/to/your/vault"

Then restart your terminal and relaunch Claude Code.
EOF
    # JSON error for Claude to read
    printf '{"error":"BRAIN_PATH is not set. Brain mode cannot function without a vault path.","degraded":true}\n'
    return 1
  fi

  # Check: does the directory exist?
  if [ ! -d "$BRAIN_PATH" ]; then
    cat >&2 <<EOF
Brain mode cannot find your vault at: $BRAIN_PATH

The directory does not exist. Would you like to create it?
  mkdir -p "$BRAIN_PATH"

If your vault has moved, update BRAIN_PATH in your shell profile.
EOF
    printf '{"error":"BRAIN_PATH directory does not exist: '"$BRAIN_PATH"'","degraded":true}\n'
    return 1
  fi

  return 0
}

brain_log_error() {
  local event="$1" message="$2"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  # Append to persistent error log — only if BRAIN_PATH is valid
  if [ -d "$BRAIN_PATH" ]; then
    printf '[%s] %s: %s\n' "$timestamp" "$event" "$message" >> "$BRAIN_PATH/.brain-errors.log"
  fi
}
```

### Pattern 2: Stop Hook with Loop Guard

**What:** The Stop hook is the only hook that can re-trigger itself (by blocking with exit 2). The `stop_hook_active` field in the JSON payload is `true` when Claude was already blocked once by a Stop hook this turn. Check it first and exit 0 immediately if true.

**When to use:** Any Stop hook that might use exit 2 to block Claude from stopping. Always.

```bash
# Source: official Claude Code hooks docs (stop_hook_active field)
# ~/.claude/hooks/stop.sh
#!/usr/bin/env bash

HOOK_INPUT=$(cat)  # Read once, reuse

# CRITICAL: Loop guard — check before anything else
STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # Already ran once — let Claude stop this time. No logging, no output.
  exit 0
fi

source ~/.claude/hooks/lib/brain-path.sh

# Validate BRAIN_PATH
if ! brain_path_validate; then
  # Brain path invalid — degrade gracefully, don't block stop
  brain_log_error "Stop" "BRAIN_PATH invalid, skipped stop-hook logic"
  exit 0
fi

# Phase 1: scaffold only — no session logic yet
# Future phases add vault capture here
exit 0
```

### Pattern 3: JSON Output Self-Validation

**What:** After constructing the JSON output string, validate it with `jq` before writing to stdout. If `jq` cannot parse it, write an error to stderr and exit cleanly (exit 0) so the hook does not corrupt Claude's parsing.

**When to use:** Any hook that produces structured JSON output for Claude.

```bash
# JSON isolation: write to a variable, validate, then echo
emit_json() {
  local json="$1"
  if printf '%s' "$json" | jq empty >/dev/null 2>&1; then
    printf '%s\n' "$json"
  else
    echo "Hook produced invalid JSON — skipping structured output" >&2
    brain_log_error "JSONValidation" "Invalid JSON would have been: $json"
    # Exit 0 so we don't break the session — just lose the structured output
    exit 0
  fi
}
```

### Pattern 4: JSON Isolation via Clean Subshell

**What:** Run the JSON-producing portion of the hook in a clean subshell with stderr redirected, capturing only stdout. This prevents any stray output (from sourced libs, shell profile leakage, etc.) from contaminating the JSON stream.

**When to use:** The exit-critical JSON output section of any hook.

```bash
# Isolate JSON output: all noise goes to stderr, only JSON to stdout
json_output=$(
  # Redirect any unexpected output to stderr inside the subshell
  exec 2>&1
  # ... produce JSON here ...
  printf '{"decision":"block","reason":"No vault found"}\n'
) 2>/dev/null

# Validate before emitting
emit_json "$json_output"
```

**Rationale for this approach (Claude's discretion):** The redirect strategy is the most robust of the three options. Delimiter markers require the parser to strip them (adding complexity). A clean subshell still sources the same shell profile. Redirect strategy is simple, battle-tested, and requires no output parsing — only the explicitly constructed JSON reaches stdout.

### Pattern 5: Hook Registration in settings.json

**What:** The four lifecycle hooks are registered under their respective event names. All use `type: "command"`. No matchers needed for SessionStart, Stop, or PreCompact (they fire unconditionally). PostToolUseFailure uses no matcher at Phase 1 — it catches all tool failures for logging.

```json
// Source: official Claude Code hooks docs configuration format
// ~/.claude/settings.json (user scope)
{
  "env": {
    "BRAIN_PATH": "/path/to/your/vault"
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/session-start.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/pre-compact.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/stop.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/post-tool-use-failure.sh",
            "timeout": 10,
            "async": true
          }
        ]
      }
    ]
  }
}
```

Note: `PostToolUseFailure` is marked `async: true` — it cannot block (the tool already failed), and making it async means failure logging never slows the session.

### Pattern 6: Statusline Brain Indicator

**What:** A statusline script that shows a brain indicator when brain mode is active. The `agent.name` field in the stdin JSON is `"brain-mode"` when launched with `--agent brain-mode`. If absent, regular session.

**When to use:** Always — it is the Phase 1 statusline for STAT-01.

```bash
# Source: official Claude Code statusline docs — agent.name field
# ~/.claude/statusline.sh
#!/usr/bin/env bash
input=$(cat)

MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
AGENT=$(printf '%s' "$input" | jq -r '.agent.name // ""')
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

if [ "$AGENT" = "brain-mode" ]; then
  # Brain mode active — show indicator left of model name
  printf '\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
else
  printf '[%s] %s%%\n' "$MODEL" "$PCT"
fi
```

The brain emoji (U+1F9E0) is printed as a UTF-8 byte sequence via `printf` for maximum shell compatibility across bash/zsh. The `\360\237\247\240` sequence is the octal encoding of the brain emoji.

**Statusline display design recommendation (Claude's discretion):** Show brain emoji + model name + context %. Simple, not overloaded. The brain emoji is the signal; the rest is baseline useful info. Color can be added in Phase 3 when v2 requirements (STAT-02) land.

### Anti-Patterns to Avoid

- **Single monolithic hook script for all events:** Cannot be made async per-event, fails silently across all events if one case crashes, grows unmanageable. One script per event.
- **`exit 1` to block:** Exit 1 is non-blocking in Claude Code. Only `exit 2` blocks. Exit 1 gives the illusion of a guard while the operation proceeds.
- **JSON mixed with debug output on stdout:** Any non-JSON output on stdout before or after the JSON payload breaks parsing silently. All debug output goes to `>&2`.
- **Hardcoded vault paths:** Always use `$BRAIN_PATH`. Hardcoded paths break on different machines, usernames, and vault moves.
- **Stop hook without loop guard:** Without checking `stop_hook_active`, a Stop hook that uses exit 2 will loop indefinitely. This is the worst failure mode.
- **Not making scripts executable:** Hook scripts that are not `chmod +x` fail silently — the hook appears registered but never runs.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON parsing in hooks | `grep`/`sed`-based field extraction | `jq 1.6+` | Edge cases around null fields, nested objects, and special characters are handled by `jq`'s `// default` fallback syntax. The official docs explicitly use `jq` in all examples. |
| Stop-loop detection | Custom retry counter | Built-in `stop_hook_active` field | Claude Code already tracks this in the hook JSON payload. Reading the field is one `jq` expression. |
| Hook event routing | A dispatcher script | One script per event, registered separately | Claude Code already routes events by event name in `settings.json`. There is no need for a dispatcher. |
| Statusline session data | Custom session tracking | stdin JSON from Claude Code | Claude Code sends model, context %, cost, agent name, etc. already. No custom tracking needed. |
| Exit code abstraction | A wrapper function | Direct `exit 0` / `exit 2` | The three-code contract is simple and direct. An abstraction adds indirection without value. |

**Key insight:** Claude Code's hook system already handles routing, event payloads, loop detection, and exit code semantics. The job is to write thin, correct shell scripts that use these mechanisms — not to rebuild them.

---

## Common Pitfalls

### Pitfall 1: Stop Hook Infinite Loop
**What goes wrong:** A Stop hook uses `exit 2` to block Claude. Claude tries to stop again. The hook fires again. Loop continues indefinitely, consuming tokens and hanging the terminal.
**Why it happens:** The hook blocks every stop attempt, including the ones it triggered itself.
**How to avoid:** Check `stop_hook_active` in the JSON payload first. If `true`, `exit 0` immediately — Claude already tried to stop once and was blocked, your logic already ran.
**Warning signs:** Session hangs after `/exit`, token counter climbs without user input, Claude generates work unprompted.

### Pitfall 2: Exit Code Confusion (exit 1 vs exit 2)
**What goes wrong:** A hook intended to block uses `exit 1`. Claude Code treats it as non-blocking — the operation proceeds as if the hook passed. The "guard" is decorative.
**Why it happens:** `exit 1` is the Unix convention for error. Claude Code's contract is non-standard: only `exit 2` blocks.
**How to avoid:** Memorize the contract: `exit 0` = pass, `exit 2` = block, anything else = non-blocking error. Never mix `exit 2` with JSON output — JSON is ignored when exit code is 2. Use `stderr` for the user-facing block message.
**Warning signs:** Hook runs (visible in `--debug`) but the operation it should block still executes.

### Pitfall 3: Shell Profile Output Corrupts JSON
**What goes wrong:** Hook produces: `Welcome to bash!\n{"decision":"block"}` — Claude Code cannot parse this as JSON. The structured decision is silently ignored.
**Why it happens:** Claude Code spawns a shell that sources `~/.zshrc` / `~/.bashrc`. Profiles with unconditional `echo` statements inject text before the hook's JSON output.
**How to avoid:** Use the redirect isolation pattern — the JSON-producing section redirects all unexpected output to `/dev/null` or stderr. Self-validate with `jq empty` before emitting. Verify in `--debug` that hook output starts with `{`.
**Warning signs:** Hook decisions (block/allow) are ignored; `claude --verbose` shows non-JSON text before JSON in hook output.

### Pitfall 4: Scripts Not Executable
**What goes wrong:** Hook or statusline script is created but not `chmod +x`. Claude Code silently skips non-executable scripts — the hook appears registered but never runs.
**Why it happens:** File creation does not set executable bit by default.
**How to avoid:** Always `chmod +x` every new script immediately after creating it. Verify with `ls -la ~/.claude/hooks/`.
**Warning signs:** Hooks appear in `/hooks` view but have no effect; statusline shows `--` or goes blank.

### Pitfall 5: Missing jq Fallback for Null Fields
**What goes wrong:** `jq -r '.stop_hook_active'` returns `null` (string) instead of `false` when the field is absent. Shell comparison `[ "$VAR" = "true" ]` passes correctly, but `[ "$VAR" = "false" ]` fails — the null string is neither true nor false.
**Why it happens:** Fields like `stop_hook_active` may be absent from the JSON payload in some hook invocations. `jq` returns the string `"null"` for absent fields without a default.
**How to avoid:** Always use `jq -r '.field // false'` or `jq -r '.field // "default"'` for any field that may be absent. Test against a minimal JSON payload without the field.
**Warning signs:** Loop guard condition passes when it should catch; inconsistent hook behavior between first and subsequent calls.

### Pitfall 6: BRAIN_PATH Not Available to Hook Subprocess
**What goes wrong:** `BRAIN_PATH` is set in the user's `.zshrc` but hooks run as non-interactive subshells and do not source `.zshrc`. The env var is empty in every hook.
**Why it happens:** Hook subshells are not interactive shells — they do not source `.zshrc`/`.bashrc` by default on all systems.
**How to avoid:** Inject `BRAIN_PATH` via the `env` block in `~/.claude/settings.json`. This guarantees the variable is available to every hook subprocess regardless of shell configuration. Keep `.zshrc` export as a fallback for the user's own shell sessions.
**Warning signs:** `echo $BRAIN_PATH` in a hook returns empty; validation fires on every hook invocation even after BRAIN_PATH is set in the shell profile.

### Pitfall 7: PostToolUseFailure Cannot Block
**What goes wrong:** A PostToolUseFailure hook uses `exit 2` expecting to block the failed tool's result from reaching Claude. This is not how this event works — the tool already failed, exit 2 only shows stderr as context.
**Why it happens:** The exit 2 mental model carries over from PreToolUse hooks where it does block.
**How to avoid:** PostToolUseFailure is for logging and context enrichment only. To block a tool, use PreToolUse. Use PostToolUseFailure to append `additionalContext` to Claude's understanding of what went wrong. Mark this hook `async: true` since it cannot block anyway.

---

## Code Examples

Verified patterns from official sources:

### Stop Hook Input JSON (official schema)
```bash
# Source: code.claude.com/docs/en/hooks — Stop event JSON input
# Fields available in $HOOK_INPUT for the Stop hook
HOOK_INPUT=$(cat)
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id')
STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
LAST_MESSAGE=$(printf '%s' "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path')
```

### SessionStart Hook Input JSON (official schema)
```bash
# Source: code.claude.com/docs/en/hooks — SessionStart event JSON input
HOOK_INPUT=$(cat)
SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source')  # "startup" | "resume" | "clear" | "compact"
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id')
MODEL=$(printf '%s' "$HOOK_INPUT" | jq -r '.model')
CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd')

# SessionStart: use CLAUDE_ENV_FILE to persist env vars to subsequent Bash calls
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "export BRAIN_PATH=\"$BRAIN_PATH\"" >> "$CLAUDE_ENV_FILE"
fi
```

### PreCompact Hook Input JSON (official schema)
```bash
# Source: code.claude.com/docs/en/hooks — PreCompact event JSON input
HOOK_INPUT=$(cat)
TRIGGER=$(printf '%s' "$HOOK_INPUT" | jq -r '.trigger')  # "manual" | "auto"
SESSION_ID=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id')
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path')
```

### PostToolUseFailure Hook Input JSON (official schema)
```bash
# Source: code.claude.com/docs/en/hooks — PostToolUseFailure event JSON input
HOOK_INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name')       # e.g. "Bash"
ERROR=$(printf '%s' "$HOOK_INPUT" | jq -r '.error')                # error message string
IS_INTERRUPT=$(printf '%s' "$HOOK_INPUT" | jq -r '.is_interrupt')  # true if user interrupted
TOOL_INPUT=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input')      # tool's input object
```

### Statusline: Detect Brain Mode via agent.name
```bash
# Source: code.claude.com/docs/en/statusline — agent.name field in stdin JSON
# agent.name is present only when launched with --agent <name>
AGENT=$(printf '%s' "$input" | jq -r '.agent.name // ""')
if [ "$AGENT" = "brain-mode" ]; then
  BRAIN_INDICATOR="\360\237\247\240 "  # brain emoji (UTF-8 octal)
else
  BRAIN_INDICATOR=""
fi
```

### Atomic Append to Error Log
```bash
# Atomic append using a temp file to prevent partial writes
brain_log_error() {
  local event="$1" message="$2"
  local timestamp log_entry tmp_file
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  log_entry="[$timestamp] $event: $message"
  if [ -d "$BRAIN_PATH" ]; then
    # Append is atomic for single lines on most filesystems
    printf '%s\n' "$log_entry" >> "$BRAIN_PATH/.brain-errors.log"
  fi
}
```

### Testing a Hook Locally
```bash
# Test any hook script with mock JSON — do this before registering in settings.json
echo '{"session_id":"test123","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done.","cwd":"/tmp","permission_mode":"default","transcript_path":"/tmp/test.jsonl"}' \
  | bash ~/.claude/hooks/stop.sh

# Test statusline with mock JSON
echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":25},"agent":{"name":"brain-mode"}}' \
  | bash ~/.claude/statusline.sh

# Verify JSON output is parseable
echo '...' | bash ~/.claude/hooks/stop.sh | jq .
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `.claude/commands/` format | `SKILL.md` in `~/.claude/skills/<name>/` | Claude Code v2.0+ | Skills supersede commands. Support supporting files, frontmatter control, string substitutions. When both exist with same name, skill wins. |
| No lifecycle hooks | Full hooks API (22 event types) | Claude Code v2.0+ | Autonomous event-driven behavior is now first-class in Claude Code. |
| `exit 1` = block (Unix convention) | `exit 2` = block, `exit 1` = non-blocking | Claude Code's non-standard contract | Non-standard but documented. The three-code contract must be internalized. |

**Deprecated / outdated:**
- `.claude/commands/` format: Legacy. Do not create new commands in this format. Existing ones continue to work but skills win on name collision.
- Using `{"continue": true}` in Stop hook output to continue: This triggers another Stop event — effectively a manual loop trigger. Use `exit 2` to block instead.

---

## Open Questions

1. **BRAIN_PATH not set: offer-to-create vs. degrade**
   - What we know: CONTEXT.md says "offer to create it (prompt user)" for non-existent directory. Hooks cannot interactively prompt — they output to stderr and JSON.
   - What's unclear: Can Claude Code hooks trigger an interactive confirmation prompt? Hooks run asynchronously and do not have terminal access for readline-style prompts.
   - Recommendation: The "offer to create" must be mediated by Claude, not the hook. The hook outputs the contextual error message via stderr + JSON error field; Claude reads the JSON, surfaces the offer to the user in the conversation. The hook itself cannot prompt interactively. This is consistent with the dual-channel design — the JSON error field is specifically for Claude to read and act on.

2. **`env` block in settings.json vs. shell profile for BRAIN_PATH**
   - What we know: The `env` block in `settings.json` injects env vars into every Claude Code subprocess, including hooks. Shell profile only injects into interactive shells.
   - What's unclear: Does the `env` block work on Windows Git Bash for hook subprocesses?
   - Recommendation: Use both: `env` block in `settings.json` as the primary (reliable across all platforms), shell profile export as a convenience for the user's own terminal sessions. Document this in the hook library's validation error message.

3. **Statusline: `agent.name` field availability**
   - What we know: Official docs confirm `agent.name` is present in statusline stdin JSON when running with `--agent` flag. It may be absent when not in agent mode.
   - What's unclear: Is it `null` or absent entirely when not in agent mode? The `// ""` fallback handles both cases.
   - Recommendation: Use `jq -r '.agent.name // ""'` with an empty string fallback. If the result is `"brain-mode"`, show the brain indicator; otherwise show nothing. This is safe regardless of field presence.

---

## Sources

### Primary (HIGH confidence)
- `https://code.claude.com/docs/en/hooks` — Complete hooks reference: all 22 event types, configuration format, exit code behavior, JSON input/output schemas, environment variables, stop-loop prevention via `stop_hook_active`, shell profile JSON corruption issue. Fetched 2026-03-19.
- `https://code.claude.com/docs/en/statusline` — Complete statusline reference: full stdin JSON schema, `agent.name` field, update trigger conditions, ANSI support, multi-line output, Windows configuration. Fetched 2026-03-19.
- `.planning/research/STACK.md` — Project's prior stack research (HIGH confidence, sourced from same official docs). Confirms all technology choices, version compatibility table (v2.1.79), and Windows-specific notes.
- `.planning/research/PITFALLS.md` — Project's prior pitfalls research (HIGH confidence). Pitfalls 1-4 directly apply to Phase 1 and are reproduced with additions here.

### Secondary (MEDIUM confidence)
- WebSearch results on statusline community tools (ccstatusline, claude-statusline, ccusage) — verified pattern: statusline receives JSON on stdin, all community tools follow the same schema as official docs.
- WebSearch results on PostToolUseFailure — confirmed it exists and fires on tool failure; input fields verified against official docs fetch.

### Tertiary (LOW confidence)
- None — all critical claims verified against official sources.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all technologies verified against official Claude Code docs (v2.1.79+)
- Architecture patterns: HIGH — hook configuration format, JSON schemas, and exit code contract verified directly from official hooks reference
- Pitfalls: HIGH — all pitfalls verified against official docs (stop_hook_active field existence, exit code behavior, JSON stdout isolation requirement)
- Statusline: HIGH — full schema verified from official statusline reference including agent.name field

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (Claude Code docs are actively updated — re-verify if more than 30 days pass before planning begins)
