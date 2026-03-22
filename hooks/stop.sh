#!/usr/bin/env bash
HOOK_INPUT=$(cat)

# CRITICAL: Loop guard MUST be checked BEFORE sourcing anything
# stop_hook_active is true when this hook already fired once this turn
STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # Already ran once — let Claude stop. No output, no logging, no sourcing.
  exit 0
fi

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Brain path invalid — degrade, don't block stop
  exit 0
fi

# Extract transcript path from hook input
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""')

# Check for capturable content (shared function from brain-path.sh)
if ! has_capturable_content "$TRANSCRIPT_PATH"; then
  # Trivial session — silent skip, no output
  exit 0
fi

brain_log_error "Stop" "Capture trigger fired (tools: $TOOL_COUNT, commits: $HAS_GIT_COMMIT, files: $HAS_FILE_CHANGES)"

REASON="Before ending this session, please run /brain-capture to preserve any useful patterns from this conversation, then briefly confirm what was captured (e.g., 'Brain captured: N learnings') and then you can stop."
BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
