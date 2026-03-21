---
phase: 04-intelligence-layer
plan: "02"
subsystem: hooks, commands, agents
tags: [post-tool-use-failure, error-pattern-recognition, pattern-store, brain-add-pattern, intelligence-layer]
requires:
  - hooks/lib/brain-path.sh
  - hooks/post-tool-use-failure.sh
  - "04-01: PostToolUseFailure hook registration in settings.json"
provides:
  - "$BRAIN_PATH/brain-mode/pattern-store.json (runtime, via init_pattern_store)"
  - hooks/lib/brain-path.sh (init_pattern_store, update_encounter_count)
  - commands/brain-add-pattern.md
affects:
  - hooks/post-tool-use-failure.sh (extended with pattern matching)
  - agents/brain-mode.md (new skill + error recognition section)
tech-stack:
  added: []
  patterns:
    - Atomic temp+mv writes for JSON store updates (already used elsewhere, now applied to pattern store)
    - ". as $p" jq binding to access object fields inside contains() after pipe context
    - Write-tool initialization for skill-driven store creation (avoid shell sourcing in agent context)
key-files:
  created:
    - commands/brain-add-pattern.md
  modified:
    - hooks/lib/brain-path.sh
    - hooks/post-tool-use-failure.sh
    - agents/brain-mode.md
key-decisions:
  - Use ". as $p" jq variable binding — required because .key inside contains() resolves in string context after pipe, not object context
  - Write tool (not source brain-path.sh) for pattern store initialization from skill — more reliable in agent runtime context
  - additionalContext returned as hookSpecificOutput JSON (not decision:block) — PostToolUseFailure cannot block tool use
  - No exit 1 paths in post-tool-use-failure.sh — Phase 1 oversight fixed; hook must always exit 0
patterns-established:
  - jq pattern: ". as $p | select(contains($p.field))" required when referencing object fields inside string-pipe operations
  - Pattern store uses encounter_count + last_seen for analytics; hook increments atomically on each match
  - Skills that write to the vault initialize stores with Write tool, not shell sourcing
duration: "~3 minutes"
completed: "2026-03-21"
---

# Phase 4 Plan 02: Error Pattern Recognition Summary

**One-liner:** PostToolUseFailure hook matches bash errors against a JSON pattern store and injects past solutions into Claude's context via additionalContext, with encounter count tracking and a /brain-add-pattern skill for populating the store.

## Accomplishments

- Extended `post-tool-use-failure.sh` with pattern matching: reads `$BRAIN_PATH/brain-mode/pattern-store.json`, matches error message and command against stored pattern keys (case-insensitive, jq-based), and injects the solution via `additionalContext` when a match is found
- Added `init_pattern_store` to `brain-path.sh`: creates the store directory and file with a valid empty schema on first use, no-op if already exists, atomic temp+mv write
- Added `update_encounter_count` to `brain-path.sh`: increments `encounter_count` and sets `last_seen` for all matching patterns atomically
- Fixed Phase 1 oversight: changed `exit 1` after `brain_path_validate` failure to `exit 0` — PostToolUseFailure must never block tool use
- Created `commands/brain-add-pattern.md`: full skill with 6-step workflow for pattern creation using Write tool initialization (not shell sourcing)
- Updated `agents/brain-mode.md`: added `/brain-add-pattern` to Available Skills list and new "Error Pattern Recognition" section

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Pattern store utilities + hook extension | 536ef68 | hooks/lib/brain-path.sh, hooks/post-tool-use-failure.sh |
| 2 | /brain-add-pattern skill + agent update | 4990968 | commands/brain-add-pattern.md, agents/brain-mode.md |

## Files Created

- `commands/brain-add-pattern.md` — Slash command skill for populating the pattern store

## Files Modified

- `hooks/lib/brain-path.sh` — Added `init_pattern_store` and `update_encounter_count` functions
- `hooks/post-tool-use-failure.sh` — Extended with pattern matching, fixed exit 1 bug, added COMMAND extraction
- `agents/brain-mode.md` — Added skill listing and Error Pattern Recognition section

## Decisions Made

1. **jq `. as $p` binding required** — `.key` inside `contains(.key | ascii_downcase)` evaluates in the string context of the piped value, not the object context. Fixed to `. as $p | select(contains($p.key | ascii_downcase))`. This was discovered during verification testing and auto-fixed under Rule 1 (Bug).

2. **Write tool for skill initialization** — Skills that create the pattern store should use the Write tool directly, not source shell library functions. Shell sourcing is fragile in agent runtime contexts.

3. **exit 0 on all paths** — PostToolUseFailure hooks must never block tool use. The existing `exit 1` was a Phase 1 oversight, auto-fixed under Rule 1.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] jq "Cannot index string with string 'key'" in contains() calls**
- **Found during:** Task 1 verification testing
- **Issue:** Both the pattern-matching select in `post-tool-use-failure.sh` and the update logic in `update_encounter_count` used `.key` inside a `contains()` call after a pipe. jq evaluates `.key` in the string context of the piped value, not the parent object context, resulting in "Cannot index string with string 'key'" at runtime.
- **Fix:** Added `. as $p` binding before the `select()` / `if` expression so `$p.key` correctly references the pattern object's key field.
- **Files modified:** `hooks/post-tool-use-failure.sh`, `hooks/lib/brain-path.sh`
- **Commit:** 536ef68

## Next Phase Readiness

Phase 4 is complete. Both plans (04-01: git commit detection, 04-02: error pattern recognition) are implemented. The intelligence layer is operational:

- PostToolUse detects git commits and offers brain-capture
- PostToolUseFailure matches errors against the pattern store and injects past solutions
- The pattern store can be populated via /brain-add-pattern
- All hooks exit 0 on all paths (graceful degradation)

The system is ready for real-world usage. Next steps are documentation and user onboarding rather than new feature development.

## Self-Check: PASSED

All files present: hooks/lib/brain-path.sh, hooks/post-tool-use-failure.sh, commands/brain-add-pattern.md, agents/brain-mode.md, .planning/phases/04-intelligence-layer/04-02-SUMMARY.md
All commits present: 536ef68, 4990968
