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

# Phase 1: scaffold only — future phases add pre-stop capture here
emit_json '{"status":"ok","brain_mode":true}'
exit 0
