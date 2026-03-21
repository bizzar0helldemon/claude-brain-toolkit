# hooks/lib/brain-path.sh
# Sourced library — do NOT execute directly. Source with: source hooks/lib/brain-path.sh
#
# Provides: brain_path_validate, brain_log_error, emit_json
# Compatible with: bash 3.2+, zsh 5.0+
# All output uses printf (not echo) for portability.

# ------------------------------------------------------------------------------
# brain_path_validate
#
# Validates that BRAIN_PATH is set and points to an existing directory.
#
# On failure: writes contextual explanation to stderr, JSON error to stdout.
# On success: returns 0 with no output.
#
# Return codes: 0 = valid, 1 = invalid (unset or directory missing)
# ------------------------------------------------------------------------------
brain_path_validate() {
  # Case 1: BRAIN_PATH is unset or empty
  if [ -z "${BRAIN_PATH:-}" ]; then
    printf '%s\n' \
      "BRAIN_PATH is not set." \
      "" \
      "BRAIN_PATH is an environment variable that tells Claude Brain where your personal" \
      "knowledge vault lives on disk. Every hook script depends on it to read and write" \
      "your notes, session logs, and error records." \
      "" \
      "To fix this, add the following line to your shell profile (~/.bashrc, ~/.zshrc," \
      "or ~/.bash_profile depending on your shell):" \
      "" \
      "  export BRAIN_PATH=\"/path/to/your/vault\"" \
      "" \
      "Replace /path/to/your/vault with the actual directory where you want to store" \
      "your brain data. After editing your profile, run:" \
      "" \
      "  source ~/.zshrc   # or ~/.bashrc / ~/.bash_profile" \
      "" \
      "You also need to set BRAIN_PATH in settings.json under the \"env\" block so that" \
      "Claude Code injects it into hook subprocesses (shell profiles are not loaded in" \
      "non-interactive subshells)." \
      >&2

    emit_json '{"error":"BRAIN_PATH is not set","degraded":true}'
    return 1
  fi

  # Case 2: BRAIN_PATH is set but the directory does not exist
  if [ ! -d "$BRAIN_PATH" ]; then
    printf '%s\n' \
      "BRAIN_PATH directory does not exist: $BRAIN_PATH" \
      "" \
      "BRAIN_PATH is currently set to a path that does not exist on disk. This can" \
      "happen when:" \
      "  - You set BRAIN_PATH for the first time and haven't created the directory yet." \
      "  - Your vault was moved, renamed, or is on a drive that isn't mounted." \
      "  - You're on a different machine and the path doesn't match." \
      "" \
      "To create the directory at the current path, run:" \
      "" \
      "  mkdir -p \"$BRAIN_PATH\"" \
      "" \
      "If your vault has moved, update BRAIN_PATH in both your shell profile and in" \
      "settings.json (under the \"env\" block) to point to the new location." \
      "" \
      "Claude Brain has flagged this in the JSON output below so Claude can surface" \
      "an offer to create the directory for you if you prefer." \
      >&2

    emit_json "{\"error\":\"BRAIN_PATH directory does not exist\",\"path\":\"$BRAIN_PATH\",\"degraded\":true,\"offer_create\":true}"
    return 1
  fi

  # Case 3: Valid — BRAIN_PATH is set and directory exists
  return 0
}

# ------------------------------------------------------------------------------
# brain_log_error <event> <message>
#
# Appends a UTC-timestamped error entry to $BRAIN_PATH/.brain-errors.log.
# Only writes if BRAIN_PATH points to a valid directory (guards against
# cascading failures when BRAIN_PATH itself is invalid).
#
# Args:
#   $1 — event name (e.g., "SessionStart", "JSONValidation")
#   $2 — error message
# ------------------------------------------------------------------------------
brain_log_error() {
  local event="$1"
  local message="$2"

  # Guard: only log if BRAIN_PATH is a valid directory
  if [ ! -d "${BRAIN_PATH:-}" ]; then
    return 0
  fi

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s\n' "[$timestamp] $event: $message" >> "$BRAIN_PATH/.brain-errors.log"
}

# ------------------------------------------------------------------------------
# emit_json <json_string>
#
# Validates a JSON string with jq, then prints it to stdout if valid.
# If invalid: writes an error to stderr, logs via brain_log_error, exits 0
# (never breaks the session over a JSON formatting bug).
#
# Args:
#   $1 — JSON string to validate and emit
# ------------------------------------------------------------------------------
emit_json() {
  local json="$1"

  if printf '%s' "$json" | jq empty >/dev/null 2>&1; then
    printf '%s\n' "$json"
  else
    printf '%s\n' "emit_json: invalid JSON detected — output suppressed to prevent corrupting Claude's input." >&2
    printf '%s\n' "  Attempted value: $json" >&2
    brain_log_error "JSONValidation" "Invalid JSON suppressed: $json"
    exit 0
  fi
}

# ------------------------------------------------------------------------------
# init_pattern_store <store_path>
#
# Ensures the pattern store file exists with a valid empty schema.
# Creates parent directory if needed. No-op if file already exists.
#
# Args:
#   $1 — absolute path to pattern-store.json
#
# Return codes: 0 always
# ------------------------------------------------------------------------------
init_pattern_store() {
  local store_path="$1"
  local store_dir
  store_dir=$(dirname "$store_path")

  # Create parent directory if it doesn't exist
  mkdir -p "$store_dir"

  # No-op if store already exists
  if [ -f "$store_path" ]; then
    return 0
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local tmp_file
  tmp_file="${store_path}.tmp.$$"

  printf '%s\n' "{\"version\":\"1\",\"created\":\"$now\",\"updated\":\"$now\",\"patterns\":[]}" > "$tmp_file"

  if ! mv "$tmp_file" "$store_path" 2>/dev/null; then
    rm -f "$tmp_file" 2>/dev/null
    brain_log_error "PatternStore" "Failed to initialize pattern store at $store_path"
  fi

  return 0
}

# ------------------------------------------------------------------------------
# update_encounter_count <store_path> <error_message>
#
# Increments encounter_count and sets last_seen for any pattern whose key
# is contained in the error message (case-insensitive match).
# Writes atomically via temp+mv. Never crashes the calling hook.
#
# Args:
#   $1 — absolute path to pattern-store.json
#   $2 — error message string to match against pattern keys
#
# Return codes: 0 always
# ------------------------------------------------------------------------------
update_encounter_count() {
  local store_path="$1"
  local error_msg="$2"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local tmp_file
  tmp_file="${store_path}.tmp.$$"

  # Use jq to update matching patterns atomically.
  # `. as $p` binds the pattern object before select so .key is accessible
  # inside the contains() call (which otherwise evaluates in string context).
  if ! jq \
    --arg now "$now" \
    --arg error_msg "$error_msg" \
    '.updated = $now |
     .patterns = [
       .patterns[] |
       . as $p |
       if ($error_msg | ascii_downcase) | contains($p.key | ascii_downcase)
       then .encounter_count += 1 | .last_seen = $now
       else .
       end
     ]' \
    "$store_path" > "$tmp_file" 2>/dev/null; then
    rm -f "$tmp_file" 2>/dev/null
    brain_log_error "PatternStore" "jq update failed for store at $store_path"
    return 0
  fi

  if ! mv "$tmp_file" "$store_path" 2>/dev/null; then
    rm -f "$tmp_file" 2>/dev/null
    brain_log_error "PatternStore" "atomic write failed for store at $store_path"
  fi

  return 0
}
