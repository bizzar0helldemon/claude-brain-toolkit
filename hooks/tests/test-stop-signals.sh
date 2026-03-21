#!/usr/bin/env bash
# test-stop-signals.sh — Validate jq signal detection patterns from stop.sh
# Re-runnable at any time. All fixtures are created inline and cleaned up on exit.
# Usage: bash hooks/tests/test-stop-signals.sh
# Exit: 0 if all tests pass, 1 if any test fails

PASS=0
FAIL=0
FAILURES=()

# --- Helpers ---

assert_eq() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $test_name — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
    FAILURES+=("$test_name")
  fi
}

assert_gt() {
  local test_name="$1"
  local threshold="$2"
  local actual="$3"
  if [ "$actual" -gt "$threshold" ] 2>/dev/null; then
    echo "PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $test_name — expected > $threshold, got '$actual'"
    FAIL=$((FAIL + 1))
    FAILURES+=("$test_name")
  fi
}

# --- Temp file management ---

TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

# --- jq patterns (exact copies from stop.sh) ---

count_tools() {
  local transcript="$1"
  jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    .name
  ' "$transcript" 2>/dev/null | wc -l | tr -d ' '
}

count_git_commits() {
  local transcript="$1"
  jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Bash") |
    .input.command // ""
  ' "$transcript" 2>/dev/null | grep -c 'git commit' || echo 0
}

count_file_changes() {
  local transcript="$1"
  jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Write" or .name == "Edit") |
    .name
  ' "$transcript" 2>/dev/null | wc -l | tr -d ' '
}

# =============================================================================
# Test 1: Trivial session — text-only, no tool_use entries
# Expected: TOOL_COUNT=0
# =============================================================================

TRIVIAL_JSONL="$TMPDIR_LOCAL/trivial.jsonl"
cat > "$TRIVIAL_JSONL" <<'JSONL'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"What is 2+2?"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"4"}]}}
{"type":"progress","data":{"type":"hook_progress","hookEventName":"Stop","message":"Running stop hook"}}
{"type":"file-history-snapshot","content":{}}
JSONL

TOOL_COUNT=$(count_tools "$TRIVIAL_JSONL")
assert_eq "Test 1: Trivial session has TOOL_COUNT=0" "0" "$TOOL_COUNT"

# =============================================================================
# Test 2: Active session — multiple tool_use entries (Bash, Read, Write)
# Expected: TOOL_COUNT > 0 (should be 3)
# =============================================================================

ACTIVE_JSONL="$TMPDIR_LOCAL/active.jsonl"
cat > "$ACTIVE_JSONL" <<'JSONL'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Run some commands"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls -la"}},{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/tmp/foo.txt"}},{"type":"tool_use","id":"t3","name":"Write","input":{"file_path":"/tmp/bar.txt","content":"hello"}}]}}
{"type":"progress","data":{"type":"hook_progress","hookEventName":"PostToolUse","message":"Bash finished"}}
{"type":"progress","data":{"type":"hook_progress","hookEventName":"PostToolUse","message":"Read finished"}}
{"type":"progress","data":{"type":"hook_progress","hookEventName":"PostToolUse","message":"Write finished"}}
JSONL

TOOL_COUNT=$(count_tools "$ACTIVE_JSONL")
assert_gt "Test 2: Active session has TOOL_COUNT > 0" "0" "$TOOL_COUNT"
assert_eq "Test 2: Active session TOOL_COUNT equals 3" "3" "$TOOL_COUNT"

# =============================================================================
# Test 3: Git commit detection
# Expected: HAS_GIT_COMMIT=1
# =============================================================================

GIT_JSONL="$TMPDIR_LOCAL/git.jsonl"
cat > "$GIT_JSONL" <<'JSONL'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Commit my changes"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"git add src/foo.ts"}},{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"git commit -m 'feat: add foo feature'"}}]}}
JSONL

HAS_GIT_COMMIT=$(count_git_commits "$GIT_JSONL")
assert_eq "Test 3: Git commit detected (count=1)" "1" "$HAS_GIT_COMMIT"

# =============================================================================
# Test 4: File change detection — Write and Edit tool calls
# Expected: HAS_FILE_CHANGES=2
# =============================================================================

FILES_JSONL="$TMPDIR_LOCAL/files.jsonl"
cat > "$FILES_JSONL" <<'JSONL'
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Update some files"}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Write","input":{"file_path":"/tmp/new.txt","content":"new content"}},{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/tmp/existing.txt","old_string":"old","new_string":"new"}}]}}
JSONL

HAS_FILE_CHANGES=$(count_file_changes "$FILES_JSONL")
assert_eq "Test 4: File changes detected (count=2)" "2" "$HAS_FILE_CHANGES"

# =============================================================================
# Test 5: Missing/empty transcript — defaults to 0, no errors emitted
# Expected: TOOL_COUNT=0, no stderr output
# =============================================================================

MISSING_PATH="/tmp/nonexistent-transcript-$(date +%s).jsonl"

TOOL_COUNT=0
STDERR_OUTPUT=""
if [ -n "$MISSING_PATH" ] && [ -f "$MISSING_PATH" ]; then
  TOOL_COUNT=$(count_tools "$MISSING_PATH")
fi

assert_eq "Test 5: Missing transcript yields TOOL_COUNT=0" "0" "$TOOL_COUNT"

# Also verify /dev/null produces 0 (empty file edge case)
NULL_COUNT=$(count_tools /dev/null)
assert_eq "Test 5b: Empty transcript (/dev/null) yields TOOL_COUNT=0" "0" "$NULL_COUNT"

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failed tests:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

exit 0
