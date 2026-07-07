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

# Pattern matching against stored error patterns
PATTERN_STORE="${BRAIN_PATH}/brain-mode/pattern-store.json"

# Degrade gracefully when no pattern store exists
if [ ! -f "$PATTERN_STORE" ]; then
  emit_json '{"status":"ok","logged":true,"tool":"'"$TOOL_NAME"'"}'
  exit 0
fi

# Self-heal legacy stores: bare-array schema never matches the v1 reader below.
# This mismatch silently killed pattern recall for 1,000+ failures — migrate loudly.
migrate_pattern_store "$PATTERN_STORE"

# Find first matching pattern (match error or command against pattern key, case-insensitive).
# `. as $p` binds the pattern object before select so $p.key is accessible
# inside contains() (which otherwise evaluates in string context after the pipe).
# NOTE: jq stderr goes to the brain error log, NOT /dev/null — a broken store
# must be loud (the old 2>/dev/null hid the schema mismatch for 3 months).
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
  "$PATTERN_STORE" 2>>"${BRAIN_PATH}/.brain-errors.log" | head -1)

if [ -n "$MATCH" ]; then
  # Increment encounter count for matched pattern (must run first — read-after-write)
  update_encounter_count "$PATTERN_STORE" "$ERROR_MSG"

  # Read back updated encounter count
  COUNT=$(jq -r \
    --arg err "$ERROR_MSG" \
    '.patterns[] | . as $p | select(($err | ascii_downcase) | contains($p.key | ascii_downcase)) | .encounter_count' \
    "$PATTERN_STORE" 2>>"${BRAIN_PATH}/.brain-errors.log" | head -1)

  # Numeric guard — prevents bash errors on empty or non-numeric COUNT
  COUNT="${COUNT:-0}"
  if ! printf '%s' "$COUNT" | grep -qE '^[0-9]+$'; then
    COUNT=0
  fi

  # Calculate tier based on encounter count
  if [ "$COUNT" -ge 5 ]; then
    TIER="root-cause-flag"
    TIER_NOTE="[Encounter $COUNT — investigate root cause, do not repeat the solution]"
  elif [ "$COUNT" -ge 2 ]; then
    TIER="brief-reminder"
    TIER_NOTE="[Encounter $COUNT — give a 1-2 sentence reminder only]"
  else
    TIER="full-explanation"
    TIER_NOTE="[Encounter $COUNT — give full explanation with steps]"
  fi

  # Build context message and JSON safely via jq --arg (no string interpolation of solution text)
  CONTEXT_MSG=$(printf "Past solution found [encounter_count=%s tier=%s]:\n\n%s\n\n%s" \
    "$COUNT" "$TIER" "$MATCH" "$TIER_NOTE")

  OUTPUT=$(jq -n \
    --arg ctx "$CONTEXT_MSG" \
    '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":$ctx}}')

  emit_json "$OUTPUT"
  exit 0
fi

# No match — emit simple logged response
emit_json '{"status":"ok","logged":true,"tool":"'"$TOOL_NAME"'"}'
exit 0
