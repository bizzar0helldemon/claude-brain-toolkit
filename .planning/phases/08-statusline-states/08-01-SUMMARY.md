---
phase: 08-statusline-states
plan: "01"
subsystem: statusline
tags:
  - statusline
  - hooks
  - state-machine
  - shell
dependency_graph:
  requires:
    - "07-01 (stop.sh signal detection — threshold logic this plan extends)"
  provides:
    - "write_brain_state helper (hooks/lib/brain-path.sh)"
    - "Three-state statusline display (idle/captured/error)"
    - ".brain-state file protocol"
  affects:
    - "hooks/lib/brain-path.sh"
    - "hooks/stop.sh"
    - "hooks/session-start.sh"
    - "hooks/post-tool-use-failure.sh"
    - "statusline.sh"
tech_stack:
  added: []
  patterns:
    - "Atomic temp+mv file write for cross-process state (existing pattern extended)"
    - "Octal escape sequences for emoji portability (existing convention maintained)"
    - "BRAIN_PATH guard before file operations (existing pattern applied)"
key_files:
  created: []
  modified:
    - "hooks/lib/brain-path.sh"
    - "hooks/stop.sh"
    - "hooks/session-start.sh"
    - "hooks/post-tool-use-failure.sh"
    - "statusline.sh"
decisions:
  - "write_brain_state lives in brain-path.sh (shared library), not duplicated per hook"
  - "Error state resets to idle on SessionStart — statusline is a live indicator, not historical"
  - "captured written AFTER emit_json in stop.sh (Pitfall 3 avoidance)"
metrics:
  duration: "~8 minutes"
  completed: "2026-03-21"
---

# Phase 8 Plan 01: Statusline States Summary

## One-liner

Three-state statusline (idle/captured/error) driven by atomic `.brain-state` file writes from hooks, read on every statusline refresh via `BRAIN_PATH` guard.

## What Was Built

Added passive visual state communication to the statusline — the user now sees at a glance whether the brain captured work or encountered errors, without running any commands.

**State protocol:**
- `idle` — brain active, no notable hook activity (brain emoji only)
- `captured` — stop hook fired and emitted decision:block (green circle + brain)
- `error` — a tool failure was logged (red circle + brain)

**Cross-process channel:** `.brain-state` plain text file at `$BRAIN_PATH/.brain-state`. Hooks write it atomically; statusline reads it with `cut -d' ' -f1` on every refresh. No jq in the hot path.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add write_brain_state helper and hook state writes | 6109157 | hooks/lib/brain-path.sh, hooks/stop.sh, hooks/session-start.sh, hooks/post-tool-use-failure.sh |
| 2 | Update statusline to read state file and display indicators | 2425211 | statusline.sh |

## Implementation Details

### brain-path.sh — write_brain_state helper

New function after `update_encounter_count`. Guards on `[ ! -d "${BRAIN_PATH:-}" ]`, writes `"$state $timestamp"` via temp+mv atomic pattern. On mv failure: removes temp and calls `brain_log_error`. Always returns 0.

### stop.sh — state writes at decision points

- Trivial session path: `write_brain_state "idle"` before `exit 0`
- Capture block path: `write_brain_state "captured"` AFTER `emit_json "$BLOCK_JSON"` (ordering per research Pitfall 3)

### session-start.sh — session reset

`write_brain_state "idle"` immediately after `brain_path_validate` succeeds, before sourcing brain-context.sh. Prevents stale `captured` or `error` states persisting from prior sessions.

### post-tool-use-failure.sh — error signaling

`write_brain_state "error"` immediately after `brain_log_error "ToolFailure:$TOOL_NAME"`. Signals degraded state for any tool failure in the session.

### statusline.sh — state-aware display

Replaced single `printf` with `BRAIN_STATE` read + `case` statement:
- Reads `$BRAIN_PATH/.brain-state` only when `BRAIN_PATH` is set and file exists
- Defaults to `idle` if either guard fails
- `cut -d' ' -f1` extracts state name, ignores timestamp
- All emoji use octal escape sequences (existing portability convention)

## Deviations from Plan

None — plan executed exactly as written. Research doc patterns matched implementation requirements without adjustment.

## Verification Results

1. All 5 files pass `bash -n` syntax check
2. `write_brain_state` function defined in brain-path.sh (3 references: definition + 2 in header comment)
3. `write_brain_state "captured"` on line 73, `emit_json` on line 72 — ordering verified
4. `write_brain_state "idle"` present in both stop.sh (trivial path) and session-start.sh
5. `write_brain_state "error"` present in post-tool-use-failure.sh
6. `cut.*brain-state` pattern present in statusline.sh
7. No raw Unicode in statusline.sh — octal only confirmed
8. Idle fallback test: `BRAIN_PATH="/nonexistent" bash statusline.sh` outputs brain emoji only
9. Non-brain-mode test: outputs `[Sonnet] 25%` without brain emoji

## Self-Check: PASSED

All files present. Both task commits verified in git history.
