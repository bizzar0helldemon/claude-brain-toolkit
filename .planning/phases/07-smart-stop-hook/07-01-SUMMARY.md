---
phase: 07-smart-stop-hook
plan: 01
subsystem: hooks
tags: [stop-hook, signal-detection, transcript-parsing, jq, bash]
dependency_graph:
  requires: []
  provides: [smart-stop-hook]
  affects: [hooks/stop.sh]
tech_stack:
  added: []
  patterns: [jq-jsonl-parsing, bash-signal-detection, heredoc-test-fixtures]
key_files:
  modified: [hooks/stop.sh]
  created: [hooks/tests/test-stop-signals.sh]
decisions:
  - "TOOL_COUNT > 0 is sufficient threshold — any tool use indicates non-trivial work; no minimum threshold needed for v1.1"
  - "Error resolution sessions are captured implicitly via TOOL_COUNT > 0 — no separate HAS_ERROR_RESOLUTION signal needed"
  - "Missing/absent transcript_path defaults to trivial (no block) — conservative in the correct direction"
metrics:
  duration_seconds: 325
  completed: 2026-03-21
---

# Phase 7 Plan 01: Smart Stop Hook — Signal Detection Summary

**One-liner:** Stop hook now parses session transcript JSONL via jq to count tool calls, git commits, and file writes — only blocking for brain capture when at least one signal is non-zero.

---

## What Was Built

Modified `hooks/stop.sh` to replace the unconditional `decision:block` with signal-gated blocking. The hook reads `transcript_path` from its input, parses the JSONL file using jq to detect meaningful work, and exits silently on trivial sessions.

**Signal detection logic:**
- `TOOL_COUNT` — count of all tool_use entries in assistant messages (double-filtered to exclude progress entries)
- `HAS_GIT_COMMIT` — grep count of `git commit` strings in Bash tool command inputs
- `HAS_FILE_CHANGES` — count of Write or Edit tool calls

If all three are zero, the hook exits 0 with no output. If any is non-zero, it emits `decision:block` with the existing REASON text.

**Test coverage:** Created `hooks/tests/test-stop-signals.sh` with 5 test cases (7 assertions) using synthetic inline JSONL fixtures. All pass.

---

## Commits

| Hash | Type | Description |
|------|------|-------------|
| fc41bb7 | feat | Add transcript signal detection to stop.sh |
| 4710199 | test | Add dry-run signal detection tests for stop.sh |

---

## Deviations from Plan

None — plan executed exactly as written. The Full Detection Logic Skeleton from 07-RESEARCH.md was used directly, matching the plan's action spec.

---

## Verification Results

1. `bash -n hooks/stop.sh` — PASS (syntax clean)
2. `stop_hook_active` guard remains first check before `source` — PASS (lines 6-10)
3. TOOL_COUNT, HAS_GIT_COMMIT, HAS_FILE_CHANGES all present — PASS
4. Silent exit 0 path when SHOULD_CAPTURE=false — PASS (line 62-64)
5. `decision:block` emission path with emit_json preserved — PASS (line 70)
6. Existing REASON text unchanged — PASS
7. `bash hooks/tests/test-stop-signals.sh` — 7/7 assertions PASS

---

## Key Patterns

**jq double-filter for tool calls (excludes progress entries):**
```bash
jq -r '
  select(.type == "assistant") |
  .message.content[]? |
  select(.type == "tool_use") |
  .name
' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' '
```

**grep -c guard for zero-match exit code:**
```bash
grep -c 'git commit' || echo 0
```

**wc -l whitespace normalization:**
```bash
wc -l | tr -d ' '
```

---

## Self-Check: PASSED

All files exist. All commits verified. All verification criteria met.
