#!/usr/bin/env bash
HOOK_INPUT=$(cat)

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Brain path invalid — silent exit, don't disrupt idle notification
  exit 0
fi

# One-offer guard: only suggest capture once per session
IDLE_OFFERED_FILE="$BRAIN_PATH/.brain-idle-offered"
if [ -f "$IDLE_OFFERED_FILE" ]; then
  exit 0
fi

# Extract transcript path from hook input
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""')

# Check for capturable content (shared function from brain-path.sh)
if ! has_capturable_content "$TRANSCRIPT_PATH"; then
  # No capturable content — stay silent
  exit 0
fi

# Write guard file BEFORE emitting (prevents race on rapid idle fires)
printf '%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$IDLE_OFFERED_FILE"

brain_log_error "IdleCapture" "Offer triggered (files: $HAS_FILE_CHANGES, commits: $HAS_GIT_COMMIT)"

# Build additionalContext suggestion for Claude
CTX="This session has produced capturable content (file changes: $HAS_FILE_CHANGES, git commits: $HAS_GIT_COMMIT). If the conversation has reached a natural pause, consider gently offering: 'Would you like me to run /brain-capture to preserve useful patterns from this session?' -- only offer once, do not repeat."

HOOK_OUTPUT=$(jq -n \
  --arg ctx "$CTX" \
  '{"hookSpecificOutput": {"hookEventName": "Notification", "additionalContext": $ctx}}')

emit_json "$HOOK_OUTPUT"
exit 0
