#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 1
fi

# Phase 1: scaffold only — future phases add pre-compact capture here
TRIGGER=$(printf '%s' "$HOOK_INPUT" | jq -r '.trigger // "auto"')
emit_json '{"status":"ok","brain_mode":true,"trigger":"'"$TRIGGER"'"}'
exit 0
