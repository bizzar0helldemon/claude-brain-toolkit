---
phase: 03-onboarding-entry-point
plan: "01"
subsystem: agents-and-skills
tags: [brain-mode, onboarding, subagent, skill, brain-setup]
dependency_graph:
  requires: []
  provides:
    - agents/brain-mode.md
    - onboarding-kit/skills/brain-setup/SKILL.md
  affects:
    - onboarding-kit/setup.sh (Plan 02 deploys these files)
tech_stack:
  added: []
  patterns:
    - Subagent definition with frontmatter (name, description, tools, model)
    - Skill definition with frontmatter (name, description) + guided conversation body
key_files:
  created:
    - agents/brain-mode.md
    - onboarding-kit/skills/brain-setup/SKILL.md
  modified: []
decisions:
  - No `skills:` frontmatter field in brain-mode.md — behavior for main-thread agents is unverified; defer until live testing confirms it works
metrics:
  duration: "~2 minutes"
  completed: 2026-03-21
---

# Phase 3 Plan 01: Brain-Mode Subagent + Brain-Setup Skill Summary

## One-liner

brain-mode subagent with three-state startup handling and brain-setup wizard covering BRAIN_PATH-unset and directory-missing cases.

## What Was Built

### agents/brain-mode.md
Subagent definition for `claude --agent brain-mode`. Frontmatter: `name: brain-mode`, `tools: Read, Write, Edit, Bash, Grep, Glob, Agent`, `model: inherit`. No `skills:` field (deferred — see decisions).

System prompt handles three distinct startup states:
- **(a) No hook output** — hooks not deployed; tells user to run `bash onboarding-kit/setup.sh`
- **(b) Degraded context** (`degraded: true` or `BRAIN_PATH is not set`) — hooks installed but BRAIN_PATH unconfigured; offers `/brain-setup`
- **(c) Normal context** — vault loaded; acknowledges briefly and proceeds

Also covers: proactive `/brain-capture` offers after significant work, empty-vault hint to run `/brain-scan`, full list of available skills.

Word count: 559 (under 800 limit).

### onboarding-kit/skills/brain-setup/SKILL.md
First-time onboarding wizard. Frontmatter: `name: brain-setup`.

Handles two cases:
- **Case A: BRAIN_PATH unset** — prompts user for vault path, creates directory, writes BRAIN_PATH to `settings.json` via jq, writes to shell profile, instructs restart
- **Case B: Directory missing** (`offer_create: true`) — offers create-in-place or update to new location

Includes:
- Concrete bash code blocks for settings.json jq mutation and shell profile update
- jq fallback: use Write/Edit tool if jq unavailable
- Windows Git Bash note: settings.json is the primary reliable channel; shell profile is secondary
- Restart instruction for Case A

Word count: 435 (under 600 limit).

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1: brain-mode.md | 78ee3d4 | feat(03-01): create brain-mode subagent definition |
| Task 2: brain-setup SKILL.md | 3311bf6 | feat(03-01): create brain-setup onboarding wizard skill |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- `agents/brain-mode.md` — FOUND
- `onboarding-kit/skills/brain-setup/SKILL.md` — FOUND
- Commit 78ee3d4 — FOUND
- Commit 3311bf6 — FOUND
