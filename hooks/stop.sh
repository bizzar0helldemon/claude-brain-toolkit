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

brain_log_error "Stop" "Capture trigger fired"

REASON="Before ending this session, please run /brain-capture to preserve any useful patterns from this conversation, then run /daily-note to log a session summary. After completing both, briefly confirm what was captured (e.g., 'Brain captured: N learnings, daily note updated') and then you can stop."
BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
