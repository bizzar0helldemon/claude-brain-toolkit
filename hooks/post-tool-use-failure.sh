#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 1
fi

# Log tool failure for post-mortem debugging
TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
ERROR_MSG=$(printf '%s' "$HOOK_INPUT" | jq -r '.error // "no error message"')

brain_log_error "ToolFailure:$TOOL_NAME" "$ERROR_MSG"

# Phase 1: log only — future phases add error pattern matching here
emit_json '{"status":"ok","logged":true,"tool":"'"$TOOL_NAME"'"}'
exit 0
