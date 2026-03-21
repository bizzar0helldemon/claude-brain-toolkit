# Phase 8: Statusline States - Research

**Researched:** 2026-03-21
**Domain:** Claude Code statusline scripting, bash state file pattern, cross-process communication
**Confidence:** HIGH

---

## Summary

Phase 8 adds three distinct visual states to the statusline: idle (🧠), captured (🟢🧠), and error/degraded (🔴🧠). The core technical challenge is that the statusline script has no direct access to hook outcomes — it receives only the JSON session data Claude Code pipes to it on each refresh. State must be communicated from hooks to the statusline via a shared file written by hooks and read by the statusline script.

The statusline already exists at `~/.claude/statusline.sh` and is registered in `~/.claude/settings.json` via `statusLine.type = "command"`. It currently shows the brain emoji only when `agent.name == "brain-mode"`. Phase 8 extends this script to read a state file at `$BRAIN_PATH/.brain-state` and prepend the appropriate indicator. The state file is written by hooks (stop.sh for capture success, brain_log_error callers for errors) and read on every statusline refresh. No new hook types or Claude Code configuration changes are needed.

The implementation touches three files: `statusline.sh` (reads state file, displays indicator), `stop.sh` (writes captured state on successful block), and `hooks/lib/brain-path.sh` (adds a `write_brain_state` helper). The state file is a single-line text file containing the state name (`idle`, `captured`, `error`) and an optional timestamp, kept simple to avoid jq dependency in the hot path.

**Primary recommendation:** Use a `$BRAIN_PATH/.brain-state` plain text file written atomically by hooks. Statusline reads it on every refresh with a simple `cat` or `read` call. State resets to `idle` at each SessionStart.

---

## Standard Stack

### Core

No new dependencies are needed. All tools are already present in the project.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `bash` | 3.2+ | Statusline script runtime | All existing hooks use bash; Claude Code spawns via Git Bash on Windows |
| `jq` | any | Parse statusline JSON input | Already used throughout all hooks and statusline.sh |
| `printf` | POSIX | Unicode emoji output | Already used in current statusline.sh for brain emoji (octal encoding) |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `date -u` | POSIX | UTC timestamp in state file | Used in brain_log_error already; same pattern for state file |
| `mv` (atomic rename) | POSIX | Write state file without corruption | Same pattern as `update_encounter_count` — write to `.tmp`, then `mv` |

### No Installation Needed

```bash
# No packages to install — all dependencies already present
```

---

## Architecture Patterns

### Recommended File Layout

```
hooks/
├── stop.sh                   # Write "captured" state after decision:block fires
├── session-start.sh          # Write "idle" state on session start (reset)
├── post-tool-use-failure.sh  # Write "error" state on tool failure (degraded)
└── lib/
    └── brain-path.sh         # Add write_brain_state helper function
statusline.sh                 # Read state file, display indicator
```

State file location: `$BRAIN_PATH/.brain-state`

### Pattern 1: State File Communication

**What:** Hooks write a one-line state file; statusline reads it on every refresh.

**Why this works:** The statusline runs in its own process and cannot receive hook output. A file on disk is the only reliable cross-process channel available. The file is written by hooks atomically (temp file + mv) to prevent partial reads.

**State file format:**

```
captured 2026-03-21T14:32:05Z
```

Two tokens: state name and UTC timestamp. State names: `idle`, `captured`, `error`. The timestamp enables future time-gating (e.g., "only show 🟢 if capture was within this session") but is not required for v1.1.

**Writing the state file (hook side):**

```bash
# Source: pattern from update_encounter_count in brain-path.sh — atomic write
write_brain_state() {
  local state="$1"  # idle | captured | error

  # Guard: only write if BRAIN_PATH is valid
  if [ ! -d "${BRAIN_PATH:-}" ]; then
    return 0
  fi

  local state_file="$BRAIN_PATH/.brain-state"
  local tmp_file="${state_file}.tmp.$$"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  printf '%s\n' "$state $timestamp" > "$tmp_file" 2>/dev/null
  mv "$tmp_file" "$state_file" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null

  return 0
}
```

**Reading the state file (statusline side):**

```bash
# Source: statusline.sh — read state, default to idle if file absent or unreadable
BRAIN_STATE="idle"
if [ -n "${BRAIN_PATH:-}" ] && [ -f "$BRAIN_PATH/.brain-state" ]; then
  BRAIN_STATE=$(cut -d' ' -f1 "$BRAIN_PATH/.brain-state" 2>/dev/null || echo "idle")
fi
```

### Pattern 2: Emoji Output (Existing Convention)

The current statusline.sh uses octal escapes for Unicode emoji via `printf`, not raw characters. Phase 8 must follow the same convention for portability on Windows/Git Bash.

```bash
# Verified pattern from current statusline.sh:
printf '\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
# ^--- this is 🧠 (U+1F9E0) encoded as 4-byte UTF-8 octal sequence
```

Emoji octal sequences for the three states:

| State | Emoji | Octal sequence |
|-------|-------|----------------|
| idle (brain only) | 🧠 | `\360\237\247\240` |
| captured | 🟢 + 🧠 | `\360\237\237\242\360\237\247\240` |
| error | 🔴 + 🧠 | `\360\237\224\264\360\237\247\240` |

**Verification method:** `printf '\360\237\237\242' | xxd` should show the UTF-8 bytes for 🟢 (U+1F7E2). Test with `printf '\360\237\237\242\360\237\247\240 [test]\n'` in a terminal.

### Pattern 3: State Transitions

| Event | Hook | State Written | Condition |
|-------|------|--------------|-----------|
| Session starts | session-start.sh | `idle` | Always (reset) |
| Stop hook fires, tool count > 0 | stop.sh | `captured` | After emitting decision:block |
| Stop hook fires, tool count = 0 | stop.sh | `idle` | After silent exit |
| Tool failure logged | post-tool-use-failure.sh | `error` | After brain_log_error |
| BRAIN_PATH invalid | any hook | `error` | After brain_path_validate returns 1 |

**Session start reset is critical.** Without it, a `captured` state from a previous session would persist forever into future idle sessions. The reset ensures each session starts from a known state.

### Pattern 4: BRAIN_PATH Availability in Statusline

The statusline script must read `BRAIN_PATH` from the environment. Unlike hooks (which have env vars injected via settings.json `env` block), the statusline runs in the same environment. Since `settings.json` already has `"env": {"BRAIN_PATH": ""}`, Claude Code injects BRAIN_PATH into the statusline environment — the same mechanism that injects it into hooks.

**Verification:** The existing statusline.sh already works in this environment (it reads `agent.name` from JSON, which works). BRAIN_PATH injection follows the same pattern.

If BRAIN_PATH is empty or the state file doesn't exist, fall back to idle display (existing behavior — just show 🧠 without a colored prefix).

### Anti-Patterns to Avoid

- **Reading transcript_path in statusline to detect hook outcomes:** The transcript shows what Claude said and what tools Claude called. It does NOT contain hook output or whether capture happened. This approach would require JSONL parsing on every statusline refresh (slow) and would not reliably detect hook-level events.
- **Using $$ (PID) in the state file path:** The statusline runs as a new process every refresh. PID-based paths would create a new file each run and never be read by the next invocation. Use a stable, fixed filename.
- **Writing state from within emit_json:** emit_json is a library function in brain-path.sh used by multiple hooks. Side effects in emit_json would write state for every JSON emission, not just capture-relevant ones. Write state explicitly after the decision point.
- **Checking .brain-errors.log for error state:** The log file grows unbounded and contains historical entries. It cannot reliably signal "current session has errors" without timestamp parsing and session correlation logic that isn't worth the complexity.
- **Using jq to parse the state file:** The state file is intentionally plain text (one line, two tokens) so the statusline can read it with a simple `cut -d' ' -f1` without launching jq. The statusline runs frequently (every 300ms debounce) — keep the hot path fast.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic file write | Custom locking mechanism | temp file + `mv` pattern | Already used in `update_encounter_count` — battle-tested in this codebase |
| JSON parsing in statusline | Custom regex/grep JSON parsing | jq (already used in statusline.sh) | jq is already present and used for the main input parsing |
| Unicode emoji in bash | Raw emoji characters in source | Octal escape sequences via printf | Current statusline.sh already uses this — portability on Windows/Git Bash confirmed |
| Cross-process state | Shared memory, pipes, or sockets | Plain text file in BRAIN_PATH | Files work across processes, survive restarts, require no daemon |

**Key insight:** The state file approach is deliberately boring. A one-line text file is readable by humans, debuggable by `cat`, and requires no special tooling. Complexity here would be a liability in a debugging tool.

---

## Common Pitfalls

### Pitfall 1: State File Not Reset Between Sessions

**What goes wrong:** A `captured` state from Session A persists into Session B. The user sees 🟢🧠 at the start of Session B before any capture has happened.

**Why it happens:** The state file survives on disk between sessions. Without an explicit reset, the old state is always read.

**How to avoid:** Write `idle` state in session-start.sh as the first thing after brain_path_validate succeeds.

**Warning signs:** Statusline shows 🟢 immediately on session start before any work is done.

### Pitfall 2: BRAIN_PATH Not Set When Statusline Runs

**What goes wrong:** Statusline tries to read `$BRAIN_PATH/.brain-state` but BRAIN_PATH is empty string. `cat "" /.brain-state` fails silently or errors.

**Why it happens:** BRAIN_PATH may not be configured (fresh install, misconfiguration). The statusline must not crash in this case.

**How to avoid:** Guard with `[ -n "${BRAIN_PATH:-}" ] && [ -f "$BRAIN_PATH/.brain-state" ]` before reading. Default to `idle` if file is absent.

**Warning signs:** Statusline goes blank or shows error output.

### Pitfall 3: State Written Before Decision, Not After

**What goes wrong:** stop.sh writes `captured` state before emitting the `decision:block` JSON. If emit_json fails (rare, but possible), the state file says `captured` but no capture prompt was shown.

**Why it happens:** Ordering the write before the emit seems natural but is incorrect.

**How to avoid:** Write `captured` state AFTER `emit_json "$BLOCK_JSON"` succeeds and the exit 0 path is reached.

**Warning signs:** State shows `captured` but no capture prompt appeared in the session.

### Pitfall 4: Emoji Displays as Question Mark or Box on Windows

**What goes wrong:** The 🟢 or 🔴 emoji renders as `?` or an empty box in the Windows Terminal / Git Bash environment.

**Why it happens:** Terminal emoji support varies. The current statusline uses octal sequences which work in Git Bash. Raw UTF-8 bytes in source files may not survive copy-paste.

**How to avoid:** Use the verified octal sequences from the Pattern 2 table above. Test with `printf '\360\237\237\242\n'` in Git Bash before committing.

**Warning signs:** Statusline shows boxes or question marks instead of colored circles.

### Pitfall 5: State File Write Contention

**What goes wrong:** Two hooks fire simultaneously (e.g., PostToolUseFailure and Stop fire in rapid succession) and both try to write `.brain-state` at the same time.

**Why it happens:** `mv` is atomic at the filesystem level on most OS/filesystem combinations. But two writers using the same `.tmp.$$` name could collide if they have the same PID (unlikely but theoretically possible in rapid succession).

**How to avoid:** Include `$$` (PID) in the temp file name, which is already the pattern in `update_encounter_count`. Since each hook runs in a separate process, PIDs are distinct.

**Warning signs:** Corrupted `.brain-state` file (empty or partial content).

---

## Code Examples

Verified patterns from official sources and existing codebase:

### write_brain_state Helper (brain-path.sh)

```bash
# Source: based on update_encounter_count pattern in brain-path.sh (atomic write via mv)
# Add to brain-path.sh after the existing functions

write_brain_state() {
  local state="$1"  # Expected: idle | captured | error

  if [ ! -d "${BRAIN_PATH:-}" ]; then
    return 0
  fi

  local state_file="$BRAIN_PATH/.brain-state"
  local tmp_file="${state_file}.tmp.$$"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  printf '%s\n' "$state $timestamp" > "$tmp_file" 2>/dev/null
  if ! mv "$tmp_file" "$state_file" 2>/dev/null; then
    rm -f "$tmp_file" 2>/dev/null
    brain_log_error "BrainState" "Failed to write state: $state"
  fi

  return 0
}
```

### stop.sh — Write State After Capture Block

```bash
# Source: existing stop.sh pattern — add write_brain_state calls at decision points

# ... (existing signal detection logic) ...

if [ "$SHOULD_CAPTURE" = "false" ]; then
  write_brain_state "idle"  # ADD: trivial session — reset to idle
  exit 0
fi

brain_log_error "Stop" "Capture trigger fired (tools: $TOOL_COUNT, commits: $HAS_GIT_COMMIT, files: $HAS_FILE_CHANGES)"

REASON="Before ending this session, please run /brain-capture to preserve any useful patterns from this conversation, then run /daily-note to log a session summary. After completing both, briefly confirm what was captured (e.g., 'Brain captured: N learnings, daily note updated') and then you can stop."
BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
write_brain_state "captured"  # ADD: capture block emitted — state is captured
exit 0
```

### session-start.sh — Reset State on Session Start

```bash
# Source: existing session-start.sh — add reset before or after brain_path_validate
# Add this line after brain_path_validate succeeds:

write_brain_state "idle"  # Reset state — new session starts clean
```

### post-tool-use-failure.sh — Write Error State

```bash
# Source: existing post-tool-use-failure.sh — add after brain_log_error call

brain_log_error "ToolFailure:$TOOL_NAME" "$ERROR_MSG"
write_brain_state "error"  # ADD: tool failure detected — signal degraded state
```

### statusline.sh — Read State and Display Indicator

```bash
#!/usr/bin/env bash
# Source: extension of existing statusline.sh pattern
input=$(cat)

MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
AGENT=$(printf '%s' "$input" | jq -r '.agent.name // ""')
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Only show brain states when brain-mode agent is active
if [ "$AGENT" = "brain-mode" ]; then
  # Read brain state from file — default to idle if file absent or BRAIN_PATH unset
  BRAIN_STATE="idle"
  if [ -n "${BRAIN_PATH:-}" ] && [ -f "$BRAIN_PATH/.brain-state" ]; then
    BRAIN_STATE=$(cut -d' ' -f1 "$BRAIN_PATH/.brain-state" 2>/dev/null || echo "idle")
  fi

  case "$BRAIN_STATE" in
    captured)
      # 🟢🧠 — capture ran successfully this session
      printf '\360\237\237\242\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
      ;;
    error)
      # 🔴🧠 — hook error or degraded state
      printf '\360\237\224\264\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
      ;;
    *)
      # idle (default) — brain active, no recent hook activity
      printf '\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
      ;;
  esac
else
  printf '[%s] %s%%\n' "$MODEL" "$PCT"
fi
```

### Testing Statusline Manually

```bash
# Source: from Claude Code official docs — test with mock input
echo '{"model":{"display_name":"Sonnet"},"context_window":{"used_percentage":25},"agent":{"name":"brain-mode"}}' \
  | BRAIN_PATH="/your/vault/path" bash ~/.claude/statusline.sh
```

### Verifying Emoji Octal Sequences

```bash
# Verify 🟢 (U+1F7E2) — GREEN CIRCLE
printf '\360\237\237\242\n'  # should print 🟢

# Verify 🔴 (U+1F534) — RED CIRCLE
printf '\360\237\224\264\n'  # should print 🔴

# Verify 🧠 (U+1F9E0) — BRAIN (already in use)
printf '\360\237\247\240\n'  # should print 🧠
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Static emoji (brain-mode vs non-brain-mode) | Dynamic state (idle/captured/error) | Phase 8 | Statusline communicates hook outcomes passively |
| No state file | `.brain-state` written by hooks | Phase 8 | Cross-process channel for hook → statusline communication |
| No session reset | SessionStart writes idle | Phase 8 | Each session starts from known state |

**Deprecated/outdated:**
- Nothing is deprecated. Phase 8 is a pure extension of the existing statusline.sh — no removal of existing behavior.

---

## Open Questions

1. **Should the error state be sticky across sessions or reset on SessionStart?**
   - What we know: The `idle` reset in SessionStart gives a clean slate. But if a hook failed at the end of the previous session, the user might want to see that error state persisted into the next session.
   - What's unclear: Whether seeing a stale error state is more useful or more confusing.
   - Recommendation: Reset to `idle` on SessionStart regardless. The `.brain-errors.log` file is the persistent error record for forensics. The statusline state is a live indicator, not a historical one. Sticky error state would be confusing after the issue is resolved.

2. **Should write_brain_state be added to brain-path.sh or as inline logic in each hook?**
   - What we know: brain-path.sh already has a library pattern (brain_log_error, emit_json, etc.). All hooks source it.
   - What's unclear: Whether adding more functions to brain-path.sh increases coupling in a way that matters.
   - Recommendation: Add to brain-path.sh. It's the right home for shared hook utilities. The precedent is established, and the alternative (duplicating the atomic write pattern in each hook) is worse.

3. **What happens if the user is NOT in brain-mode but a hook writes the state file?**
   - What we know: The state file is at `$BRAIN_PATH/.brain-state`. Hooks always run (they're registered globally, not agent-gated). The state file would still be written.
   - What's unclear: Whether this matters — if the user isn't in brain-mode, the statusline already shows the non-brain branch and ignores state entirely.
   - Recommendation: No issue. The statusline correctly gates on `agent.name == "brain-mode"` before reading state. Hooks writing state outside brain-mode sessions is harmless — the file is just never read in that case.

4. **Do we need a "capturing in progress" state (between block emission and capture completion)?**
   - What we know: The stop hook emits `decision:block` and immediately exits. The statusline would show `captured` even though the user hasn't run `/brain-capture` yet.
   - What's unclear: Whether this is misleading. `captured` means "capture was requested" not "capture completed."
   - Recommendation: Keep it simple. The state name can be `capturing` conceptually even if the display is 🟢🧠. The green signal means "capture is in progress or complete" — it communicates that a meaningful session happened. Renaming states would add complexity for no user-visible benefit in v1.1.

---

## Sources

### Primary (HIGH confidence)
- `https://code.claude.com/docs/en/statusline` — Complete official statusline documentation: JSON input schema, all available fields, update timing (300ms debounce), output format, multi-line support, ANSI colors, Windows configuration, caching recommendations, troubleshooting
- Existing codebase: `statusline.sh`, `hooks/stop.sh`, `hooks/lib/brain-path.sh`, `hooks/session-start.sh`, `hooks/post-tool-use-failure.sh` — verified existing patterns for octal emoji, atomic write via mv, brain_log_error, emit_json
- `C:/Users/srco1/desktop/claude-brain-toolkit/settings.json` — verified statusLine registration, env injection of BRAIN_PATH, hook registration for all five hook types

### Secondary (MEDIUM confidence)
- WebSearch: Claude Code statusline 2026 — confirmed community pattern of file-based caching for state; multiple independent projects (ccstatusline, ccusage, claude-statusline) use temp-file caching to preserve state between statusline invocations
- `onboarding-kit/setup.sh` — verified deployment model: statusline.sh deploys to `~/.claude/statusline.sh`; BRAIN_PATH injected via settings.json `env` block

### Tertiary (LOW confidence)
- None — all claims are grounded in official docs or direct codebase inspection.

---

## Metadata

**Confidence breakdown:**
- Statusline JSON contract (input fields, update timing): HIGH — verified from official docs at code.claude.com/docs/en/statusline
- State file pattern: HIGH — derived from existing `update_encounter_count` atomic write pattern in brain-path.sh; matches community approaches verified by WebSearch
- Emoji octal sequences: HIGH — current statusline.sh uses this pattern already; sequences verified against Unicode codepoints
- Hook state transition logic: HIGH — derived directly from reading all five hook scripts; no uncertainty about when each hook fires
- BRAIN_PATH availability in statusline: MEDIUM — settings.json has `env.BRAIN_PATH` injection; same mechanism works for hooks; marked MEDIUM because not explicitly documented for statusline (only for hooks) in official docs

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (statusline API is stable; hook file format is controlled by this project)
