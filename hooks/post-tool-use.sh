#!/usr/bin/env bash
# PostToolUse hook — silent ledgers (charter: fully-automatic memory).
#
# Two silent, non-blocking concerns:
#   Bash `git commit`  -> one record in brain-mode/commit-log.jsonl
#   Read of a vault .md -> one "use" event in brain-mode/retrieval-log.jsonl
# The use events are the missing half of the feedback loop: the gardener folds
# them so "was this surfaced note ever actually opened" becomes measurable.
# No blocking, no nagging, no output.

HOOK_INPUT=$(cat)

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Brain path invalid — degrade gracefully, do NOT block tool use
  exit 0
fi

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // ""')

# --- Read of a vault note -> feedback-loop use event -------------------------
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Grep" ]; then
  READ_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""')
  # Resolve to an absolute path, then test containment in the vault.
  case "$READ_PATH" in
    "$BRAIN_PATH"/*)
      REL="${READ_PATH#"${BRAIN_PATH}"/}"
      # Only count knowledge notes, not the machinery/logs.
      case "$REL" in
        brain-mode/*|.*) ;;  # skip logs, state, hidden files
        *.md)
          NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
          SESSION="${CLAUDE_SESSION_ID:-$(date -u +%s)-$$}"
          mkdir -p "$BRAIN_PATH/brain-mode" 2>/dev/null
          jq -cn --arg ts "$NOW" --arg session "$SESSION" --arg path "$REL" \
            '{ts:$ts,session:$session,path:$path,via:"read"}' \
            >> "$BRAIN_PATH/brain-mode/retrieval-log.jsonl" 2>/dev/null
          ;;
      esac
      ;;
  esac
  exit 0
fi

COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

# Only the commit ledger acts on Bash calls
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
