#!/usr/bin/env bash
# Stop hook — mechanical session capture (charter: fully-automatic memory).
#
# On every session end this hook WRITES, silently:
#   1. A session receipt line to $BRAIN_PATH/brain-mode/session-log.jsonl
#   2. GSD ingestion: new .planning/ summary/learnings/verification docs are
#      copied into $BRAIN_PATH/inbox/captures/ with canonical frontmatter
# Then, only when the session had capturable content, it emits ONE
# decision:block directing Claude (never the user) to distill via /brain-capture.

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

TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""')
CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // ""')
[ -z "$CWD" ] && CWD=$(pwd)

# --- Derive project tag: .brain.md tag > git repo basename > cwd basename ---
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

# --- Analyze transcript once (sets TOOL_COUNT, HAS_GIT_COMMIT, HAS_FILE_CHANGES) ---
CAPTURABLE=1
if has_capturable_content "$TRANSCRIPT_PATH"; then
  CAPTURABLE=0
fi

# Sanitize counters (defensive: must be plain integers for jq --argjson)
TOOL_COUNT="${TOOL_COUNT//[^0-9]/}"; TOOL_COUNT="${TOOL_COUNT:-0}"
HAS_GIT_COMMIT="${HAS_GIT_COMMIT//[^0-9]/}"; HAS_GIT_COMMIT="${HAS_GIT_COMMIT:-0}"
HAS_FILE_CHANGES="${HAS_FILE_CHANGES//[^0-9]/}"; HAS_FILE_CHANGES="${HAS_FILE_CHANGES:-0}"

# --- 1. Mechanical session receipt (always, silent, no model involved) ---
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "$BRAIN_PATH/brain-mode"
jq -cn \
  --arg ts "$NOW" \
  --arg project "$PROJECT" \
  --arg cwd "$CWD" \
  --argjson tools "$TOOL_COUNT" \
  --argjson commits "$HAS_GIT_COMMIT" \
  --argjson files_edited "$HAS_FILE_CHANGES" \
  '{ts:$ts,project:$project,cwd:$cwd,tools:$tools,commits:$commits,files_edited:$files_edited}' \
  >> "$BRAIN_PATH/brain-mode/session-log.jsonl" 2>/dev/null

# --- 2. GSD ingestion: .planning/ artifacts flow into the vault (brain-as-spine) ---
if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/.planning" ]; then
  STAMP="$BRAIN_PATH/brain-mode/.ingest-stamp-${PROJECT}"
  INGEST_DIR="$BRAIN_PATH/inbox/captures"
  mkdir -p "$INGEST_DIR"

  if [ -f "$STAMP" ]; then
    NEW_FILES=$(find "$REPO_ROOT/.planning" -type f -name '*.md' \
      \( -iname '*SUMMARY*' -o -iname '*LEARNINGS*' -o -iname '*VERIFICATION*' -o -iname '*RESEARCH*' \) \
      -newer "$STAMP" 2>/dev/null)
  else
    # First run for this project: only pick up files touched in the last day
    NEW_FILES=$(find "$REPO_ROOT/.planning" -type f -name '*.md' \
      \( -iname '*SUMMARY*' -o -iname '*LEARNINGS*' -o -iname '*VERIFICATION*' -o -iname '*RESEARCH*' \) \
      -mtime -1 2>/dev/null)
  fi

  INGESTED=0
  while IFS= read -r src; do
    [ -z "$src" ] && continue
    base="gsd-${PROJECT}-$(basename "${src%.md}" | tr '[:upper:]' '[:lower:]')"
    dest="$INGEST_DIR/${base}.md"
    [ -f "$dest" ] && continue   # name-level dedup: already ingested
    {
      printf -- '---\n'
      printf 'title: %s\n' "$base"
      printf 'type: capture\n'
      printf 'project: %s\n' "$PROJECT"
      printf 'status: captured\n'
      printf 'source: gsd-ingest\n'
      printf 'created: %s\n' "$(date -u +%Y-%m-%d)"
      printf -- '---\n\n'
      cat "$src"
    } > "$dest" 2>/dev/null && INGESTED=$(( INGESTED + 1 ))
  done <<EOF_FILES
$NEW_FILES
EOF_FILES
  touch "$STAMP" 2>/dev/null
  if [ "$INGESTED" -gt 0 ]; then
    brain_log_error "Stop" "GSD ingest: $INGESTED .planning artifact(s) -> inbox/captures/"
  fi
fi

# --- 3. Semantic distillation: direct Claude (not the user) to capture, once ---
if [ "$CAPTURABLE" -eq 0 ]; then
  brain_log_error "Stop" "Receipt written (tools: $TOOL_COUNT, commits: $HAS_GIT_COMMIT, files: $HAS_FILE_CHANGES)"
  REASON="Session ending. A mechanical session receipt was already written to the vault — do not mention it. If this session produced a non-obvious lesson, pattern, or decision worth keeping, silently run /brain-capture now and stamp 'project: ${PROJECT}' in the note's frontmatter. Do not ask the user anything and do not summarize the capture beyond one collapsed line. If nothing is worth distilling, just stop."
  BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
  emit_json "$BLOCK_JSON"
fi
exit 0
