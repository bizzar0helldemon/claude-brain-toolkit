#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 0
fi

# Extract tool context
TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
ERROR_MSG=$(printf '%s' "$HOOK_INPUT" | jq -r '.error // "no error message"')
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

# Log tool failure for post-mortem debugging
brain_log_error "ToolFailure:$TOOL_NAME" "$ERROR_MSG"
write_brain_state "error"

# Pattern matching against stored error patterns
PATTERN_STORE="${BRAIN_PATH}/brain-mode/pattern-store.json"

# Degrade gracefully when no pattern store exists
if [ ! -f "$PATTERN_STORE" ]; then
  emit_json '{"status":"ok","logged":true,"tool":"'"$TOOL_NAME"'"}'
  exit 0
fi

# Find first matching pattern (match error or command against pattern key, case-insensitive).
# `. as $p` binds the pattern object before select so $p.key is accessible
# inside contains() (which otherwise evaluates in string context after the pipe).
MATCH=$(jq -r \
  --arg error_msg "$ERROR_MSG" \
  --arg command "$COMMAND" \
  '.patterns[] |
   . as $p |
   select(
     (($error_msg | ascii_downcase) | contains($p.key | ascii_downcase)) or
     (($command | ascii_downcase) | contains($p.key | ascii_downcase))
   ) |
   .solution' \
  "$PATTERN_STORE" 2>/dev/null | head -1)

if [ -n "$MATCH" ]; then
  # Increment encounter count for matched pattern
  update_encounter_count "$PATTERN_STORE" "$ERROR_MSG"

  # Build response with past solution injected into context
  CONTEXT_MSG="Past solution found for this error:\n\n$MATCH"
  emit_json "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUseFailure\",\"additionalContext\":\"$CONTEXT_MSG\"}}"
  exit 0
fi

# No match — emit simple logged response
emit_json '{"status":"ok","logged":true,"tool":"'"$TOOL_NAME"'"}'
exit 0
