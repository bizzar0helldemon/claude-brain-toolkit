#!/usr/bin/env bash
HOOK_INPUT=$(cat)

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Brain path invalid — degrade gracefully, do NOT block tool use
  exit 0
fi

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // ""')
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

# Only act on Bash tool calls
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

# Only act on git commit commands
if ! printf '%s' "$COMMAND" | grep -q 'git commit'; then
  exit 0
fi

# Skip dry runs — not a real commit
if printf '%s' "$COMMAND" | grep -q '\-\-dry-run'; then
  exit 0
fi

brain_log_error "PostToolUse" "git commit detected: $COMMAND"

REASON="A git commit just completed. Before continuing, please run /brain-capture to preserve any useful patterns or decisions from this work session. After capturing, briefly summarize what was committed and what was captured."
BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
