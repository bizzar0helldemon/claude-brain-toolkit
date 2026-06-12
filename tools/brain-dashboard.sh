#!/usr/bin/env bash
# brain-dashboard.sh — Brain Dashboard TUI
#
# A single entry point for the whole brain system:
#   • Launch a project → opens a NEW terminal window cd'd into the project
#     with a brain-mode Claude session running
#   • Game night, vault search, vault health, quick capture
#
# Dependencies: fzf (required), kitty (preferred terminal; falls back to
# gnome-terminal / alacritty / konsole / x-terminal-emulator).
#
# Usage:
#   brain                 → dashboard
#   brain here            → skip menu, start brain-mode session in $PWD
#   brain <query...>      → skip menu, search the vault
#
# Project registry: $BRAIN_PATH/brain-mode/projects.tsv  (name<TAB>path)
# Auto-discovery:   git repos one level under $BRAIN_PROJECT_DIRS
#                   (default: ~/Documents ~/projects ~/dev ~/code)

set -u

# ── Preconditions ────────────────────────────────────────────────
if [ -z "${BRAIN_PATH:-}" ] || [ ! -d "${BRAIN_PATH:-}" ]; then
  echo "BRAIN_PATH is not set (or vault missing). Run /brain-setup inside Claude Code." >&2
  exit 1
fi
if ! command -v fzf >/dev/null 2>&1; then
  echo "fzf is required for the dashboard. Install it (e.g. sudo apt install fzf)." >&2
  exit 1
fi

REGISTRY="$BRAIN_PATH/brain-mode/projects.tsv"
SCAN_DIRS="${BRAIN_PROJECT_DIRS:-$HOME/Documents $HOME/projects $HOME/dev $HOME/code}"
LAUNCH_DIR="$PWD"

# ── Locate brain-search tool ─────────────────────────────────────
find_search_tool() {
  for CAND in "$HOME/.claude/tools/brain-search" \
              "$(dirname "$0")/brain-search" \
              "$(dirname "$BRAIN_PATH")/claude-brain-toolkit/tools/brain-search"; do
    if [ -x "$CAND" ]; then printf '%s' "$CAND"; return 0; fi
  done
  return 1
}

# ── New-terminal launcher ────────────────────────────────────────
# launch_terminal <dir> <command...>  — opens a new window at <dir> running
# <command>, leaving an interactive shell behind when the command exits.
launch_terminal() {
  local dir="$1"; shift
  local cmd="$*"
  local wrapped="cd '$dir' && $cmd; exec \${SHELL:-bash}"

  if command -v kitty >/dev/null 2>&1; then
    kitty --detach --directory "$dir" "${SHELL:-bash}" -ic "$cmd; exec ${SHELL:-bash}" &
  elif command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --working-directory="$dir" -- bash -ic "$cmd; exec bash" &
  elif command -v alacritty >/dev/null 2>&1; then
    alacritty --working-directory "$dir" -e bash -ic "$cmd; exec bash" &
  elif command -v konsole >/dev/null 2>&1; then
    konsole --workdir "$dir" -e bash -ic "$cmd; exec bash" &
  elif command -v x-terminal-emulator >/dev/null 2>&1; then
    (cd "$dir" && x-terminal-emulator -e bash -ic "$cmd; exec bash" &)
  else
    echo "No supported terminal emulator found — running here instead."
    (cd "$dir" && eval "$cmd")
    return
  fi
  disown 2>/dev/null || true
  echo "  ↗ Launched in new window: $dir"
}

# ── Project list: registry + auto-discovered git repos ───────────
project_list() {
  {
    if [ -f "$REGISTRY" ]; then
      grep -v '^\s*#' "$REGISTRY" | grep -v '^\s*$'
    fi
    for base in $SCAN_DIRS; do
      [ -d "$base" ] || continue
      for gitdir in "$base"/*/.git; do
        [ -e "$gitdir" ] || continue
        local proj_dir proj_name
        proj_dir="$(dirname "$gitdir")"
        proj_name="$(basename "$proj_dir")"
        printf '%s\t%s\n' "$proj_name" "$proj_dir"
      done
    done
  } | awk -F'\t' '!seen[$2]++' | sort -f
}

# ── Actions ──────────────────────────────────────────────────────
# Project/game launches run in dangerous mode (skip permission prompts) —
# you only launch trusted directories from your own registry.
# NOTE: flag order matters — `--agent` is silently ignored if it comes
# AFTER --dangerously-skip-permissions (see vault: CLI Flag Ordering Sensitivity).
BRAIN_CMD="claude --agent brain-mode --dangerously-skip-permissions"

do_launch_project() {
  local pick
  pick=$(project_list | awk -F'\t' '{printf "%-32s %s\n", $1, $2}' | \
         fzf --height=60% --reverse --prompt="project ▸ " \
             --header="Select a project — opens a new window with a brain session") || return
  local dir
  dir=$(printf '%s' "$pick" | awk '{print $NF}')
  [ -d "$dir" ] || { echo "  ! Directory not found: $dir"; return; }
  launch_terminal "$dir" "$BRAIN_CMD"
}

do_brain_here() {
  cd "$LAUNCH_DIR" && exec claude --agent brain-mode
}

do_game_night() {
  local game
  game=$(printf '%s\n' \
      "🗡  Resume Neural Archive quest (Act 2 awaits)" \
      "🧩 Swap riddles" \
      "📰 Co-operative crosswords" \
      "🔗 Word association" \
      "❓ Twenty questions" \
      "📖 Collaborative storytelling" \
      "🧙 A wizard approaches you in the tavern (RPG)" \
      "🎲 Surprise me" | \
    fzf --height=50% --reverse --prompt="game ▸ " --header="AI Fluency Game Night") || return
  local prompt="/brain-game ${game#* }"
  launch_terminal "$BRAIN_PATH" "$BRAIN_CMD '$prompt'"
}

do_search() {
  local tool query
  tool=$(find_search_tool) || { echo "  ! brain-search tool not found."; read -rp "  [enter] "; return; }
  read -rp "  search ▸ " query
  [ -n "$query" ] || return
  "$tool" "$query" --limit 10 | "${PAGER:-less -R}"
}

do_health() {
  echo ""
  echo "  📊 Vault health — $BRAIN_PATH"
  echo "  ─────────────────────────────────────────"
  printf "  %-22s %s\n" "Total entries:" "$(find "$BRAIN_PATH" -name '*.md' -not -path '*/.*' 2>/dev/null | wc -l)"
  printf "  %-22s %s\n" "Learnings:" "$(find "$BRAIN_PATH/learnings" -name '*.md' 2>/dev/null | wc -l)"
  printf "  %-22s %s\n" "Prompts/patterns:" "$(find "$BRAIN_PATH/prompts" -name '*.md' 2>/dev/null | wc -l)"
  printf "  %-22s %s\n" "Daily notes:" "$(find "$BRAIN_PATH/daily_notes" -name '*.md' 2>/dev/null | wc -l)"
  printf "  %-22s %s\n" "Newest daily note:" "$(ls -1 "$BRAIN_PATH/daily_notes" 2>/dev/null | sort | tail -1)"
  printf "  %-22s %s\n" "Error patterns:" "$(jq '.patterns | length' "$BRAIN_PATH/brain-mode/pattern-store.json" 2>/dev/null || echo 0)"
  printf "  %-22s %s\n" "Retrievals logged:" "$(wc -l < "$BRAIN_PATH/brain-mode/retrieval-log.jsonl" 2>/dev/null || echo 0)"
  printf "  %-22s %s\n" "Inbox items:" "$(grep -c '^- ' "$BRAIN_PATH/inbox/quick-capture.md" 2>/dev/null || echo 0)"
  if git -C "$BRAIN_PATH" rev-parse --git-dir >/dev/null 2>&1; then
    printf "  %-22s %s dirty file(s)\n" "Vault git:" "$(git -C "$BRAIN_PATH" status --porcelain | wc -l)"
  fi
  echo ""
  echo "  For the full audit (broken links, cold storage): /brain-audit inside a session"
  read -rp "  [enter] "
}

do_capture() {
  local note ts
  read -rp "  capture ▸ " note
  [ -n "$note" ] || return
  ts="$(date '+%Y-%m-%d %H:%M')"
  mkdir -p "$BRAIN_PATH/inbox"
  if [ ! -f "$BRAIN_PATH/inbox/quick-capture.md" ]; then
    printf -- '---\ntitle: "Quick Capture Inbox"\ntype: index\ntags: [inbox, quick-capture]\n---\n\n# Quick Capture Inbox\n\n' > "$BRAIN_PATH/inbox/quick-capture.md"
  fi
  printf -- '- %s — %s\n' "$ts" "$note" >> "$BRAIN_PATH/inbox/quick-capture.md"
  echo "  ✓ captured to inbox/quick-capture.md"
}

do_register() {
  local dir name
  read -rp "  project path [$LAUNCH_DIR] ▸ " dir
  dir="${dir:-$LAUNCH_DIR}"
  dir="$(cd "$dir" 2>/dev/null && pwd)" || { echo "  ! Not a directory."; return; }
  read -rp "  display name [$(basename "$dir")] ▸ " name
  name="${name:-$(basename "$dir")}"
  mkdir -p "$(dirname "$REGISTRY")"
  if grep -qF "	$dir" "$REGISTRY" 2>/dev/null; then
    echo "  ~ already registered."
  else
    printf '%s\t%s\n' "$name" "$dir" >> "$REGISTRY"
    echo "  ✓ registered: $name → $dir"
  fi
}

# ── Direct modes ─────────────────────────────────────────────────
if [ "${1:-}" = "here" ]; then do_brain_here; fi
if [ $# -gt 0 ]; then
  TOOL=$(find_search_tool) && exec "$TOOL" "$*" --limit 10
  echo "brain-search tool not found." >&2; exit 1
fi

# ── Main menu loop ───────────────────────────────────────────────
while true; do
  CHOICE=$(printf '%s\n' \
      "🚀 Launch project          — new window, brain session in project dir" \
      "🧠 Brain session here      — start claude brain-mode in $LAUNCH_DIR" \
      "🎮 Game night              — riddles, crosswords, Neural Archive quest" \
      "🔍 Search vault            — full-text + semantic search" \
      "📊 Vault health            — quick stats snapshot" \
      "⚡ Quick capture           — drop a note into the inbox" \
      "➕ Register project        — add a directory to the launcher" \
      "🚪 Quit" | \
    fzf --height=60% --reverse --prompt="🧠 brain ▸ " \
        --header="Brain Dashboard — $(basename "$BRAIN_PATH")") || exit 0

  case "$CHOICE" in
    🚀*) do_launch_project ;;
    🧠*) do_brain_here ;;
    🎮*) do_game_night ;;
    🔍*) do_search ;;
    📊*) do_health ;;
    ⚡*) do_capture ;;
    ➕*) do_register ;;
    🚪*) exit 0 ;;
  esac
done
