#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  # Validation already emitted dual-channel error — just exit non-blocking
  exit 1
fi

# Source brain-context library — provides get_project_name for fast-path
# project-match check. Sourcing is side-effect-free (function defs + module vars).
source ~/.claude/hooks/lib/brain-context.sh

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
  CURRENT_PROJECT=$(get_project_name "$CWD" | awk '{print $1}')

  if [ -f "$CACHED_CONTEXT_FILE" ]; then
    CACHED_PROJECT=$(jq -r '.project // empty' "$CACHED_CONTEXT_FILE" 2>/dev/null)
    CACHED_CONTEXT=$(jq -r '.additionalContext // empty' "$CACHED_CONTEXT_FILE" 2>/dev/null)

    # Serve from cache only when the cache was stamped with the current project.
    # Legacy caches (no project field) are treated as untrusted — fall through.
    if [ -n "$CACHED_CONTEXT" ] && [ -n "$CACHED_PROJECT" ] && [ "$CACHED_PROJECT" = "$CURRENT_PROJECT" ]; then
      HOOK_OUTPUT=$(jq -n \
        --arg ctx "$CACHED_CONTEXT" \
        '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}')
      emit_json "$HOOK_OUTPUT"

      if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
        printf '%s\n' "BRAIN_LOADED=1" >> "$CLAUDE_ENV_FILE"
      fi

      brain_log_error "SessionStart" "Fast reload from cache (source: clear, project: $CURRENT_PROJECT)"
      exit 0
    fi

    # Project mismatch or legacy cache — log and fall through to minimal emit below.
    # Don't run the full path: /clear is meant to stay instant.
    if [ -n "$CACHED_PROJECT" ] && [ "$CACHED_PROJECT" != "$CURRENT_PROJECT" ]; then
      brain_log_error "SessionStart" \
        "Cache project mismatch (cached=$CACHED_PROJECT, current=$CURRENT_PROJECT) — emitting minimal context"
    elif [ -z "$CACHED_PROJECT" ] && [ -n "$CACHED_CONTEXT" ]; then
      brain_log_error "SessionStart" \
        "Legacy cache without project field — emitting minimal context (will restamp on next startup)"
    fi
  fi

  # No usable cache for this project — emit minimal context so /clear stays instant.
  # The cache will be rebuilt with a project stamp on the next full startup.
  MINIMAL_CTX="Brain: /clear (no cache for $CURRENT_PROJECT yet — full context loads on next startup)"
  HOOK_OUTPUT=$(jq -n \
    --arg ctx "$MINIMAL_CTX" \
    '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}')
  emit_json "$HOOK_OUTPUT"

  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    printf '%s\n' "BRAIN_LOADED=1" >> "$CLAUDE_ENV_FILE"
  fi

  brain_log_error "SessionStart" "Fast /clear with no usable cache for $CURRENT_PROJECT — emitted minimal context"
  exit 0
fi

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

# Resolve project name once for both cache stamp and session state below.
PROJECT_NAME=$(get_project_name "$CWD" | awk '{print $1}')

# Cache the context for fast /clear reloads. Stamp with project + cwd so the
# fast path can verify the cache belongs to the current project (see BTK-1).
jq -n \
  --arg ctx "$ADDITIONAL_CONTEXT" \
  --arg project "$PROJECT_NAME" \
  --arg cwd "$CWD" \
  '{additionalContext: $ctx, project: $project, cwd: $cwd, cached_at: now}' \
  > "$CACHED_CONTEXT_FILE" 2>/dev/null

# Persist session state for delta-loading on next session
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
