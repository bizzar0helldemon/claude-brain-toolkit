#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Validation already emitted dual-channel error — just exit non-blocking
  exit 1
fi

# Reset idle-capture one-offer guard for new session
rm -f "$BRAIN_PATH/.brain-idle-offered" 2>/dev/null

# Parse hook input fields (do this EARLY so /clear fast path works)
SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // "startup"')
CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // ""')

# Fall back to actual cwd if not provided in hook input
if [ -z "$CWD" ]; then
  CWD=$(pwd)
fi

# --- Fast path: /clear reuses cached context, skips expensive vault scan ---
CACHED_CONTEXT_FILE="${BRAIN_PATH}/.brain-cached-context.json"

if [ "$SOURCE" = "clear" ]; then
  if [ -f "$CACHED_CONTEXT_FILE" ]; then
    # Reuse the context from the previous session start
    CACHED_CONTEXT=$(jq -r '.additionalContext // empty' "$CACHED_CONTEXT_FILE" 2>/dev/null)
    if [ -n "$CACHED_CONTEXT" ]; then
      HOOK_OUTPUT=$(jq -n \
        --arg ctx "$CACHED_CONTEXT" \
        '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}')
      emit_json "$HOOK_OUTPUT"

      if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
        printf '%s\n' "BRAIN_LOADED=1" >> "$CLAUDE_ENV_FILE"
      fi

      brain_log_error "SessionStart" "Fast reload from cache (source: clear)"
      exit 0
    fi
  fi

  # No cache file yet — emit minimal context so /clear stays instant
  # The cache will be built on the next full startup
  MINIMAL_CTX="Brain: /clear (no cache yet — full context loads on next startup)"
  HOOK_OUTPUT=$(jq -n \
    --arg ctx "$MINIMAL_CTX" \
    '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}')
  emit_json "$HOOK_OUTPUT"

  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    printf '%s\n' "BRAIN_LOADED=1" >> "$CLAUDE_ENV_FILE"
  fi

  brain_log_error "SessionStart" "Fast /clear with no cache — emitted minimal context"
  exit 0
fi

# Source brain-context library (only needed for full path)
source ~/.claude/hooks/lib/brain-context.sh

# --- Full path: startup/resume/compact — build context from vault ---

# --- Git sync check: detect ahead/behind/diverged state for multi-machine safety ---
GIT_SYNC_STATUS=""
if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Fetch remote state (fast, no merge — timeout after 5s to avoid blocking on network issues)
  timeout 5 git -C "$CWD" fetch --quiet 2>/dev/null

  LOCAL=$(git -C "$CWD" rev-parse HEAD 2>/dev/null)
  REMOTE=$(git -C "$CWD" rev-parse '@{upstream}' 2>/dev/null)
  BASE=$(git -C "$CWD" merge-base HEAD '@{upstream}' 2>/dev/null)

  if [ -n "$LOCAL" ] && [ -n "$REMOTE" ] && [ -n "$BASE" ]; then
    if [ "$LOCAL" = "$REMOTE" ]; then
      : # In sync — no message needed
    elif [ "$LOCAL" = "$BASE" ]; then
      BEHIND_COUNT=$(git -C "$CWD" rev-list --count HEAD..@{upstream} 2>/dev/null)
      GIT_SYNC_STATUS="   Git: LOCAL IS BEHIND by ${BEHIND_COUNT} commit(s) — pull before working to avoid divergence"
    elif [ "$REMOTE" = "$BASE" ]; then
      AHEAD_COUNT=$(git -C "$CWD" rev-list --count @{upstream}..HEAD 2>/dev/null)
      GIT_SYNC_STATUS="   Git: ${AHEAD_COUNT} unpushed commit(s) — push when ready"
    else
      AHEAD_COUNT=$(git -C "$CWD" rev-list --count @{upstream}..HEAD 2>/dev/null)
      BEHIND_COUNT=$(git -C "$CWD" rev-list --count HEAD..@{upstream} 2>/dev/null)
      GIT_SYNC_STATUS="   Git: DIVERGED — ${AHEAD_COUNT} ahead, ${BEHIND_COUNT} behind remote — reconcile before working"
    fi
  fi
fi

# Create a temp file for tracking state from build_brain_context subshell
_BRAIN_CONTEXT_STATE_FILE=$(mktemp)
export _BRAIN_CONTEXT_STATE_FILE

# Build vault context within token budget
# build_brain_context writes tracking state to _BRAIN_CONTEXT_STATE_FILE
VAULT_CONTEXT=$(build_brain_context "$CWD" "$SOURCE")

# Source the tracking state back into this shell (restores _PROJECT_COUNT etc.)
# shellcheck source=/dev/null
source "$_BRAIN_CONTEXT_STATE_FILE"
rm -f "$_BRAIN_CONTEXT_STATE_FILE"
unset _BRAIN_CONTEXT_STATE_FILE

# Build summary block using tracked counters from build_brain_context
SUMMARY_BLOCK=$(build_summary_block \
  "$CWD" \
  "$SOURCE" \
  "$_PROJECT_COUNT" \
  "$_PITFALL_COUNT" \
  "$_GLOBAL_ACTIVE" \
  "$_NEWEST_MTIME" \
  "${_TOTAL_VAULT_COUNT:-0}")

# Append git sync status to summary if present
if [ -n "$GIT_SYNC_STATUS" ]; then
  SUMMARY_BLOCK="${SUMMARY_BLOCK}
${GIT_SYNC_STATUS}"
fi

# Combine summary block and vault context
if [ -n "$VAULT_CONTEXT" ]; then
  ADDITIONAL_CONTEXT="${SUMMARY_BLOCK}

${VAULT_CONTEXT}"
else
  ADDITIONAL_CONTEXT="$SUMMARY_BLOCK"
fi

# Build and emit the hook output JSON
# All string content goes through jq --arg to ensure safe escaping
HOOK_OUTPUT=$(jq -n \
  --arg ctx "$ADDITIONAL_CONTEXT" \
  '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}')

emit_json "$HOOK_OUTPUT"

# Cache the context for fast /clear reloads
jq -n --arg ctx "$ADDITIONAL_CONTEXT" '{"additionalContext": $ctx}' > "$CACHED_CONTEXT_FILE" 2>/dev/null

# Persist session state for delta-loading on next session
PROJECT_NAME=$(get_project_name "$CWD" | awk '{print $1}')
if [ "${#_LOADED_FILES[@]}" -gt 0 ]; then
  write_session_state "$PROJECT_NAME" "${_LOADED_FILES[@]}"
else
  write_session_state "$PROJECT_NAME"
fi

# Signal to downstream hooks that brain has loaded
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  printf '%s\n' "BRAIN_LOADED=1" >> "$CLAUDE_ENV_FILE"
fi

# Log session start
ENTRY_COUNT="${#_LOADED_FILES[@]}"
brain_log_error "SessionStart" "Brain context loaded (source: $SOURCE, entries: $ENTRY_COUNT, project: $PROJECT_NAME)"

exit 0
