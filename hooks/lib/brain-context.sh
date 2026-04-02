# hooks/lib/brain-context.sh
# Sourced library — do NOT execute directly. Source with: source hooks/lib/brain-context.sh
#
# Provides: vault query, token budgeting, project matching, session state, summary block
# Depends on: brain-path.sh (must be sourced first — provides brain_log_error, emit_json)
# Compatible with: bash 3.2+, zsh 5.0+
# All output uses printf (not echo) for portability.

# Source brain-path.sh if not already sourced (idempotent)
if ! command -v brain_log_error >/dev/null 2>&1; then
  _BRAIN_CONTEXT_SELFDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
  # shellcheck source=brain-path.sh
  source "${_BRAIN_CONTEXT_SELFDIR}/brain-path.sh"
fi

# ------------------------------------------------------------------------------
# Module-level state tracking (populated by build_brain_context)
# ------------------------------------------------------------------------------
_LOADED_FILES=()
_PROJECT_COUNT=0
_PITFALL_COUNT=0
_GLOBAL_ACTIVE=false
_NEWEST_MTIME=0
_TTOK_WARNED=false

# ------------------------------------------------------------------------------
# get_frontmatter_field <field> <file>
#
# Extract a simple `key: value` YAML frontmatter field from a markdown file.
# Handles first `---` as opening delimiter.
#
# Args:
#   $1 — field name (e.g., "project", "type", "tags")
#   $2 — path to markdown file
# Output: field value (stdout), empty string if not found
# ------------------------------------------------------------------------------
get_frontmatter_field() {
  local field="$1"
  local file="$2"

  if [ ! -f "$file" ]; then
    return 1
  fi

  awk '/^---/{found++; next} found==1{print} found==2{exit}' "$file" \
    | grep "^${field}:" \
    | head -1 \
    | sed "s/^${field}:[[:space:]]*//" \
    | tr -d '"'"'" \
    | tr -d '\r'
}

# ------------------------------------------------------------------------------
# get_mtime <file>
#
# Get file modification time as Unix timestamp.
# Tries GNU stat, BSD stat, then date -r fallback.
#
# Args:
#   $1 — path to file
# Output: Unix timestamp (stdout), 0 on failure
# ------------------------------------------------------------------------------
get_mtime() {
  local file="$1"
  local mtime

  if [ ! -f "$file" ]; then
    printf '%s' "0"
    return 0
  fi

  # GNU stat (Linux, Git Bash on Windows)
  mtime=$(stat -c '%Y' "$file" 2>/dev/null)
  if [ -n "$mtime" ]; then
    printf '%s' "$mtime"
    return 0
  fi

  # BSD stat (macOS)
  mtime=$(stat -f '%m' "$file" 2>/dev/null)
  if [ -n "$mtime" ]; then
    printf '%s' "$mtime"
    return 0
  fi

  # date -r fallback
  mtime=$(date -r "$file" +%s 2>/dev/null)
  if [ -n "$mtime" ]; then
    printf '%s' "$mtime"
    return 0
  fi

  brain_log_error "get_mtime" "Could not determine mtime for: $file"
  printf '%s' "0"
}

# ------------------------------------------------------------------------------
# get_project_name <cwd>
#
# Get canonical project name candidates (space-separated).
# Primary: git repo root basename. Secondary: git remote repo name.
# Fallback: basename of cwd.
#
# Args:
#   $1 — current working directory
# Output: space-separated project name candidates (stdout)
# ------------------------------------------------------------------------------
get_project_name() {
  local cwd="$1"
  local candidates=""

  # Try git repo root basename
  local repo_root
  repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo_root" ]; then
    local repo_name
    repo_name=$(basename "$repo_root")
    candidates="$repo_name"

    # Add suffix-stripped variant (e.g. "homunculus-dev" → "homunculus")
    local stripped
    stripped=$(printf '%s' "$repo_name" | sed 's/-\(dev\|app\|api\|web\|cli\|srv\|server\|client\|frontend\|backend\|mono\|core\)$//')
    if [ -n "$stripped" ] && [ "$stripped" != "$repo_name" ]; then
      candidates="$candidates $stripped"
    fi

    # Also try remote origin name as secondary candidate
    local remote_url
    remote_url=$(git -C "$cwd" remote get-url origin 2>/dev/null)
    if [ -n "$remote_url" ]; then
      local remote_name
      remote_name=$(printf '%s' "$remote_url" \
        | sed 's/.*[:/]\([^/]*\)\.git$/\1/' \
        | sed 's/.*[:/]\([^/]*\)$/\1/')
      if [ -n "$remote_name" ] && [ "$remote_name" != "$repo_name" ]; then
        candidates="$candidates $remote_name"
      fi
    fi
  fi

  # Fallback to cwd basename if no git repo
  if [ -z "$candidates" ]; then
    candidates=$(basename "$cwd")
  fi

  printf '%s' "$candidates"
}

# ------------------------------------------------------------------------------
# count_tokens <text>
#
# Count approximate token count for text.
# Uses ttok if available, falls back to char heuristic (chars / 4).
#
# Args:
#   $1 — text to count tokens for
# Output: integer token count (stdout)
# ------------------------------------------------------------------------------
count_tokens() {
  local text="$1"

  if command -v ttok >/dev/null 2>&1; then
    local count
    count=$(printf '%s' "$text" | ttok 2>/dev/null)
    if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
      printf '%s' "$count"
      return 0
    fi
  fi

  # Fallback: char count / 4 heuristic
  if [ "$_TTOK_WARNED" = "false" ]; then
    brain_log_error "count_tokens" "ttok not available — using char/4 heuristic for token counting"
    _TTOK_WARNED=true
  fi

  local chars
  chars=$(printf '%s' "$text" | wc -c | awk '{print $1}')
  printf '%s' "$(( chars / 4 ))"
}

# ------------------------------------------------------------------------------
# entry_matches_project <file> <project_candidates>
#
# Check if a vault file's frontmatter `project:` field matches any of the
# space-separated project candidates.
#
# Args:
#   $1 — path to vault markdown file
#   $2 — space-separated project name candidates
# Return: 0 if match, 1 if no match
# ------------------------------------------------------------------------------
entry_matches_project() {
  local file="$1"
  local candidates="$2"

  local entry_project
  entry_project=$(get_frontmatter_field "project" "$file")

  # Empty project field = no match via frontmatter
  if [ -z "$entry_project" ]; then
    return 1
  fi

  local candidate
  for candidate in $candidates; do
    # Exact match
    if [ "$entry_project" = "$candidate" ]; then
      return 0
    fi
    # Fuzzy: candidate contains the project value (e.g. "homunculus-dev" contains "homunculus")
    if printf '%s' "$candidate" | grep -qi "^${entry_project}" 2>/dev/null; then
      return 0
    fi
    # Fuzzy: project value contains the candidate
    if printf '%s' "$entry_project" | grep -qi "^${candidate}" 2>/dev/null; then
      return 0
    fi
  done

  return 1
}

# ------------------------------------------------------------------------------
# _matches_project_directory <file> <project_candidates>
#
# Check if a vault file lives under a directory whose name fuzzy-matches any
# project candidate. Handles vaults organized by folder without frontmatter.
# E.g., $BRAIN_PATH/homunculus/notes.md matches candidate "homunculus-dev".
#
# Args:
#   $1 — path to vault markdown file
#   $2 — space-separated project name candidates
# Return: 0 if match, 1 if no match
# ------------------------------------------------------------------------------
_matches_project_directory() {
  local file="$1"
  local candidates="$2"

  # Get the file's path relative to BRAIN_PATH
  local rel_path="${file#"${BRAIN_PATH}"/}"

  # Get the first directory component (top-level vault folder)
  local top_dir="${rel_path%%/*}"

  # If file is at vault root (no subdirectory), no directory match
  if [ "$top_dir" = "$rel_path" ]; then
    return 1
  fi

  # Skip common non-project directories
  case "$top_dir" in
    brain-mode|preferences|frameworks|templates|intake|daily_notes|inbox)
      return 1
      ;;
  esac

  local candidate
  for candidate in $candidates; do
    # Exact match
    if [ "$top_dir" = "$candidate" ]; then
      return 0
    fi
    # Fuzzy: candidate starts with dir name (e.g. "homunculus-dev" starts with "homunculus")
    if printf '%s' "$candidate" | grep -qi "^${top_dir}" 2>/dev/null; then
      return 0
    fi
    # Fuzzy: dir name starts with candidate
    if printf '%s' "$top_dir" | grep -qi "^${candidate}" 2>/dev/null; then
      return 0
    fi
  done

  return 1
}

# ------------------------------------------------------------------------------
# _is_global_entry <file>
#
# Check if a vault file is a global/preference entry.
# Matches: type: preference, type: global, or file is in a preferences/ subdir.
#
# Args:
#   $1 — path to vault markdown file
# Return: 0 if global, 1 if not
# ------------------------------------------------------------------------------
_is_global_entry() {
  local file="$1"

  local entry_type
  entry_type=$(get_frontmatter_field "type" "$file")

  if [ "$entry_type" = "preference" ] || [ "$entry_type" = "global" ]; then
    return 0
  fi

  # Check if file is in a preferences/ subdirectory
  if printf '%s' "$file" | grep -q '/preferences/'; then
    return 0
  fi

  return 1
}

# ------------------------------------------------------------------------------
# _is_pitfall_entry <file>
#
# Check if a vault file is a pitfall entry.
#
# Args:
#   $1 — path to vault markdown file
# Return: 0 if pitfall, 1 if not
# ------------------------------------------------------------------------------
_is_pitfall_entry() {
  local file="$1"

  local entry_type
  entry_type=$(get_frontmatter_field "type" "$file")

  if [ "$entry_type" = "pitfall" ]; then
    return 0
  fi

  # Check tags for pitfall
  local tags
  tags=$(get_frontmatter_field "tags" "$file")
  if printf '%s' "$tags" | grep -q 'pitfall'; then
    return 0
  fi

  return 1
}

# ------------------------------------------------------------------------------
# collect_vault_entries <cwd>
#
# Walk $BRAIN_PATH/ recursively for .md files. Collect project-specific entries
# (matching project candidates) and global entries. Sort project entries by
# mtime descending. Print file paths to stdout, project entries first.
#
# Args:
#   $1 — current working directory
# Output: file paths (stdout), one per line
# ------------------------------------------------------------------------------
collect_vault_entries() {
  local cwd="$1"

  if [ ! -d "${BRAIN_PATH:-}" ]; then
    return 1
  fi

  local project_candidates
  project_candidates=$(get_project_name "$cwd")

  # Collect entries into temp arrays
  local project_entries=()
  local dir_matched_entries=()
  local global_entries=()

  # Max directory-matched entries to prevent performance issues with large vaults.
  # Frontmatter-matched entries are always included (no cap).
  local max_dir_entries=25

  # Find all .md files, skip hidden files/dirs and special brain files
  while IFS= read -r -d '' file; do
    # Skip files starting with dot (hidden)
    local basename_file
    basename_file=$(basename "$file")
    if printf '%s' "$basename_file" | grep -q '^\.' ; then
      continue
    fi

    # Skip special brain management files
    if [ "$basename_file" = ".brain-session-state.json" ] || [ "$basename_file" = ".brain-errors.log" ]; then
      continue
    fi

    # Skip hidden directory paths
    if printf '%s' "$file" | grep -q '/\.' ; then
      continue
    fi

    if entry_matches_project "$file" "$project_candidates"; then
      # Frontmatter match — always include (highest confidence)
      project_entries+=("$file")
    elif _matches_project_directory "$file" "$project_candidates"; then
      # Directory match — collect separately for capping
      dir_matched_entries+=("$file")
    elif _is_global_entry "$file"; then
      global_entries+=("$file")
    fi

  done < <(find "$BRAIN_PATH" -name "*.md" -not -name ".*" -print0 2>/dev/null)

  # For directory-matched entries, prefer shallow files (depth 1 in project dir)
  # then cap to max_dir_entries newest files. This avoids ingesting hundreds of
  # auto-generated code-notes/library-notes while keeping meaningful project files.
  if [ "${#dir_matched_entries[@]}" -gt "$max_dir_entries" ]; then
    # Separate shallow (depth 1) from deep entries
    local shallow=()
    local deep=()
    local dm
    for dm in "${dir_matched_entries[@]}"; do
      local rel="${dm#"${BRAIN_PATH}"/}"
      # Count path separators: project/file.md = 1 sep (shallow), project/sub/file.md = 2+ (deep)
      local sep_count
      sep_count=$(printf '%s' "$rel" | tr -cd '/' | wc -c | awk '{print $1}')
      if [ "$sep_count" -le 1 ]; then
        shallow+=("$dm")
      else
        deep+=("$dm")
      fi
    done

    # Take all shallow entries, fill remaining cap from deep entries (newest first)
    dir_matched_entries=()
    for dm in "${shallow[@]}"; do
      dir_matched_entries+=("$dm")
    done
    local remaining=$(( max_dir_entries - ${#dir_matched_entries[@]} ))
    if [ "$remaining" -gt 0 ] && [ "${#deep[@]}" -gt 0 ]; then
      # Sort deep entries by mtime, take newest $remaining
      local deep_sorted=""
      for dm in "${deep[@]}"; do
        local dmt
        dmt=$(get_mtime "$dm")
        deep_sorted="${deep_sorted}${dmt}	${dm}"$'\n'
      done
      local count=0
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        local path_part="${line#*	}"
        dir_matched_entries+=("$path_part")
        count=$(( count + 1 ))
        [ "$count" -ge "$remaining" ] && break
      done < <(printf '%s' "$deep_sorted" | sort -rn -t$'\t' -k1)
    fi
  fi

  # Split directory-matched entries into shallow (depth 1) vs deep for tiered output
  local dir_shallow=()
  local dir_deep=()
  for dm in "${dir_matched_entries[@]}"; do
    local rel="${dm#"${BRAIN_PATH}"/}"
    local sep_count
    sep_count=$(printf '%s' "$rel" | tr -cd '/' | wc -c | awk '{print $1}')
    if [ "$sep_count" -le 1 ]; then
      dir_shallow+=("$dm")
    else
      dir_deep+=("$dm")
    fi
  done

  # Output in 3 priority tiers (each sorted by mtime descending):
  #   Tier 1: Frontmatter-matched (highest confidence — explicit project: field)
  #   Tier 2: Shallow directory-matched (top-level project files: handoffs, identity, etc.)
  #   Tier 3: Deep directory-matched (subdirectory files: code-notes, library-notes, etc.)
  # Token budget in build_brain_context naturally caps total loaded content,
  # so higher tiers get priority.
  local _tier_name
  for _tier_name in frontmatter dir_shallow dir_deep; do
    local _tier_arr=()
    case "$_tier_name" in
      frontmatter) _tier_arr=("${project_entries[@]}") ;;
      dir_shallow) _tier_arr=("${dir_shallow[@]}") ;;
      dir_deep)    _tier_arr=("${dir_deep[@]}") ;;
    esac

    if [ "${#_tier_arr[@]}" -gt 0 ]; then
      local sort_input=""
      local f
      for f in "${_tier_arr[@]}"; do
        local mt
        mt=$(get_mtime "$f")
        sort_input="${sort_input}${mt}	${f}"$'\n'
      done
      printf '%s' "$sort_input" | sort -rn -t$'\t' -k1 | cut -f2
    fi
  done

  # Global entries (unsorted — order is stable)
  local gf
  for gf in "${global_entries[@]}"; do
    printf '%s\n' "$gf"
  done
}

# ------------------------------------------------------------------------------
# load_brain_md <cwd>
#
# Load .brain.md from project root (git root or cwd). Caps at 500 tokens.
#
# Args:
#   $1 — current working directory
# Output: .brain.md content (stdout), empty if not found
# ------------------------------------------------------------------------------
load_brain_md() {
  local cwd="$1"

  # Find project root
  local project_root
  project_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$project_root" ]; then
    project_root="$cwd"
  fi

  local brain_md="${project_root}/.brain.md"
  if [ ! -f "$brain_md" ]; then
    return 0
  fi

  local content
  content=$(cat "$brain_md")

  local token_count
  token_count=$(count_tokens "$content")

  if [ "$token_count" -gt 500 ]; then
    brain_log_error "load_brain_md" ".brain.md exceeds 500 token limit ($token_count tokens) — truncating"
    # Truncate: approximate 500 tokens ~ 2000 chars
    content=$(printf '%s' "$content" | head -c 2000)
    content="${content}"$'\n'"[.brain.md truncated — 500 token limit]"
  fi

  printf '%s' "$content"
}

# ------------------------------------------------------------------------------
# is_entry_new_or_changed <file>
#
# Check if file is new or has changed since last session state.
# Reads $BRAIN_PATH/.brain-session-state.json.
#
# Args:
#   $1 — path to file
# Return: 0 if new/changed, 1 if unchanged
# ------------------------------------------------------------------------------
is_entry_new_or_changed() {
  local file="$1"
  local state_file="${BRAIN_PATH}/.brain-session-state.json"

  if [ ! -f "$state_file" ]; then
    return 0  # No state = treat everything as new
  fi

  # Read previous mtime for this file from state
  local prev_mtime
  prev_mtime=$(jq -r --arg path "$file" \
    '.entries[] | select(.path == $path) | .mtime' \
    "$state_file" 2>/dev/null)

  if [ -z "$prev_mtime" ] || [ "$prev_mtime" = "null" ]; then
    return 0  # Not in state = new
  fi

  local current_mtime
  current_mtime=$(get_mtime "$file")

  if [ "$current_mtime" != "$prev_mtime" ]; then
    return 0  # Changed
  fi

  return 1  # Unchanged
}

# ------------------------------------------------------------------------------
# build_brain_context <cwd> <source>
#
# Main entry point. Assembles vault context within token budget.
# Resets module-level tracking state before building.
#
# Because this function is typically called via $() (command substitution) which
# spawns a subshell, module-level variables set inside cannot propagate back to
# the parent shell. To work around this, the function writes tracking state to
# a temp file (_BRAIN_CONTEXT_STATE_FILE). The caller must source that file
# after the call to restore _PROJECT_COUNT, _PITFALL_COUNT, _GLOBAL_ACTIVE,
# _NEWEST_MTIME, and _LOADED_FILES in the parent shell.
#
# Usage pattern:
#   _BRAIN_CONTEXT_STATE_FILE=$(mktemp)
#   VAULT_CONTEXT=$(build_brain_context "$CWD" "$SOURCE")
#   source "$_BRAIN_CONTEXT_STATE_FILE"
#   rm -f "$_BRAIN_CONTEXT_STATE_FILE"
#
# Args:
#   $1 — current working directory
#   $2 — source (startup|resume|clear|compact)
# Output: assembled context string (stdout)
# ------------------------------------------------------------------------------
build_brain_context() {
  local cwd="$1"
  local source="${2:-startup}"

  # Reset module-level tracking (local copies — written to state file at end)
  local loaded_files=()
  local project_count=0
  local pitfall_count=0
  local global_active=false
  local newest_mtime=0

  local budget="${BRAIN_TOKEN_BUDGET:-2000}"
  local used_tokens=0
  local assembled=""

  # Load .brain.md outside the vault budget
  local brain_md_content
  brain_md_content=$(load_brain_md "$cwd")

  # Collect vault entries
  local entries=()
  while IFS= read -r line; do
    [ -n "$line" ] && entries+=("$line")
  done < <(collect_vault_entries "$cwd")

  # Accumulate entries within budget
  local entry
  for entry in "${entries[@]}"; do
    # For compact source, only include new/changed entries
    if [ "$source" = "compact" ]; then
      if ! is_entry_new_or_changed "$entry"; then
        continue
      fi
    fi

    local content
    content=$(cat "$entry" 2>/dev/null)
    [ -z "$content" ] && continue

    local entry_tokens
    entry_tokens=$(count_tokens "$content")

    if [ $(( used_tokens + entry_tokens )) -gt "$budget" ]; then
      # Drop this entry — token budget exceeded
      brain_log_error "build_brain_context" "Token budget exceeded, dropping: $(basename "$entry")"
      continue
    fi

    # Add to assembled context
    assembled="${assembled}

--- $(basename "$entry") ---
${content}"
    used_tokens=$(( used_tokens + entry_tokens ))

    # Track metadata
    loaded_files+=("$entry")
    local entry_mtime
    entry_mtime=$(get_mtime "$entry")

    if _is_global_entry "$entry"; then
      global_active=true
    else
      project_count=$(( project_count + 1 ))
      if [ "$entry_mtime" -gt "$newest_mtime" ] 2>/dev/null; then
        newest_mtime="$entry_mtime"
      fi
    fi

    if _is_pitfall_entry "$entry"; then
      pitfall_count=$(( pitfall_count + 1 ))
    fi
  done

  # Prepend .brain.md if present
  if [ -n "$brain_md_content" ]; then
    assembled="--- .brain.md ---
${brain_md_content}
${assembled}"
  fi

  # Write tracking state to state file for parent shell to source
  if [ -n "${_BRAIN_CONTEXT_STATE_FILE:-}" ]; then
    {
      printf '_PROJECT_COUNT=%s\n' "$project_count"
      printf '_PITFALL_COUNT=%s\n' "$pitfall_count"
      printf '_GLOBAL_ACTIVE=%s\n' "$global_active"
      printf '_NEWEST_MTIME=%s\n' "$newest_mtime"
      # Write loaded files array
      printf '_LOADED_FILES=(\n'
      local f
      for f in "${loaded_files[@]}"; do
        printf '  %q\n' "$f"
      done
      printf ')\n'
    } > "$_BRAIN_CONTEXT_STATE_FILE"
  fi

  printf '%s' "$assembled"
}

# ------------------------------------------------------------------------------
# build_summary_block <cwd> <source> <project_count> <pitfall_count> <global_active> <newest_mtime>
#
# Build the brain summary block for first-message context.
#
# Args:
#   $1 — current working directory
#   $2 — source
#   $3 — project_count
#   $4 — pitfall_count
#   $5 — global_active (true/false)
#   $6 — newest_mtime (Unix timestamp, 0 if none)
# Output: formatted summary block (stdout)
# ------------------------------------------------------------------------------
build_summary_block() {
  local cwd="$1"
  local source="$2"
  local project_count="${3:-0}"
  local pitfall_count="${4:-0}"
  local global_active="${5:-false}"
  local newest_mtime="${6:-0}"

  local project_name
  project_name=$(get_project_name "$cwd" | awk '{print $1}')

  # Format newest date
  local newest_date="none"
  if [ "$newest_mtime" -gt 0 ] 2>/dev/null; then
    newest_date=$(date -d "@${newest_mtime}" +"%Y-%m-%d" 2>/dev/null \
      || date -r "$newest_mtime" +"%Y-%m-%d" 2>/dev/null \
      || printf '%s' "unknown")
  fi

  local summary
  summary="$(printf '\xf0\x9f\xa7\xa0') Brain loaded for ${project_name}
   ${project_count} project notes (newest: ${newest_date})
   ${pitfall_count} pitfalls"

  if [ "$global_active" = "true" ]; then
    summary="${summary}
   Global preferences active"
  fi

  # First-time project offer
  if [ "$project_count" -eq 0 ]; then
    local brain_md_exists=false
    local project_root
    project_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
    [ -z "$project_root" ] && project_root="$cwd"
    [ -f "${project_root}/.brain.md" ] && brain_md_exists=true

    if [ "$brain_md_exists" = "false" ]; then
      summary="${summary}
   No project notes yet — ask me to scan this project for brain cataloging"
    fi
  fi

  printf '%s' "$summary"
}

# ------------------------------------------------------------------------------
# write_session_state <project> [loaded_file1] [loaded_file2] ...
#
# Write $BRAIN_PATH/.brain-session-state.json atomically (temp + mv).
#
# Args:
#   $1 — project name
#   $2+ — paths to loaded files
# ------------------------------------------------------------------------------
write_session_state() {
  local project="$1"
  shift
  local files=("$@")

  local state_file="${BRAIN_PATH}/.brain-session-state.json"
  local tmp_file="${state_file}.tmp.$$"

  local loaded_at
  loaded_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build entries JSON array
  local entries_json="[]"
  local f
  for f in "${files[@]}"; do
    local mtime
    mtime=$(get_mtime "$f")
    entries_json=$(printf '%s' "$entries_json" \
      | jq --arg path "$f" --arg mtime "$mtime" \
        '. += [{"path": $path, "mtime": $mtime}]')
  done

  # Build full JSON
  local state_json
  state_json=$(jq -n \
    --arg project "$project" \
    --arg loaded_at "$loaded_at" \
    --argjson entries "$entries_json" \
    '{"project": $project, "loaded_at": $loaded_at, "entries": $entries}')

  # Write atomically
  printf '%s\n' "$state_json" > "$tmp_file" && mv "$tmp_file" "$state_file"
}
