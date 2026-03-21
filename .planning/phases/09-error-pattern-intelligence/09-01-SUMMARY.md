---
phase: 09-error-pattern-intelligence
plan: 01
subsystem: hooks
tags: [bash, jq, pattern-matching, adaptive-response, error-intelligence]

requires:
  - phase: 04-intelligence-layer
    provides: pattern-store.json schema, update_encounter_count, post-tool-use-failure.sh match logic

provides:
  - prune_pattern_store function (soft-cap at 50 patterns, keep highest encounter_count)
  - tier calculation in post-tool-use-failure.sh (full-explanation / brief-reminder / root-cause-flag)
  - safe jq --arg JSON construction replacing Phase 4 injection-vulnerable string interpolation
  - brain-mode.md tier-response instructions for adaptive agent verbosity

affects:
  - agents/brain-mode.md
  - hooks/post-tool-use-failure.sh
  - hooks/lib/brain-path.sh

tech-stack:
  added: []
  patterns:
    - "Atomic temp+mv writes with .tmp.$$ suffix (consistent across all brain-path.sh store ops)"
    - "jq --argjson for numeric args, --arg for string args in jq transforms"
    - "Numeric guard pattern: default to 0, grep -qE '^[0-9]+$' before arithmetic comparison"
    - "Read-after-write: call update function first, then re-read to get updated value"

key-files:
  created: []
  modified:
    - hooks/lib/brain-path.sh
    - hooks/post-tool-use-failure.sh
    - agents/brain-mode.md

key-decisions:
  - "prune called inside update_encounter_count after atomic write — prune only runs on successful increment, never on failed writes"
  - "COUNT numeric guard uses grep -qE not bash [[ ]] — ensures bash 3.2 compatibility"
  - "Tier thresholds: 1 = full, 2-4 = brief, 5+ = root-cause — matches RESEARCH.md recommendation"
  - "jq -n with --arg ctx replaces hand-assembled JSON string — fixes injection vulnerability from Phase 4"

patterns-established:
  - "Soft-cap pruning: sort_by(.encounter_count) | reverse | .[:$cap] keeps most-seen patterns"
  - "Tier injection via additionalContext: agent reads tier= label and varies verbosity accordingly"

duration: 12min
completed: 2026-03-21
---

# Phase 9 Plan 01: Error Pattern Intelligence Summary

**Encounter-count-aware adaptive error responses with soft-cap pruning — full explanation on first encounter, brief reminder on repeats 2-4, root-cause investigation flag on 5+, pattern store capped at 50 entries**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-03-21T22:48:14Z
- **Completed:** 2026-03-21T22:59:00Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added `prune_pattern_store` to `brain-path.sh` — removes least-used patterns when store exceeds 50, keeping highest-encounter entries. Called automatically at end of every `update_encounter_count`.
- Added tier calculation to `post-tool-use-failure.sh` — reads count after update, calculates tier label, constructs JSON via `jq --arg` (eliminates Phase 4 injection vulnerability).
- Extended `brain-mode.md` with explicit three-tier response instructions — agent now knows to vary verbosity based on `tier=` label injected into `additionalContext`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add prune_pattern_store to brain-path.sh** - `b6e9d09` (feat)
2. **Task 2: Tier calculation and safe JSON in post-tool-use-failure.sh** - `bd083ae` (feat)
3. **Task 3: Tier-response instructions in brain-mode.md** - `0c7c274` (feat)

## Files Created/Modified

- `hooks/lib/brain-path.sh` — added `prune_pattern_store` function + call site at end of `update_encounter_count`
- `hooks/post-tool-use-failure.sh` — added COUNT read-back, numeric guard, tier calculation, `jq -n --arg` JSON construction; removed hand-assembled JSON
- `agents/brain-mode.md` — replaced static "show past solution" with three-tier response behavior section

## Decisions Made

- `prune_pattern_store` is called inside `update_encounter_count` (not in the hook directly) — ensures pruning only runs after a successful write, and callers get pruning for free without knowing about it.
- COUNT guard uses `grep -qE '^[0-9]+$'` rather than bash arithmetic test — maintains bash 3.2 compatibility consistent with the rest of the library.
- Tier thresholds (1 / 2-4 / 5+) are hardcoded in the hook, not configurable — keeps the hook simple; thresholds can be made configurable in a future iteration if needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed missing `return 0` before prune call in update_encounter_count**

- **Found during:** Task 1 (adding prune call site)
- **Issue:** The original `mv` failure path fell through to `return 0` at the end of the function — once `prune_pattern_store "$store_path"` was inserted before that final `return 0`, the mv-failure path would have skipped the `return 0` after logging and continued to call prune on a potentially corrupted store. Added explicit `return 0` after the mv-failure log.
- **Fix:** Added `return 0` after `brain_log_error` in the mv-failure branch, before the prune call.
- **Files modified:** `hooks/lib/brain-path.sh`
- **Verification:** `bash -n hooks/lib/brain-path.sh` passes; prune call only reachable after successful mv.
- **Committed in:** `b6e9d09` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug fix)
**Impact on plan:** Necessary correctness fix. No scope creep.

## Issues Encountered

None — all three tasks executed cleanly against the plan spec.

## User Setup Required

None — no external service configuration required. Changes are purely to hook logic and agent instructions.

## Next Phase Readiness

- Phase 9 Plan 01 complete. Adaptive tier behavior and pattern store pruning are live.
- Phase 9 Plan 02 (if any) or Phase 10 can proceed immediately.
- No blockers.

---
*Phase: 09-error-pattern-intelligence*
*Completed: 2026-03-21*
