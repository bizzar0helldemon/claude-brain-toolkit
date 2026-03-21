---
phase: 06-resolve-brain-scan-ref
plan: 01
subsystem: agents
tags: [brain-mode, slash-commands, documentation, cleanup]

# Dependency graph
requires:
  - phase: 05-deploy-phase4-artifacts
    provides: setup.sh deploying all Phase 4 artifacts including brain-mode skills
provides:
  - brain-mode.md without dangling /brain-scan references — Available Skills list is now authoritative
affects: [brain-mode, onboarding, v1.0-milestone]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Available Skills list in agent definitions should only reference skills deployed by setup.sh"

key-files:
  created: []
  modified:
    - agents/brain-mode.md

key-decisions:
  - "/brain-scan is a standalone toolkit skill, not a brain-mode artifact — brain-mode.md must not list it"
  - "Empty-vault guidance directs users to /brain-capture (the correct first-session action), not /brain-scan"

patterns-established:
  - "Agent definitions are authoritative: if a skill isn't deployed by setup.sh it must not appear in Available Skills"

# Metrics
duration: 1min
completed: 2026-03-21
---

# Phase 6 Plan 01: Resolve Brain-Scan Reference Summary

**Removed three dangling /brain-scan references from brain-mode.md — Available Skills list now matches exactly what setup.sh deploys**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-03-21T18:30:29Z
- **Completed:** 2026-03-21T18:30:55Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Removed /brain-scan from the proactive knowledge capture paragraph (line 54)
- Replaced /brain-scan in empty-vault guidance with /brain-capture (the correct onboarding action)
- Removed /brain-scan entry from Available Skills list (it is a standalone skill, not a brain-mode artifact)
- All five actual brain-mode skills remain intact: /brain-capture, /daily-note, /brain-audit, /brain-add-pattern, /brain-setup

## Task Commits

1. **Task 1: Remove /brain-scan references from brain-mode.md** - `f548daf` (fix)

## Files Created/Modified

- `agents/brain-mode.md` - Removed three /brain-scan references; Available Skills now authoritative

## Decisions Made

- /brain-scan is a legitimate standalone toolkit skill but is not deployed as a brain-mode hook artifact — brain-mode.md should not own it
- Empty-vault guidance now correctly points to /brain-capture (the natural first-session action) rather than /brain-scan

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- v1.0 milestone audit gap closed — brain-mode.md Available Skills list is now authoritative
- All phases complete — project at v1.0

---
*Phase: 06-resolve-brain-scan-ref*
*Completed: 2026-03-21*

## Self-Check: PASSED

- FOUND: agents/brain-mode.md
- FOUND: .planning/phases/06-resolve-brain-scan-ref/06-01-SUMMARY.md
- FOUND: commit f548daf
