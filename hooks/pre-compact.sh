#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 1
fi

brain_log_error "PreCompact" "Capture trigger fired"

INSTRUCTION="Context is about to be compacted. Please run /brain-capture to preserve any useful patterns before the context is reduced."
COMPACT_JSON=$(jq -n --arg ctx "$INSTRUCTION" '{"hookSpecificOutput":{"hookEventName":"PreCompact","additionalContext":$ctx}}')
emit_json "$COMPACT_JSON"
exit 0
