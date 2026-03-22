# Phase 11: Idle Capture Offer - Research

**Researched:** 2026-03-21
**Domain:** Claude Code hooks / Notification event / idle detection / session state
**Confidence:** MEDIUM

## Summary

The Notification hook with `idle_prompt` matcher is the correct mechanism for idle capture offers. It fires when Claude finishes responding and the user has not typed for a configurable period (default 60 seconds, configurable via `messageIdleNotifThresholdMs`). The hook receives `transcript_path` in its input, which means the existing capturable-content detection logic from `stop.sh` can be directly reused. The hook can return `additionalContext` to inject a capture suggestion into Claude's context.

The main architectural challenge is the one-offer-per-session guard. The Notification hook fires on every idle period, so a state file (`$BRAIN_PATH/.brain-idle-offered`) written on first offer and checked on subsequent fires is the reliable approach. The SessionStart hook already manages session state -- it should clean up this file on session start to reset the guard.

**Primary recommendation:** Register a `Notification` hook with `idle_prompt` matcher. The hook script reuses stop.sh's transcript analysis logic (extracted to a shared function in `brain-path.sh`), checks a one-offer state file, and returns `additionalContext` with a gentle capture suggestion. No blocking -- this is advisory only.

## Standard Stack

### Core

| Component | Purpose | Why Standard |
|-----------|---------|--------------|
| `Notification` hook event | Fires when Claude is idle waiting for user | Native Claude Code hook event -- no polling or timers needed |
| `idle_prompt` matcher | Filters to only idle notifications | Built-in matcher, no regex needed |
| `additionalContext` output | Injects capture suggestion into conversation | Official Notification hook output field -- non-blocking by design |
| `transcript_path` input | Access session transcript for content analysis | Available in Notification hook input per official docs |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `messageIdleNotifThresholdMs` | Configure idle timeout (default 60s) | Optional -- default 60s is reasonable for capture offers |
| `$BRAIN_PATH/.brain-idle-offered` | One-offer-per-session guard file | Written on first offer, checked on every subsequent idle fire |
| `brain-path.sh` shared functions | Reuse capturable-content detection | Extract from stop.sh into shared function |

### Configuration

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notification-idle.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Architecture Patterns

### Recommended Approach

```
hooks/
  notification-idle.sh    # NEW: idle capture offer hook
  stop.sh                 # EXISTING: capture at session end
  session-start.sh        # MODIFIED: clean up idle-offered state file
  lib/
    brain-path.sh         # MODIFIED: add shared has_capturable_content()
```

### Pattern 1: Shared Capturable-Content Detection

**What:** Extract the transcript analysis logic from stop.sh into a reusable function in brain-path.sh, so both stop.sh and notification-idle.sh can use it.
**When to use:** Any hook that needs to decide whether the session has content worth capturing.

```bash
# In brain-path.sh -- new shared function
# Returns 0 if capturable content exists, 1 otherwise
# Sets HAS_FILE_CHANGES, HAS_GIT_COMMIT, TOOL_COUNT as side effects
has_capturable_content() {
  local transcript_path="$1"

  TOOL_COUNT=0
  HAS_GIT_COMMIT=0
  HAS_FILE_CHANGES=0

  if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
    return 1
  fi

  TOOL_COUNT=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    .name
  ' "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')

  HAS_GIT_COMMIT=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Bash") |
    .input.command // ""
  ' "$transcript_path" 2>/dev/null | grep -c 'git commit' || echo 0)

  HAS_FILE_CHANGES=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Write" or .name == "Edit") |
    .name
  ' "$transcript_path" 2>/dev/null | wc -l | tr -d ' ')

  if [ "$HAS_FILE_CHANGES" -gt 0 ] || [ "$HAS_GIT_COMMIT" -gt 0 ]; then
    return 0
  fi

  return 1
}
```

### Pattern 2: One-Offer-Per-Session Guard (State File)

**What:** A file-based guard that prevents the idle capture offer from firing more than once per session.
**When to use:** Every idle notification hook invocation.

```bash
# Guard file path
IDLE_OFFERED_FILE="$BRAIN_PATH/.brain-idle-offered"

# Check: already offered this session?
if [ -f "$IDLE_OFFERED_FILE" ]; then
  exit 0  # Silent -- already offered
fi

# ... (content detection logic) ...

# Mark as offered (atomically)
printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$IDLE_OFFERED_FILE"
```

**Session reset:** The SessionStart hook removes this file on every new session start:
```bash
# In session-start.sh, early in the script
rm -f "$BRAIN_PATH/.brain-idle-offered" 2>/dev/null
```

### Pattern 3: Advisory additionalContext (Non-Blocking)

**What:** The Notification hook cannot use `decision:block` -- it is read-only. Instead, it returns `additionalContext` which injects a gentle suggestion into Claude's context.
**When to use:** Always -- this is the only mechanism available for Notification hooks.

```bash
SUGGESTION="This session has capturable content (files: $HAS_FILE_CHANGES, commits: $HAS_GIT_COMMIT). If the user seems done or paused, you could gently ask: 'Would you like me to run /brain-capture to preserve patterns from this session?'. Only ask once -- do not repeat this offer."

HOOK_OUTPUT=$(jq -n --arg ctx "$SUGGESTION" \
  '{"hookSpecificOutput":{"hookEventName":"Notification","additionalContext":$ctx}}')
emit_json "$HOOK_OUTPUT"
```

### Anti-Patterns to Avoid

- **Using `decision:block` in Notification hook:** Notification hooks cannot block. The output will be ignored and may cause errors.
- **Using Stop hook for idle detection:** Stop fires on every Claude response turn, not on user idle. It is the wrong event for this purpose.
- **Using environment variables for the guard:** `CLAUDE_ENV_FILE` is only available in SessionStart. Environment variables set in one hook invocation are not visible in subsequent invocations (each hook runs in a fresh subprocess).
- **Polling or timer-based idle detection:** Claude Code has native idle detection via the Notification event. Do not build custom timers.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idle detection | Custom timers, polling scripts | `Notification` hook with `idle_prompt` matcher | Claude Code tracks idle state natively; hook fires at the right time |
| Content detection | New transcript parser | `has_capturable_content()` extracted from stop.sh | Already proven logic; same thresholds ensure consistency |
| Session-scoped state | Custom session ID tracking | State file cleaned by SessionStart hook | SessionStart already fires on every new session; file cleanup is atomic and simple |
| Idle timeout tuning | Custom delay logic | `messageIdleNotifThresholdMs` in config | Official setting, user-configurable |

## Common Pitfalls

### Pitfall 1: Notification Hook Fires on Every Idle Period

**What goes wrong:** Without the one-offer guard, the hook fires every time the idle threshold is reached, producing repeated capture suggestions that annoy the user.
**Why it happens:** `idle_prompt` fires on every idle detection event, not just once per session.
**How to avoid:** State file guard checked before any processing. Write the file after emitting the offer.
**Warning signs:** User reports seeing "would you like to capture?" multiple times per session.

### Pitfall 2: Guard File Not Cleaned Up Between Sessions

**What goes wrong:** The guard file persists from a previous session, so the offer never fires in new sessions.
**Why it happens:** SessionStart hook does not clean up the file, or the cleanup code has an error.
**How to avoid:** Add `rm -f "$BRAIN_PATH/.brain-idle-offered" 2>/dev/null` to session-start.sh early in the script (after brain_path_validate).
**Warning signs:** Offer never fires even when sessions have capturable content.

### Pitfall 3: Notification Hook Has Latency

**What goes wrong:** The idle notification fires 1-2 seconds after the actual idle state begins.
**Why it happens:** Known Claude Code issue -- Notification event firing has higher latency than Stop hook (GitHub issue #23383 / #19627).
**How to avoid:** This is acceptable for an advisory offer. The 1-2 second delay is not user-facing since the user is already idle. No workaround needed.
**Warning signs:** N/A -- this is cosmetic and does not affect functionality.

### Pitfall 4: idle_prompt May Fire After Every Response (Not Just True Idle)

**What goes wrong:** In some Claude Code versions, `idle_prompt` fires immediately after every Claude response, not just after genuine idle periods.
**Why it happens:** GitHub issue #12048 documents this as a known behavior where idle_prompt does not distinguish between "response complete" and "genuinely waiting for user."
**How to avoid:** The one-offer-per-session guard solves this completely -- even if idle_prompt fires after every response, the offer only fires once. Additionally, the capturable-content check filters out trivial sessions. The combination means: even in the worst case (fires every response), the user sees at most one offer and only when the session has real content.
**Warning signs:** Offer fires on the very first Claude response (before any real idle period). Acceptable if content exists.

### Pitfall 5: Transcript Path May Be Empty or Stale

**What goes wrong:** `transcript_path` in the Notification hook input may be empty or point to a non-existent file.
**Why it happens:** Edge case in early session or after errors.
**How to avoid:** `has_capturable_content()` already guards against empty/missing transcript path (returns 1 / "no content"). This is inherited from stop.sh's existing logic.
**Warning signs:** Hook silently exits without offering -- correct behavior when transcript is unavailable.

## Code Examples

### Complete notification-idle.sh Hook

```bash
#!/usr/bin/env bash
HOOK_INPUT=$(cat)

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 0  # Degrade gracefully
fi

# One-offer-per-session guard
IDLE_OFFERED_FILE="$BRAIN_PATH/.brain-idle-offered"
if [ -f "$IDLE_OFFERED_FILE" ]; then
  exit 0
fi

# Extract transcript path from hook input
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""')

# Check for capturable content (shared function from brain-path.sh)
if ! has_capturable_content "$TRANSCRIPT_PATH"; then
  exit 0  # Nothing worth capturing -- stay silent
fi

# Mark as offered BEFORE emitting (prevents race condition on rapid fires)
printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$IDLE_OFFERED_FILE"

brain_log_error "IdleCapture" "Offer fired (files: $HAS_FILE_CHANGES, commits: $HAS_GIT_COMMIT)"

SUGGESTION="This session has produced capturable content (file changes: $HAS_FILE_CHANGES, git commits: $HAS_GIT_COMMIT). If the conversation has reached a natural pause, consider gently offering: 'Would you like me to run /brain-capture to preserve useful patterns from this session?' -- only offer once, do not repeat."

HOOK_OUTPUT=$(jq -n --arg ctx "$SUGGESTION" \
  '{"hookSpecificOutput":{"hookEventName":"Notification","additionalContext":$ctx}}')
emit_json "$HOOK_OUTPUT"
exit 0
```

### SessionStart Cleanup Addition

```bash
# Add after brain_path_validate succeeds, before any other logic
rm -f "$BRAIN_PATH/.brain-idle-offered" 2>/dev/null
```

### settings.json Addition

```json
"Notification": [
  {
    "matcher": "idle_prompt",
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/notification-idle.sh",
        "timeout": 10
      }
    ]
  }
]
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No idle detection | `Notification` hook with `idle_prompt` matcher | Claude Code hooks system (2025) | Native idle detection, no custom timers needed |
| Hardcoded 60s idle timeout | Configurable via `messageIdleNotifThresholdMs` | ~2026 (issue #13922 resolved) | Users can tune idle threshold |
| `idle_prompt` fires correctly | May fire after every response (issue #12048) | Known issue as of 2026-03 | One-offer guard mitigates this completely |

**Known issues:**
- `idle_prompt` may fire after every response, not just genuine idle (GitHub #12048) -- mitigated by one-offer guard
- Notification hook has ~1-2s latency vs Stop hook (GitHub #23383) -- acceptable for advisory offer
- `messageIdleNotifThresholdMs` config may not be documented in all versions -- default 60s is fine

## Open Questions

1. **Does `additionalContext` from Notification hook actually appear in Claude's context?**
   - What we know: Official docs say Notification hooks can return `additionalContext`. SessionStart and PreCompact hooks use the same field successfully in this project.
   - What's unclear: Whether `additionalContext` from a Notification hook is injected the same way (into the next turn's context). No first-hand verification.
   - Recommendation: Implement and test. If `additionalContext` does not surface, fall back to a different mechanism (e.g., writing a suggestion file that brain-mode instructions tell Claude to check).

2. **Exact behavior of idle_prompt in current Claude Code version**
   - What we know: Reports conflict -- some say it fires after every response, others say after genuine idle. Behavior may vary by version.
   - What's unclear: Which behavior the user's current Claude Code version exhibits.
   - Recommendation: The one-offer guard + content check makes this irrelevant. Both behaviors produce the correct outcome.

## Sources

### Primary (HIGH confidence)
- https://code.claude.com/docs/en/hooks -- Complete hooks reference. Verified: Notification hook exists, `idle_prompt` matcher supported, `additionalContext` output field, `transcript_path` in input, Notification hooks cannot block. Fetched 2026-03-21.
- Existing codebase: `hooks/stop.sh` -- capturable-content detection logic (file changes + git commits), `hooks/lib/brain-path.sh` -- shared utilities, `hooks/session-start.sh` -- session lifecycle management, `settings.json` -- current hook registrations.

### Secondary (MEDIUM confidence)
- https://github.com/anthropics/claude-code/issues/13922 -- `messageIdleNotifThresholdMs` configurable idle timeout. Confirmed implemented.
- https://github.com/anthropics/claude-code/issues/12048 -- `idle_prompt` fires after every response (not just genuine idle). Closed as duplicate of #10168.
- https://github.com/anthropics/claude-code/issues/23383 -- Notification hook latency vs Stop hook (~1-2s delay). Closed as duplicate of #19627.

### Tertiary (LOW confidence)
- Community reports on idle_prompt behavior vary. Some users report it works correctly, others report false positives. Behavior may be version-dependent.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Notification hook with idle_prompt matcher is documented in official Claude Code hooks reference
- Architecture: MEDIUM -- additionalContext injection from Notification hooks is documented but not verified first-hand in this project
- Pitfalls: HIGH -- known issues well-documented in GitHub issues; mitigations are straightforward
- One-offer guard: HIGH -- file-based state with SessionStart cleanup is a proven pattern in this codebase

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (Claude Code hooks API is relatively stable; idle_prompt behavior may change if #12048 is fixed upstream)
