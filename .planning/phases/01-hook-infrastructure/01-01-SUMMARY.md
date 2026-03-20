---
phase: 01
plan: 01
subsystem: hook-infrastructure
tags: [brain-path, validation, settings, hooks, foundation]
dependency_graph:
  requires: []
  provides:
    - brain_path_validate (sourced by all hook scripts)
    - brain_log_error (error persistence for post-mortem debugging)
    - emit_json (jq-validated JSON emission)
    - settings.json (hook + statusline registration for Claude Code)
  affects:
    - All Phase 1 hook scripts (source hooks/lib/brain-path.sh)
    - Claude Code lifecycle (SessionStart, PreCompact, Stop, PostToolUseFailure)
tech_stack:
  added:
    - bash 3.2+/zsh 5.0+ compatible shell scripting
    - jq 1.7.1 (JSON validation and parsing — required dependency)
  patterns:
    - Dual-channel errors: stderr for human, JSON stdout for Claude
    - jq self-validation before emit (invalid JSON suppressed, not propagated)
    - Guard patterns: functions check BRAIN_PATH validity before operating
key_files:
  created:
    - hooks/lib/brain-path.sh
    - settings.json
  modified: []
key_decisions:
  - "jq installed to ~/bin/jq.exe (user-scope) — chocolatey not available without admin elevation"
  - "brain-path.sh sourced (no shebang) per plan — chmod +x applied anyway as belt-and-suspenders"
  - "BRAIN_PATH empty string in settings.json env block ensures injection into non-interactive hook subshells"
  - "PostToolUseFailure async:true — cannot block session, logged asynchronously"
metrics:
  duration: "~4 minutes"
  completed: "2026-03-20"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 1 Plan 01: BRAIN_PATH Validation Library and Hook Registration Summary

**One-liner:** Shell library providing BRAIN_PATH validation with dual-channel errors (contextual stderr + jq-validated JSON stdout) and settings.json registering all 4 Claude Code lifecycle hooks with async PostToolUseFailure.

## Accomplishments

- Created `hooks/lib/brain-path.sh` as a sourced library with three functions: `brain_path_validate`, `brain_log_error`, and `emit_json`
- `brain_path_validate` produces rich contextual explanations on stderr (not one-liners) alongside machine-readable JSON on stdout for Claude to parse
- `emit_json` validates JSON with `jq empty` before emitting — invalid JSON is suppressed and logged, never reaching Claude's input stream
- `brain_log_error` appends UTC-timestamped entries to `$BRAIN_PATH/.brain-errors.log` with a guard against logging when BRAIN_PATH itself is invalid
- Created `settings.json` registering all 4 hook lifecycle events and statusline command
- All hooks use `~/.claude/hooks/` paths (user scope); `env.BRAIN_PATH` is empty string ensuring the variable is injected into non-interactive hook subprocesses

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create BRAIN_PATH validation library | a575ff6 | hooks/lib/brain-path.sh |
| 2 | Create settings.json with hook registration and statusline | 05ae437 | settings.json |

## Files Created/Modified

**Created:**
- `hooks/lib/brain-path.sh` — sourced library with brain_path_validate, brain_log_error, emit_json
- `settings.json` — distributable template for ~/.claude/settings.json

**Modified:** None

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| jq installed to ~/bin/jq.exe | Chocolatey requires admin elevation on this system; downloading the binary to user bin was the unblocking path |
| printf throughout (not echo) | Portable across bash 3.2+ and zsh 5.0+ per research notes |
| Contextual stderr explanations (multi-line) | User decision captured in plan: explanation style, not one-liners |
| offer_create:true in JSON | Claude mediates the "create dir?" offer; hooks cannot prompt interactively |
| emit_json exits 0 on invalid JSON | Formatting bugs must not break the session; logged for debugging |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] jq not installed on the system**
- **Found during:** Task 1 verification (first `jq` call failed with "not found")
- **Issue:** jq is a hard dependency for `emit_json` validation; without it all emit calls would fail
- **Fix:** Downloaded `jq-windows-amd64.exe` 1.7.1 from official jqlang releases to `~/bin/jq.exe` (already in PATH as `/c/Users/srco1/bin`)
- **Files modified:** None in the repo — jq installed to user PATH
- **Commit:** Not a separate commit (pre-task fix, no repo files changed)

## Issues Encountered

- None beyond the jq installation deviation above

## Next Phase Readiness

- `hooks/lib/brain-path.sh` is ready to be sourced by all Phase 1 hook scripts (session-start.sh, pre-compact.sh, stop.sh, post-tool-use-failure.sh)
- `settings.json` template is ready; users will configure `env.BRAIN_PATH` during Phase 3 onboarding
- No blockers for Plan 01-02

## Self-Check: PASSED
