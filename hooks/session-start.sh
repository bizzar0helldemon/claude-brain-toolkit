#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Validation already emitted dual-channel error — just exit non-blocking
  exit 1
fi

# Reset state to idle — new session starts clean, stale prior state discarded
write_brain_state "idle"

# Source brain-context library
source ~/.claude/hooks/lib/brain-context.sh

# Parse hook input fields
SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // "startup"')
CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // ""')

# Fall back to actual cwd if not provided in hook input
if [ -z "$CWD" ]; then
  CWD=$(pwd)
fi

# Create a temp file for tracking state from build_brain_context subshell
_BRAIN_CONTEXT_STATE_FILE=$(mktemp)
export _BRAIN_CONTEXT_STATE_FILE

# Build vault context within token budget
# build_brain_context writes tracking state to _BRAIN_CONTEXT_STATE_FILE
VAULT_CONTEXT=$(build_brain_context "$CWD" "$SOURCE")

# Source the tracking state back into this shell (restores _PROJECT_COUNT etc.)
# shellcheck source=/dev/null
source "$_BRAIN_CONTEXT_STATE_FILE"
rm -f "$_BRAIN_CONTEXT_STATE_FILE"
unset _BRAIN_CONTEXT_STATE_FILE

# Build summary block using tracked counters from build_brain_context
SUMMARY_BLOCK=$(build_summary_block \
  "$CWD" \
  "$SOURCE" \
  "$_PROJECT_COUNT" \
  "$_PITFALL_COUNT" \
  "$_GLOBAL_ACTIVE" \
  "$_NEWEST_MTIME")

# Combine summary block and vault context
if [ -n "$VAULT_CONTEXT" ]; then
  ADDITIONAL_CONTEXT="${SUMMARY_BLOCK}

${VAULT_CONTEXT}"
else
  ADDITIONAL_CONTEXT="$SUMMARY_BLOCK"
fi

# Build and emit the hook output JSON
# All string content goes through jq --arg to ensure safe escaping
HOOK_OUTPUT=$(jq -n \
  --arg ctx "$ADDITIONAL_CONTEXT" \
  '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}')

emit_json "$HOOK_OUTPUT"

# Persist session state for delta-loading on next session
PROJECT_NAME=$(get_project_name "$CWD" | awk '{print $1}')
if [ "${#_LOADED_FILES[@]}" -gt 0 ]; then
  write_session_state "$PROJECT_NAME" "${_LOADED_FILES[@]}"
else
  write_session_state "$PROJECT_NAME"
fi

# Signal to downstream hooks that brain has loaded
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  printf '%s\n' "BRAIN_LOADED=1" >> "$CLAUDE_ENV_FILE"
fi

# Log session start
ENTRY_COUNT="${#_LOADED_FILES[@]}"
brain_log_error "SessionStart" "Brain context loaded (source: $SOURCE, entries: $ENTRY_COUNT, project: $PROJECT_NAME)"

exit 0
