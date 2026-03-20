---
phase: 01-hook-infrastructure
plan: "02"
subsystem: hook-infrastructure
tags:
  - hooks
  - lifecycle
  - statusline
  - shell
dependency_graph:
  requires:
    - 01-01
  provides:
    - session-start-hook
    - pre-compact-hook
    - stop-hook
    - post-tool-use-failure-hook
    - statusline-script
  affects:
    - all future phases (hooks are the foundation)
tech_stack:
  added:
    - bash shell scripting (lifecycle hooks)
  patterns:
    - stop-loop guard via CLAUDE_HOOK_ACTIVE env var check
    - degraded-mode JSON on validation failure (exit 0, degraded:true)
    - append-only error log with timestamps (.brain-errors.log)
    - statusline via agent.name detection (CLAUDE_AGENT_NAME or hook input JSON)
key_files:
  created:
    - hooks/session-start.sh
    - hooks/pre-compact.sh
    - hooks/stop.sh
    - hooks/post-tool-use-failure.sh
    - statusline.sh
  modified: []
key_decisions: []
metrics:
  duration: ~3 minutes
  completed: "2026-03-20"
---

# Phase 1 Plan 2: Lifecycle Hook Scripts + Statusline Summary

**One-liner:** Four lifecycle hook scripts (SessionStart, PreCompact, Stop, PostToolUseFailure) and a statusline script that shows brain emoji when brain mode is active — all using the BRAIN_PATH validation library from 01-01.

## Performance

- **Duration:** ~3 minutes
- **Tasks completed:** 2 of 2 (plus human-verify checkpoint, approved)
- **Deviations:** None

## Accomplishments

- All four lifecycle hooks implemented using the `brain-path.sh` library (brain_path_validate, emit_json, brain_log_error)
- Stop hook has stop-loop guard: checks `CLAUDE_HOOK_ACTIVE` env var BEFORE sourcing anything — no sourcing side effects trigger re-entry
- PostToolUseFailure appends timestamped entries to `.brain-errors.log` in BRAIN_PATH; degraded-mode writes to stderr only
- statusline.sh reads agent name from hook input JSON; emits brain emoji when agent.name is "brain-mode", plain model+context% otherwise
- All hooks emit valid JSON; degraded-mode path emits `{"degraded": true}` and exits 0 so invalid BRAIN_PATH never breaks a session
- User smoke-tested all paths: BRAIN_PATH unset, stop loop guard, statusline brain mode, statusline normal mode, all 4 hooks with valid BRAIN_PATH, error log entries

## Task Commits

| Task | Description | Commit |
|------|-------------|--------|
| 1 | Create all 4 lifecycle hook scripts | 0dac879 |
| 2 | Create statusline script with brain mode indicator | 51b8630 |
| 3 | Checkpoint: human-verify (approved) | APPROVED |

## Files Created

| File | Purpose |
|------|---------|
| `hooks/session-start.sh` | SessionStart handler; validates BRAIN_PATH, logs startup, emits scaffold JSON |
| `hooks/pre-compact.sh` | PreCompact handler; validates BRAIN_PATH, emits trigger field |
| `hooks/stop.sh` | Stop handler; stop-loop guard checks CLAUDE_HOOK_ACTIVE before any sourcing |
| `hooks/post-tool-use-failure.sh` | PostToolUseFailure handler; logs tool failures to .brain-errors.log with timestamps |
| `statusline.sh` | Shows brain emoji + model + context% in brain mode; model + context% otherwise |

## Decisions Made

None — followed plan as specified. All implementation choices (stop-loop guard pattern, degraded-mode exit 0) were established in Phase 1 research and carried through as designed.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. All smoke tests passed on first run.

## Next Phase Readiness

Phase 1 is now complete. Phase 2 (Session Lifecycle) can begin.

**Phase 2 prerequisites satisfied:**
- Hook scaffold in place (all 4 lifecycle events covered)
- BRAIN_PATH validation library available to all scripts
- settings.json template ready for hook registration
- Stop-loop guard prevents recursive hook invocation
- Error logging channel established

**Pending concerns carried forward to Phase 2:**
- Windows Git Bash compatibility: `stat` flags differ between macOS and Linux/Git Bash — verify in Phase 2 if stat is used
- Verify whether `skills` frontmatter in `agents/brain-mode.md` preloads brain-* skills at session start (live test required in Phase 3)

## Self-Check

**Files exist:**
- `hooks/session-start.sh` — FOUND
- `hooks/pre-compact.sh` — FOUND
- `hooks/stop.sh` — FOUND
- `hooks/post-tool-use-failure.sh` — FOUND
- `statusline.sh` — FOUND

**Commits exist:**
- `0dac879` — FOUND (feat(01-02): create all 4 lifecycle hook scripts)
- `51b8630` — FOUND (feat(01-02): create statusline script with brain mode indicator)

## Self-Check: PASSED
