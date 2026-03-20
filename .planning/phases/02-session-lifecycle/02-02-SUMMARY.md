---
phase: "02"
plan: "02"
subsystem: session-lifecycle
tags: [stop-hook, pre-compact-hook, brain-capture, daily-note, session-end, decision-block]
dependency_graph:
  requires:
    - phase: 02-01
      provides: brain-context library, session-start injection, vault query infrastructure
    - phase: 01-02
      provides: stop.sh and pre-compact.sh scaffolds with loop guard and BRAIN_PATH validation
  provides:
    - decision:block capture trigger on session end (stop.sh)
    - additionalContext capture trigger before compaction (pre-compact.sh)
    - complete Phase 2 session lifecycle loop (load at start, capture at end)
  affects: [03-onboarding, 04-intelligence]
tech_stack:
  added: []
  patterns:
    - "decision:block with jq -n --arg reason for safe multi-word reason strings"
    - "hookSpecificOutput.additionalContext for non-blocking PreCompact instruction injection"
    - "Loop guard (stop_hook_active check) prevents double-capture on second Stop fire"
key_files:
  created: []
  modified:
    - hooks/stop.sh
    - hooks/pre-compact.sh
key_decisions:
  - "Stop hook uses decision:block (not additionalContext) so capture is guaranteed before session ends"
  - "PreCompact uses additionalContext (not decision:block) because compaction cannot be blocked — instruction is advisory"
  - "Reason text instructs both /brain-capture and /daily-note in sequence, with confirmation notification requested"
  - "Loop guard from Phase 1 preserved exactly as-is — second Stop fire exits silently before any sourcing"
metrics:
  duration: "~5 minutes"
  completed: "2026-03-20"
  tasks_completed: 1
  tasks_total: 2
---

# Phase 2 Plan 02: Stop/PreCompact Capture Triggers Summary

**decision:block capture trigger in stop.sh and additionalContext instruction in pre-compact.sh, completing the Phase 2 session lifecycle loop: vault context loads at session start, knowledge is captured before session end or compaction.**

## Performance

- **Duration:** ~5 minutes
- **Completed:** 2026-03-20
- **Tasks:** 1 (+ 1 human-verify checkpoint approved)
- **Files modified:** 2

## Accomplishments

- Stop hook now emits `decision:block` with a reason instructing Claude to run `/brain-capture` then `/daily-note` before stopping, and confirm what was captured
- Pre-compact hook now emits `hookSpecificOutput.additionalContext` instructing Claude to run `/brain-capture` before context is reduced
- Both hooks log trigger events via `brain_log_error` for observability
- Phase 1 loop guard (stop_hook_active check) preserved intact — second Stop fire exits silently
- Full Phase 2 end-to-end verified by human: session start loads vault context, session end triggers capture

## Task Commits

| Task | Name | Commit |
|------|------|--------|
| 1 | Update stop.sh and pre-compact.sh with capture triggers | ff323d6 |
| 2 | Human-verify checkpoint | APPROVED |

## Files Created/Modified

- `hooks/stop.sh` — Updated from Phase 1 scaffold. Emits `decision:block` with capture + daily-note instructions on first fire; exits silently on second fire (loop guard preserved)
- `hooks/pre-compact.sh` — Updated from Phase 1 scaffold. Emits `hookSpecificOutput.additionalContext` with `/brain-capture` instruction before compaction

## Decisions Made

- Stop hook uses `decision:block` rather than `additionalContext`: capture must happen before session ends, blocking is appropriate here
- PreCompact uses `additionalContext` rather than `decision:block`: compaction cannot be blocked (hooks cannot prevent it), so the instruction is advisory
- Reason text includes both `/brain-capture` and `/daily-note` in sequence with a confirmation request — user sees "Brain captured: N learnings, daily note updated" style output
- `jq -n --arg reason "$REASON"` used for JSON construction (reason string contains quotes and spaces — never string concatenation)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

Phase 2 complete. Phase 3 (Onboarding + Entry Point) is the next milestone:
- Stop and PreCompact hooks fully operational
- Session lifecycle loop complete: start → load context, end → capture knowledge
- Phase 3 needs concrete design before planning: two distinct onboarding cases (BRAIN_PATH unset vs set but vault empty) need different flows

Blockers carried forward:
- Phase 3 onboarding UX needs concrete design before planning
- Verify at Phase 3: whether `skills` frontmatter in `agents/brain-mode.md` preloads brain-* skills at session start

---

## Self-Check

| Item | Status |
|------|--------|
| hooks/stop.sh | FOUND |
| hooks/pre-compact.sh | FOUND |
| .planning/phases/02-session-lifecycle/02-02-SUMMARY.md | FOUND |
| Commit ff323d6 (Task 1) | FOUND |

## Self-Check: PASSED

---
*Phase: 02-session-lifecycle*
*Completed: 2026-03-20*
