#!/usr/bin/env bash
# test-cache-project-isolation.sh — Verify the /clear fast path in
# hooks/session-start.sh refuses to serve a cached context that was stamped
# by a different project (BTK-1).
#
# Re-runnable at any time. Each test uses isolated $BRAIN_PATH and CWD dirs.
# Usage: bash hooks/tests/test-cache-project-isolation.sh
# Exit: 0 if all tests pass, 1 if any test fails

set -u

PASS=0
FAIL=0
FAILURES=()

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/session-start.sh"

# --- Helpers ---

assert_eq() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $test_name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    FAIL=$((FAIL + 1))
    FAILURES+=("$test_name")
  fi
}

assert_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"
  case "$haystack" in
    *"$needle"*)
      echo "PASS: $test_name"
      PASS=$((PASS + 1))
      ;;
    *)
      echo "FAIL: $test_name — '$needle' not found in output"
      echo "  haystack: ${haystack:0:200}"
      FAIL=$((FAIL + 1))
      FAILURES+=("$test_name")
      ;;
  esac
}

assert_not_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"
  case "$haystack" in
    *"$needle"*)
      echo "FAIL: $test_name — '$needle' unexpectedly present"
      FAIL=$((FAIL + 1))
      FAILURES+=("$test_name")
      ;;
    *)
      echo "PASS: $test_name"
      PASS=$((PASS + 1))
      ;;
  esac
}

# --- Temp env management ---

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Create a fake project directory that get_project_name will resolve to
# `$name` via git repo root basename.
make_project() {
  local name="$1"
  local dir="$TMPROOT/$name"
  mkdir -p "$dir"
  git -C "$dir" init --quiet >/dev/null 2>&1
  # Quiet config so git ops don't whine about identity.
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "test"
  printf '%s' "$dir"
}

# Run session-start.sh with a controlled BRAIN_PATH and CWD.
# Echoes stdout (the hook JSON output) on success; stderr is dropped.
run_hook() {
  local brain_path="$1"
  local cwd="$2"
  local source_kind="$3"

  BRAIN_PATH="$brain_path" \
    printf '{"source":"%s","cwd":"%s"}' "$source_kind" "$cwd" \
    | BRAIN_PATH="$brain_path" bash "$HOOK" 2>/dev/null
}

# Extract the additionalContext field from hook JSON output.
extract_ctx() {
  local hook_output="$1"
  printf '%s' "$hook_output" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# Pre-populate a stamped cache for a given project.
write_stamped_cache() {
  local brain_path="$1"
  local project="$2"
  local ctx="$3"
  jq -n \
    --arg ctx "$ctx" \
    --arg project "$project" \
    --arg cwd "/fake/path/$project" \
    '{additionalContext: $ctx, project: $project, cwd: $cwd, cached_at: now}' \
    > "$brain_path/.brain-cached-context.json"
}

# Pre-populate a legacy (pre-fix) cache without project stamp.
write_legacy_cache() {
  local brain_path="$1"
  local ctx="$2"
  jq -n --arg ctx "$ctx" '{additionalContext: $ctx}' \
    > "$brain_path/.brain-cached-context.json"
}

# --- Test 1: cache hit, same project — serves cached context ---
test_same_project_hit() {
  local brain="$TMPROOT/brain-1"
  mkdir -p "$brain"
  local proj_a
  proj_a=$(make_project "proj-alpha")

  write_stamped_cache "$brain" "proj-alpha" "ALPHA-CACHED-CONTEXT"

  local out ctx
  out=$(run_hook "$brain" "$proj_a" "clear")
  ctx=$(extract_ctx "$out")

  assert_eq "same-project cache hit serves cached context" \
    "ALPHA-CACHED-CONTEXT" "$ctx"
}

# --- Test 2: cache miss, different project — falls through, no leak ---
test_cross_project_isolation() {
  local brain="$TMPROOT/brain-2"
  mkdir -p "$brain"
  local proj_b
  proj_b=$(make_project "proj-beta")

  # Cache was stamped by a different project.
  write_stamped_cache "$brain" "proj-alpha" "ALPHA-SECRET-CONTEXT"

  local out ctx
  out=$(run_hook "$brain" "$proj_b" "clear")
  ctx=$(extract_ctx "$out")

  assert_not_contains "cross-project /clear does not leak cached context" \
    "ALPHA-SECRET-CONTEXT" "$ctx"
  assert_contains "cross-project /clear emits minimal placeholder" \
    "no cache for proj-beta" "$ctx"

  # Verify the mismatch was logged.
  local log="$brain/.brain-errors.log"
  if [ -f "$log" ]; then
    assert_contains "cross-project mismatch is logged" \
      "Cache project mismatch" "$(cat "$log")"
  else
    echo "FAIL: cross-project mismatch is logged — log file not created"
    FAIL=$((FAIL + 1))
    FAILURES+=("cross-project mismatch is logged")
  fi
}

# --- Test 3: no cache file, /clear — minimal context ---
test_no_cache_clear() {
  local brain="$TMPROOT/brain-3"
  mkdir -p "$brain"
  local proj_c
  proj_c=$(make_project "proj-gamma")

  local out ctx
  out=$(run_hook "$brain" "$proj_c" "clear")
  ctx=$(extract_ctx "$out")

  assert_contains "missing cache file emits minimal placeholder" \
    "no cache for proj-gamma" "$ctx"
}

# --- Test 4: empty additionalContext in cache — falls through ---
test_empty_cache_falls_through() {
  local brain="$TMPROOT/brain-4"
  mkdir -p "$brain"
  local proj_d
  proj_d=$(make_project "proj-delta")

  # Stamped for the right project but empty body.
  write_stamped_cache "$brain" "proj-delta" ""

  local out ctx
  out=$(run_hook "$brain" "$proj_d" "clear")
  ctx=$(extract_ctx "$out")

  assert_contains "empty cache body emits minimal placeholder" \
    "no cache for proj-delta" "$ctx"
}

# --- Test 5: legacy cache (no project field) — treated as untrusted ---
test_legacy_cache_falls_through() {
  local brain="$TMPROOT/brain-5"
  mkdir -p "$brain"
  local proj_e
  proj_e=$(make_project "proj-epsilon")

  write_legacy_cache "$brain" "LEGACY-UNSTAMPED-CONTEXT"

  local out ctx
  out=$(run_hook "$brain" "$proj_e" "clear")
  ctx=$(extract_ctx "$out")

  assert_not_contains "legacy unstamped cache is not served" \
    "LEGACY-UNSTAMPED-CONTEXT" "$ctx"
  assert_contains "legacy unstamped cache emits minimal placeholder" \
    "no cache for proj-epsilon" "$ctx"

  local log="$brain/.brain-errors.log"
  if [ -f "$log" ]; then
    assert_contains "legacy cache fall-through is logged" \
      "Legacy cache without project field" "$(cat "$log")"
  fi
}

# --- Test 6: cache write stamps the project field on full startup ---
test_full_startup_stamps_cache() {
  local brain="$TMPROOT/brain-6"
  mkdir -p "$brain"
  local proj_f
  proj_f=$(make_project "proj-zeta")

  # Run with source=startup to trigger the full path which writes the cache.
  run_hook "$brain" "$proj_f" "startup" >/dev/null

  local cache="$brain/.brain-cached-context.json"
  if [ ! -f "$cache" ]; then
    echo "FAIL: full startup writes cache file — file not created"
    FAIL=$((FAIL + 1))
    FAILURES+=("full startup writes cache file")
    return
  fi

  local stamped
  stamped=$(jq -r '.project // empty' "$cache" 2>/dev/null)
  assert_eq "full startup stamps cache with current project" \
    "proj-zeta" "$stamped"
}

# --- Run all tests ---

echo "Running cache project-isolation tests..."
echo "Hook under test: $HOOK"
echo ""

test_same_project_hit
test_cross_project_isolation
test_no_cache_clear
test_empty_cache_falls_through
test_legacy_cache_falls_through
test_full_startup_stamps_cache

echo ""
echo "=========================================="
echo "Results: $PASS passed, $FAIL failed"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  exit 1
fi

exit 0
