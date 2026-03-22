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

# Default: no signals detected
TOOL_COUNT=0
HAS_GIT_COMMIT=0
HAS_FILE_CHANGES=0

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Count all Claude tool calls (excludes progress entries — filters to assistant messages only)
  TOOL_COUNT=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    .name
  ' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ')

  # Check for git commits in Bash tool calls
  HAS_GIT_COMMIT=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Bash") |
    .input.command // ""
  ' "$TRANSCRIPT_PATH" 2>/dev/null | grep -c 'git commit' || echo 0)

  # Check for file write/edit operations
  HAS_FILE_CHANGES=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Write" or .name == "Edit") |
    .name
  ' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ')
fi

# Determine if session has capturable content
# Threshold: actual code changes or commits — not just tool usage (reads, agents, etc.)
SHOULD_CAPTURE=false
if [ "$HAS_FILE_CHANGES" -gt 0 ] || [ "$HAS_GIT_COMMIT" -gt 0 ]; then
  SHOULD_CAPTURE=true
fi

if [ "$SHOULD_CAPTURE" = "false" ]; then
  # Trivial session — silent skip, no output
  exit 0
fi

brain_log_error "Stop" "Capture trigger fired (tools: $TOOL_COUNT, commits: $HAS_GIT_COMMIT, files: $HAS_FILE_CHANGES)"

REASON="Before ending this session, please run /brain-capture to preserve any useful patterns from this conversation, then briefly confirm what was captured (e.g., 'Brain captured: N learnings') and then you can stop."
BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
