---
phase: 04-intelligence-layer
plan: "01"
subsystem: hooks
tags: [post-tool-use, git-commit-detection, brain-capture, intelligence-layer, hooks]
requires:
  - hooks/lib/brain-path.sh
  - "03-02: setup.sh installer"
provides:
  - hooks/post-tool-use.sh
  - PostToolUse hook registration in settings.json
affects:
  - settings.json
  - Any future PostToolUse hooks (no matcher conflict by design)
tech-stack:
  added: []
  patterns:
    - PostToolUse hook using decision:block (synchronous, no async)
    - Tool/command filtering inside script rather than via matcher field
key-files:
  created:
    - hooks/post-tool-use.sh
  modified:
    - settings.json
key-decisions:
  - No async:true on PostToolUse (decision:block requires synchronous execution)
  - No matcher field — filtering handled in script to avoid future hook conflicts
  - async:true removed from PostToolUseFailure proactively for Plan 02 compatibility
  - No stop_hook_active guard — PostToolUse does not loop like Stop hooks
  - Graceful degradation (exit 0) when BRAIN_PATH is invalid — never blocks tool use
patterns-established:
  - PostToolUse hooks should filter tool/command in-script, not via matcher
  - decision:block hooks must be synchronous (no async:true)
duration: "~2 minutes"
completed: "2026-03-21"
---

# Phase 4 Plan 01: PostToolUse Git Commit Detection Hook Summary

**One-liner:** PostToolUse hook that intercepts successful `git commit` Bash calls and emits `decision:block` instructing Claude to run `/brain-capture` before continuing.

## Accomplishments

- Created `hooks/post-tool-use.sh` following the established hook pattern from `stop.sh`
- Hook reads stdin, validates BRAIN_PATH, filters to Bash-only and git-commit-only, skips `--dry-run`
- Registered `PostToolUse` in `settings.json` (synchronous, no matcher, no async)
- Removed `async:true` from `PostToolUseFailure` entry (Plan 02 prep)
- All 5 verification checks pass

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create PostToolUse git commit detection hook | 8a50dc8 | hooks/post-tool-use.sh |
| 2 | Register PostToolUse hook in settings.json | af574eb | settings.json |

## Files Created / Modified

**Created:**
- `hooks/post-tool-use.sh` — PostToolUse hook (34 lines)

**Modified:**
- `settings.json` — Added PostToolUse entry, removed async from PostToolUseFailure

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| No async:true on PostToolUse | decision:block requires synchronous execution — async hooks cannot block |
| Filter in-script (no matcher) | Avoids conflicts with any future PostToolUse hooks that may need to coexist |
| No stop_hook_active guard | PostToolUse does not loop — guard is Stop hook-specific |
| async removed from PostToolUseFailure | Plan 02 will extend it with additionalContext, which also requires synchronous execution |
| Graceful degradation on invalid BRAIN_PATH | Hook exits 0, never blocking tool use when brain is misconfigured |

## Deviations from Plan

None — plan executed exactly as written.

## Issues

None.

## Self-Check

**Files exist:**
- hooks/post-tool-use.sh: FOUND
- settings.json (modified): FOUND

**Commits exist:**
- 8a50dc8: FOUND (feat(04-01): create PostToolUse git commit detection hook)
- af574eb: FOUND (chore(04-01): register PostToolUse hook in settings.json)

## Self-Check: PASSED

## Next Phase Readiness

Plan 04-02 (PostToolUseFailure error pattern injection) can proceed:
- `settings.json` PostToolUseFailure entry is already synchronous (async removed)
- Hook library (`brain-path.sh`) is available and proven
- No blockers identified
