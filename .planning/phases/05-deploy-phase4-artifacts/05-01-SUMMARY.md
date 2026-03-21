---
phase: "05-deploy-phase4-artifacts"
plan: "01"
subsystem: "onboarding"
tags: ["setup", "hooks", "commands", "deployment", "installer"]
dependency_graph:
  requires: ["hooks/post-tool-use.sh", "commands/brain-add-pattern.md"]
  provides: ["onboarding-kit/setup.sh deploys all Phase 4 artifacts"]
  affects: ["onboarding-kit/setup.sh", "~/.claude/hooks/", "~/.claude/commands/brain/", "~/.claude/settings.json"]
tech_stack:
  added: []
  patterns:
    - "Idempotent jq merge for settings.json hook registration"
    - "Separate cleanup jq pass to strip async:true from existing installs"
key_files:
  modified:
    - "onboarding-kit/setup.sh"
decisions:
  - "Added Phase 5b step between Phase 5 (statusline) and Phase 6 (settings merge) — maintains logical ordering without renumbering existing phases"
  - "cleanup jq pass placed after merge pass — ensures async:true stripped even if command was already registered before this update"
metrics:
  duration: "~2 minutes"
  completed: "2026-03-21"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 05 Plan 01: Deploy Phase 4 Artifacts via setup.sh Summary

**One-liner:** Updated setup.sh to deploy post-tool-use.sh hook and brain-add-pattern.md slash command, register PostToolUse in settings.json, and strip legacy async:true from PostToolUseFailure for existing installs.

## What Was Built

setup.sh was written during Phase 3 and deployed Phases 1-3 artifacts only. This plan bridges the gap so fresh installs receive all Phase 4 artifacts automatically.

Four targeted edits were made to `onboarding-kit/setup.sh`:

1. **Hook deployment (Phase 4 section):** Added `cp` for `post-tool-use.sh` alongside the four existing hook scripts.

2. **Slash command deployment (new Phase 5b section):** Added section between Phase 5 (statusline) and Phase 6 (settings merge) that creates `~/.claude/commands/brain/` and copies `brain-add-pattern.md` into it.

3. **BRAIN_HOOKS heredoc update:** Removed `"async":true` from PostToolUseFailure entry; added PostToolUse entry pointing to `post-tool-use.sh`. No async fields in any hook definition.

4. **Verification section:** Added `check_file` lines for `post-tool-use.sh` and `commands/brain/brain-add-pattern.md`; added settings.json check for PostToolUse hook registration.

Additionally, a targeted cleanup jq pass was added immediately after the main merge block to strip `async:true` from PostToolUseFailure for users who ran an older version of setup.sh.

## Verification Results

- `bash -n onboarding-kit/setup.sh` — exits 0 (syntax valid)
- BRAIN_HOOKS heredoc is valid JSON (jq parses cleanly)
- PostToolUse key present in BRAIN_HOOKS, references `post-tool-use.sh`
- No `async` keys anywhere in BRAIN_HOOKS definition
- `check_file` coverage: 14 artifacts now verified (was 12)
- PostToolUse settings.json check added alongside existing SessionStart check

## Success Criteria Verification

| Criterion | Status |
|-----------|--------|
| setup.sh deploys all 5 hook scripts (incl. post-tool-use.sh) | PASS |
| setup.sh deploys brain-add-pattern.md to commands/brain/ | PASS |
| setup.sh registers PostToolUse in settings.json | PASS |
| setup.sh removes async:true from PostToolUseFailure for existing installs | PASS |
| setup.sh verifies all new artifacts in verification section | PASS |
| Script passes bash -n syntax validation | PASS |

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: Add Phase 4 artifact deployment | `0cc6589` | feat(05-01): deploy Phase 4 artifacts in setup.sh |
| Task 2: Dry-run verification | n/a | Verification only — no file changes |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- onboarding-kit/setup.sh — FOUND
- .planning/phases/05-deploy-phase4-artifacts/05-01-SUMMARY.md — FOUND
- commit 0cc6589 — FOUND
