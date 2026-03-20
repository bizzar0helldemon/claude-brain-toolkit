#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Validation already emitted dual-channel error — just exit non-blocking
  exit 1
fi

# Parse source field for future use
SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // "startup"')

# Log startup entry (.brain-errors.log serves as general brain log)
brain_log_error "SessionStart" "Brain mode initialized (source: $SOURCE)"

# Phase 1: scaffold only — future phases add vault context injection here
# Emit success status for Claude
emit_json '{"status":"ok","brain_mode":true,"phase":"scaffold"}'
exit 0
