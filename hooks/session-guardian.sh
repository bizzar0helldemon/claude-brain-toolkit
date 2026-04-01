#!/usr/bin/env bash
# hooks/session-guardian.sh — PostToolUse hook
# Monitors context window % and read/write ratio per session.
# Warns at 70%/85% context usage and detects runaway research loops.
# State tracked in $BRAIN_PATH/.brain-session-metrics.json.

HOOK_INPUT=$(cat)

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate 2>/dev/null; then
  exit 0
fi

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // ""')
CONTEXT_PCT=$(printf '%s' "$HOOK_INPUT" | jq -r '.context_window.used_percentage // 0' 2>/dev/null | cut -d. -f1)
[ -z "$CONTEXT_PCT" ] || [ "$CONTEXT_PCT" = "null" ] && CONTEXT_PCT=0

METRICS_FILE="$BRAIN_PATH/.brain-session-metrics.json"

# Initialize metrics if missing or corrupt
if [ ! -f "$METRICS_FILE" ] || ! jq empty "$METRICS_FILE" 2>/dev/null; then
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"session_start":"%s","total_reads":0,"total_writes":0,"consecutive_reads":0,"last_context_pct":0,"warned_70":false,"warned_85":false,"warned_runaway":false}\n' "$NOW" > "$METRICS_FILE"
fi

# ── Classify tool ────────────────────────────────────────────────
IS_READ=0
IS_WRITE=0
case "$TOOL_NAME" in
  Read|Grep|Glob|WebFetch|WebSearch) IS_READ=1 ;;
  Write|Edit) IS_WRITE=1 ;;
  Bash)
    CMD=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')
    if printf '%s' "$CMD" | grep -qE '(git commit|git push|mkdir|touch|cp |mv |tee )'; then
      IS_WRITE=1
    else
      IS_READ=1
    fi
    ;;
  *) ;; # Neutral tools (Agent, TaskCreate, etc.) — don't affect counters
esac

# ── Update metrics ───────────────────────────────────────────────
if [ "$IS_READ" -eq 1 ]; then
  jq --arg pct "$CONTEXT_PCT" \
    '.total_reads += 1 | .consecutive_reads += 1 | .last_context_pct = ($pct | tonumber)' \
    "$METRICS_FILE" > "${METRICS_FILE}.tmp" 2>/dev/null && \
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE" 2>/dev/null
elif [ "$IS_WRITE" -eq 1 ]; then
  jq --arg pct "$CONTEXT_PCT" \
    '.total_writes += 1 | .consecutive_reads = 0 | .warned_runaway = false | .last_context_pct = ($pct | tonumber)' \
    "$METRICS_FILE" > "${METRICS_FILE}.tmp" 2>/dev/null && \
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE" 2>/dev/null
fi

# ── Read current state ───────────────────────────────────────────
WARNED_70=$(jq -r '.warned_70 // false' "$METRICS_FILE" 2>/dev/null)
WARNED_85=$(jq -r '.warned_85 // false' "$METRICS_FILE" 2>/dev/null)
WARNED_RUNAWAY=$(jq -r '.warned_runaway // false' "$METRICS_FILE" 2>/dev/null)
CONSEC_READS=$(jq -r '.consecutive_reads // 0' "$METRICS_FILE" 2>/dev/null)

# ── Context threshold checks ────────────────────────────────────
if [ "$CONTEXT_PCT" -ge 85 ] && [ "$WARNED_85" = "false" ]; then
  jq '.warned_85 = true' "$METRICS_FILE" > "${METRICS_FILE}.tmp" 2>/dev/null && \
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE" 2>/dev/null
  REASON="Session Guardian: Context at ${CONTEXT_PCT}%. Create a handoff now to preserve session progress. Run /brain-handoff for a complete handoff, or /brain-handoff --lite for a quick one."
  emit_json "$(jq -n --arg r "$REASON" '{"decision":"block","reason":$r}')"
  exit 0
elif [ "$CONTEXT_PCT" -ge 70 ] && [ "$WARNED_70" = "false" ]; then
  jq '.warned_70 = true' "$METRICS_FILE" > "${METRICS_FILE}.tmp" 2>/dev/null && \
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE" 2>/dev/null
  REASON="Session Guardian: Context at ${CONTEXT_PCT}%. Consider wrapping up current work or running /brain-handoff --lite to preserve progress."
  emit_json "$(jq -n --arg r "$REASON" '{"decision":"block","reason":$r}')"
  exit 0
fi

# ── Runaway research check ──────────────────────────────────────
if [ "$CONSEC_READS" -ge 5 ] && [ "$WARNED_RUNAWAY" = "false" ]; then
  jq '.warned_runaway = true' "$METRICS_FILE" > "${METRICS_FILE}.tmp" 2>/dev/null && \
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE" 2>/dev/null
  REASON="Session Guardian: ${CONSEC_READS} consecutive read operations without writing. Consider acting on what you've learned, narrowing your search, or documenting findings."
  emit_json "$(jq -n --arg r "$REASON" '{"decision":"block","reason":$r}')"
  exit 0
fi

# All clear — passthrough
exit 0
