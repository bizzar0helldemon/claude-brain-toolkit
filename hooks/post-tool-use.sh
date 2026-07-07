#!/usr/bin/env bash
# PostToolUse hook — silent commit ledger (charter: fully-automatic memory).
#
# On a real `git commit`, appends one JSONL record to
# $BRAIN_PATH/brain-mode/commit-log.jsonl. No blocking, no nagging, no output.
# (The old behavior — decision:block demanding /brain-capture after every
# commit — violated the fully-automatic posture and substring-matched any
# command merely containing "git commit". Removed 2026-07-07.)

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

# Word-boundary match: `git commit` or `git -C <path> commit` as an actual
# command, not any string containing the substring (the old grep matched
# read-only greps whose *text* mentioned "git commit").
if ! printf '%s' "$COMMAND" | grep -qE '(^|[;&|[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)'; then
  exit 0
fi

# Skip dry runs — not a real commit
if printf '%s' "$COMMAND" | grep -q '\-\-dry-run'; then
  exit 0
fi

# Derive project tag (same derivation as stop.sh)
CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // ""')
[ -z "$CWD" ] && CWD=$(pwd)
PROJECT=""
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$REPO_ROOT" ] && [ -f "$REPO_ROOT/.brain.md" ]; then
  PROJECT=$(sed -n 's/.*[Bb]rain project tag[^`]*`\([^`]*\)`.*/\1/p' "$REPO_ROOT/.brain.md" | head -1)
fi
if [ -z "$PROJECT" ]; then
  if [ -n "$REPO_ROOT" ]; then
    PROJECT=$(basename "$REPO_ROOT")
  else
    PROJECT=$(basename "$CWD")
  fi
fi
PROJECT=$(printf '%s' "$PROJECT" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')

# Silent write: one commit record, then get out of the way
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HEAD_LINE=$(git -C "$CWD" log -1 --format='%h %s' 2>/dev/null)
mkdir -p "$BRAIN_PATH/brain-mode"
jq -cn \
  --arg ts "$NOW" \
  --arg project "$PROJECT" \
  --arg cwd "$CWD" \
  --arg commit "$HEAD_LINE" \
  '{ts:$ts,project:$project,cwd:$cwd,commit:$commit}' \
  >> "$BRAIN_PATH/brain-mode/commit-log.jsonl" 2>/dev/null

exit 0
