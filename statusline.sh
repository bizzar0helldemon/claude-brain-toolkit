#!/bin/bash
# 🧠 Brain Mode Status Line
# Two-row branded status bar for Claude Code brain-mode sessions.
# Reads JSON payload from stdin, outputs formatted lines.

input=$(cat 2>/dev/null || echo "{}")

# ── JSON extraction ──────────────────────────────────────────────
MODEL=$(echo "$input" | jq -r '.model.display_name // "Claude"')
AGENT=$(echo "$input" | jq -r '.agent.name // ""')
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // "."')

# ── Non-brain-mode fallback ─────────────────────────────────────
if [ "$AGENT" != "brain-mode" ]; then
  printf '[%s] %s%%\n' "$MODEL" "$PCT"
  exit 0
fi

# ── Colors (256-color) ───────────────────────────────────────────
use_color=1
[ -n "$NO_COLOR" ] && use_color=0

c() { [ "$use_color" -eq 1 ] && printf "\033[38;5;${1}m"; }
cb() { [ "$use_color" -eq 1 ] && printf "\033[1;38;5;${1}m"; }
rst() { [ "$use_color" -eq 1 ] && printf '\033[0m'; }

CYAN=117     # Brain brand
PURPLE=183   # model color
GREEN=114    # additions / good
YELLOW=221   # warning
RED=203      # danger / removals
DIM=245      # separators
WHITE=255    # neutral text
BLUE=75      # worktree indicator

# ── Repo name ────────────────────────────────────────────────────
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -n "$REPO_ROOT" ]; then
  REPO_NAME=$(basename "$REPO_ROOT")
else
  REPO_NAME=$(basename "$CWD")
fi

# ── Worktree detection ──────────────────────────────────────────
IN_WORKTREE=0
if [ -n "$REPO_ROOT" ]; then
  GIT_DIR=$(git -C "$CWD" rev-parse --git-dir 2>/dev/null || echo "")
  if [ -f "$REPO_ROOT/.git" ] || [[ "$GIT_DIR" == *"/worktrees/"* ]]; then
    IN_WORKTREE=1
  fi
fi

# ── Git info ─────────────────────────────────────────────────────
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
GIT_INDICATOR=""

if [ -n "$BRANCH" ]; then
  if git -C "$CWD" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    AHEAD=$(git -C "$CWD" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
    BEHIND=$(git -C "$CWD" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
    [ "$AHEAD" -gt 0 ] && GIT_INDICATOR+=" ↑${AHEAD}"
    [ "$BEHIND" -gt 0 ] && GIT_INDICATOR+=" ↓${BEHIND}"
  fi

  if ! git -C "$CWD" diff --quiet 2>/dev/null || \
     ! git -C "$CWD" diff --cached --quiet 2>/dev/null; then
    GIT_INDICATOR+=" *"
  elif [ -n "$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null | head -1)" ]; then
    GIT_INDICATOR+=" +"
  fi
else
  BRANCH="detached"
fi

# ── Git dirty file count ────────────────────────────────────────
DIRTY_COUNT=0
if [ -n "$REPO_ROOT" ]; then
  STAGED=$(git -C "$CWD" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  MODIFIED=$(git -C "$CWD" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
  UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  DIRTY_COUNT=$((STAGED + MODIFIED + UNTRACKED))
fi

# ── Brain state ──────────────────────────────────────────────────
BRAIN_STATE="no-vault"
if [ -n "${BRAIN_PATH:-}" ]; then
  if [ -f "$BRAIN_PATH/.brain-state" ]; then
    BRAIN_STATE=$(cut -d' ' -f1 "$BRAIN_PATH/.brain-state" 2>/dev/null || echo "idle")
  else
    BRAIN_STATE="idle"
  fi
fi

# ── Context bar (10 segments, color-coded) ───────────────────────
[ -z "$PCT" ] || [ "$PCT" = "null" ] && PCT=0
FILLED=$((PCT * 10 / 100))
[ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$((10 - FILLED))

if [ "$PCT" -lt 40 ]; then
  BAR_CLR=$GREEN
elif [ "$PCT" -lt 70 ]; then
  BAR_CLR=$YELLOW
else
  BAR_CLR=$RED
fi

BAR="$(c $BAR_CLR)"
for ((i=0; i<FILLED; i++)); do BAR+="▓"; done
BAR+="$(c $DIM)"
for ((i=0; i<EMPTY; i++)); do BAR+="░"; done
BAR+="$(rst)"

# ── Duration ─────────────────────────────────────────────────────
MINS=$((DURATION_MS / 60000))
if [ "$MINS" -ge 60 ]; then
  HRS=$((MINS / 60))
  RMIN=$((MINS % 60))
  TIME_STR="${HRS}h${RMIN}m"
else
  TIME_STR="${MINS}m"
fi

# ── Separator ────────────────────────────────────────────────────
S="$(c $DIM) │ $(rst)"

# ── Render — Row 1: Identity ─────────────────────────────────────
# Brand mark
printf '%s🧠 Brain%s' "$(cb $CYAN)" "$(rst)"
printf '%s' "$S"

# Repo + branch
printf '📂 %s%s%s' "$(c $WHITE)" "$REPO_NAME" "$(rst)"
if [ "$IN_WORKTREE" -eq 1 ]; then
  printf '  🌳 %s%s%s' "$(c $BLUE)" "$BRANCH" "$(rst)"
else
  printf '  🌿 %s%s%s' "$(c $CYAN)" "$BRANCH" "$(rst)"
fi
[ -n "$GIT_INDICATOR" ] && printf '%s%s%s' "$(c $YELLOW)" "$GIT_INDICATOR" "$(rst)"
printf '%s' "$S"

# Model
printf '🤖 %s%s%s' "$(c $PURPLE)" "$MODEL" "$(rst)"

printf '\n'

# ── Render — Row 2: State + metrics ─────────────────────────────
# Brain state badge
case "$BRAIN_STATE" in
  captured)
    printf '%s🟢 captured%s' "$(c $GREEN)" "$(rst)"
    ;;
  error)
    printf '%s🔴 error%s' "$(c $RED)" "$(rst)"
    ;;
  no-vault)
    printf '%s⚠ no vault%s' "$(c $YELLOW)" "$(rst)"
    ;;
  *)
    printf '%s● idle%s' "$(c $DIM)" "$(rst)"
    ;;
esac
printf '%s' "$S"

# Context bar
printf '%s %s%%' "$BAR" "$PCT"
printf '%s' "$S"

# Lines changed
printf '%s+%s%s %s-%s%s' "$(c $GREEN)" "$LINES_ADDED" "$(rst)" "$(c $RED)" "$LINES_REMOVED" "$(rst)"
printf '%s' "$S"

# Dirty files
if [ "$DIRTY_COUNT" -gt 0 ]; then
  printf '📝 %s%s%s' "$(c $YELLOW)" "$DIRTY_COUNT" "$(rst)"
else
  printf '📝 %s0%s' "$(c $DIM)" "$(rst)"
fi
printf '%s' "$S"

# Duration
printf '⏱ %s%s%s' "$(c $WHITE)" "$TIME_STR" "$(rst)"
printf '\n'
