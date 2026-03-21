---
phase: 03-onboarding-entry-point
plan: "02"
subsystem: installer-and-entry-point
tags: [setup, installer, deployment, settings, agent-default, idempotent]
dependency_graph:
  requires:
    - agents/brain-mode.md (from 03-01)
    - onboarding-kit/skills/brain-setup/SKILL.md (from 03-01)
    - hooks/session-start.sh, hooks/stop.sh, hooks/pre-compact.sh, hooks/post-tool-use-failure.sh (from 01-02)
    - hooks/lib/brain-path.sh, hooks/lib/brain-context.sh (from 02-01)
    - statusline.sh (from 01-02)
  provides:
    - onboarding-kit/setup.sh (complete installer)
    - settings.json with agent: brain-mode default
  affects:
    - ~/.claude/agents/brain-mode.md (deployed by setup.sh)
    - ~/.claude/skills/ (all brain skills deployed by setup.sh)
    - ~/.claude/hooks/ (all hook scripts deployed by setup.sh)
    - ~/.claude/settings.json (merged by setup.sh — idempotent)
tech_stack:
  added: []
  patterns:
    - Portable sed via temp-file pattern (sed "s|...|...|" file > file.tmp && mv file.tmp file) — no sed -i
    - Idempotent jq merge for ~/.claude/settings.json (checks command string before appending hooks)
    - REPO_DIR derived from KIT_DIR to locate source files from any working directory
key_files:
  created: []
  modified:
    - onboarding-kit/setup.sh
    - settings.json
decisions:
  - No interactive prompts (read -p) in setup.sh — vault path onboarding is handled by /brain-setup skill inside Claude Code
  - setup.sh does NOT install GSD or Superpowers — those are separate concerns not owned by brain mode
  - Idempotent hook merge via jq command-string check — running setup.sh twice is safe
metrics:
  duration: "~3 minutes"
  completed: 2026-03-21
---

# Phase 3 Plan 02: setup.sh Installer + Deployment Verification Summary

## One-liner

setup.sh installer deploying agent, all skills (with portable sed template substitution), hooks, statusline, and idempotent settings.json hook merge — verified end-to-end with `claude --agent brain-mode` and statusline active.

## What Was Built

### onboarding-kit/setup.sh (rewritten)

Complete brain mode installer. Determines `REPO_DIR` from `KIT_DIR` (the `onboarding-kit/` directory the script lives in) to correctly locate all source files regardless of working directory.

Nine deployment phases:
- **Phase 1: Prerequisites** — checks node, git, claude, jq (hard dependency added)
- **Phase 2: Deploy brain-mode agent** — copies `agents/brain-mode.md` to `~/.claude/agents/`
- **Phase 3: Deploy global skills** — copies brain-capture, daily-note, brain-audit from `global-skills/`; copies brain-setup from `onboarding-kit/skills/`; runs portable sed substitution on all `{{SET_YOUR_BRAIN_PATH}}` placeholders (replaces with literal `$BRAIN_PATH` env var reference)
- **Phase 4: Deploy hook scripts** — copies all 4 hooks + 2 lib files to `~/.claude/hooks/`; sets executable bit with `chmod +x`
- **Phase 5: Deploy statusline** — copies `statusline.sh` to `~/.claude/statusline.sh`
- **Phase 6: Update ~/.claude/settings.json** — idempotent jq merge: for each brain hook type (SessionStart, PreCompact, Stop, PostToolUseFailure), checks if command string already registered before appending; sets statusLine; writes atomically via temp file
- **Phase 7: BRAIN_PATH configuration** — if set and directory exists: confirms; if set but missing: warns to run /brain-setup; if unset: instructs user to run /brain-setup after starting Claude
- **Phase 8: Verification** — `[ -f ... ]` assertions for all deployed files; jq check for session-start.sh in settings
- **Phase 9: Next steps** — prints "Setup complete! Start brain mode: claude --agent brain-mode"

Removed: GSD installation, Superpowers plugin, git clone vault creation, `read -p` interactive prompts, old hardcoded-path sed substitution.

### settings.json (updated)

Added `"agent": "brain-mode"` at the top level. All existing hooks, env placeholder, and statusLine fields preserved unchanged. Makes brain mode the default agent when running `claude` from the toolkit project directory.

## Commits

| Task | Commit | Description | Files |
|------|--------|-------------|-------|
| Task 1: Rewrite setup.sh | a617c88 | feat(03-02): rewrite setup.sh to deploy all brain mode components | onboarding-kit/setup.sh |
| Task 2: settings.json agent default | 4b872c1 | feat(03-02): add agent: brain-mode default to project settings.json | settings.json |

## Verification Results (Human-Approved)

Checkpoint approved after running `bash onboarding-kit/setup.sh`:
- Setup script completed without errors
- All files deployed: `~/.claude/agents/brain-mode.md`, `~/.claude/skills/brain-setup/SKILL.md`, `~/.claude/hooks/session-start.sh`, `~/.claude/hooks/lib/brain-context.sh`
- `~/.claude/settings.json` contains both brain hooks and existing gsd hooks (preserved)
- `claude --agent brain-mode` starts successfully
- Brain statusline emoji appears in the statusline

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `onboarding-kit/setup.sh` — FOUND
- `settings.json` — FOUND
- Commit a617c88 — FOUND
- Commit 4b872c1 — FOUND
