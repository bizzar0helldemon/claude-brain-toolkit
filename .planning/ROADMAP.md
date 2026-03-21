# Roadmap: Claude Brain Mode

## Overview

Claude Brain Mode transforms the claude-brain-toolkit from a set of manually-invoked skills into an active, autonomous knowledge partner. The build follows a strict dependency chain — hook infrastructure first, then session lifecycle automation built on top of it, then first-run onboarding to safely hand the system to real users, then advanced intelligence features (auto-capture at milestones, error pattern recognition) that need a populated vault to be useful. Every phase delivers a coherent, independently verifiable capability before the next layer is built.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Hook Infrastructure** - Safe, validated hook scaffolding with BRAIN_PATH library, stop-loop guard, exit code discipline, and brain statusline indicator (completed 2026-03-20)
- [x] **Phase 2: Session Lifecycle** - Automatic vault context injection at session start, pre-clear capture, and token budget management (completed 2026-03-20)
- [x] **Phase 3: Onboarding + Entry Point** - First-run guided setup and `claude --agent brain-mode` launch path (completed 2026-03-21)
- [x] **Phase 4: Intelligence Layer** - Milestone auto-capture and error pattern recognition on top of a populated vault (completed 2026-03-21)
- [ ] **Phase 5: Deploy Phase 4 Artifacts** - Update setup.sh to deploy post-tool-use.sh, register PostToolUse hook, and deploy commands/ directory (Gap Closure)
- [ ] **Phase 6: Resolve /brain-scan Reference** - Remove dangling /brain-scan reference from brain-mode.md (Gap Closure)

## Phase Details

### Phase 1: Hook Infrastructure
**Goal**: Brain mode has a safe, working hook scaffold that all future features are built on
**Depends on**: Nothing (first phase)
**Requirements**: HOOK-01, HOOK-02, HOOK-03, HOOK-04, STAT-01
**Success Criteria** (what must be TRUE):
  1. A hook fires at each lifecycle event (SessionStart, PreCompact, Stop, PostToolUseFailure) and completes without looping
  2. Attempting a blocking hook with `exit 1` does NOT block tool execution; using `exit 2` does
  3. Running a hook when BRAIN_PATH is unset or invalid produces a specific, actionable error message rather than silently writing to a wrong path
  4. Hook JSON output passes `| jq .` validation without corruption from shell profile output
  5. Brain emoji appears in the Claude Code statusline whenever brain mode is active
**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md — BRAIN_PATH validation library + settings.json hook registration
- [x] 01-02-PLAN.md — Lifecycle hook scripts (all 4) + statusline script

### Phase 2: Session Lifecycle
**Goal**: Every session automatically loads relevant vault context, and knowledge is captured before context is cleared
**Depends on**: Phase 1
**Requirements**: LIFE-01, LIFE-02, LIFE-03
**Success Criteria** (what must be TRUE):
  1. Opening a project in brain mode surfaces that project's recent pitfalls and last-known state without the user asking
  2. Invoking `/clear` triggers an automatic brain-capture and daily-note entry before the context is wiped
  3. SessionStart vault injection stays under 2,000 tokens (verifiable via `claude --verbose`) so session length is not noticeably shortened
**Plans:** 2 plans

Plans:
- [x] 02-01-PLAN.md — Brain context library (vault query, token budget, project matching) + SessionStart context injection
- [x] 02-02-PLAN.md — Stop/PreCompact capture triggers + end-to-end verification

### Phase 3: Onboarding + Entry Point
**Goal**: Any user can start brain mode from scratch and have a working vault within one guided session
**Depends on**: Phase 2
**Requirements**: ONBR-01, ONBR-02
**Success Criteria** (what must be TRUE):
  1. A user with no BRAIN_PATH set runs `claude --agent brain-mode` and is guided step-by-step to create a vault directory and set the env var — no manual documentation needed
  2. After onboarding completes, running `claude --agent brain-mode` in any project directory loads brain mode with vault context from BRAIN_PATH
  3. A user whose vault directory has moved can re-run onboarding and the new path is picked up by all subsequent hooks without editing config files manually
**Plans:** 2 plans

Plans:
- [x] 03-01-PLAN.md — brain-mode.md agent definition + brain-setup onboarding wizard skill
- [x] 03-02-PLAN.md — setup.sh installer rewrite + project settings.json agent default + deployment verification

### Phase 4: Intelligence Layer
**Goal**: Brain mode actively captures knowledge at meaningful moments and surfaces past error solutions without the user invoking any commands
**Depends on**: Phase 3
**Requirements**: LIFE-04, LIFE-05
**Success Criteria** (what must be TRUE):
  1. After a `git commit` or PR merge, a brain-capture entry is automatically created in the vault without any user action
  2. When an error occurs that matches a pattern already in the vault, the brain surfaces the past solution in the current session context
  3. The pattern store (`pattern-store.json`) records encounter counts that increment correctly across sessions, verifiable by inspecting the file
**Plans:** 2 plans

Plans:
- [x] 04-01-PLAN.md — PostToolUse git commit detection hook + settings.json registration
- [x] 04-02-PLAN.md — Error pattern recognition in PostToolUseFailure + pattern store + /brain-add-pattern skill

### Phase 5: Deploy Phase 4 Artifacts
**Goal**: All Phase 4 artifacts are deployed by setup.sh so git commit capture and error pattern recognition work post-install
**Depends on**: Phase 4
**Requirements**: LIFE-04 (full), LIFE-05 (full)
**Gap Closure:** Closes gaps from v1.0 milestone audit
**Success Criteria** (what must be TRUE):
  1. After running setup.sh, post-tool-use.sh exists in ~/.claude/hooks/ and PostToolUse is registered in ~/.claude/settings.json
  2. After running setup.sh, commands/brain-add-pattern.md is deployed to ~/.claude/commands/
  3. E2E Flow 3 (git commit capture) and Flow 4 (pattern addition) work end-to-end post-install
**Plans:** TBD

### Phase 6: Resolve /brain-scan Reference
**Goal**: brain-mode.md contains no dangling references to non-existent artifacts
**Depends on**: Nothing
**Requirements**: None (integration cleanup)
**Gap Closure:** Closes gaps from v1.0 milestone audit
**Success Criteria** (what must be TRUE):
  1. brain-mode.md does not reference /brain-scan as a brain-mode artifact (it's an existing toolkit skill, not a brain-mode hook)
**Plans:** TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Hook Infrastructure | 2/2 | Complete | 2026-03-20 |
| 2. Session Lifecycle | 2/2 | Complete | 2026-03-20 |
| 3. Onboarding + Entry Point | 2/2 | Complete | 2026-03-21 |
| 4. Intelligence Layer | 2/2 | Complete | 2026-03-21 |
| 5. Deploy Phase 4 Artifacts | 0/? | Pending | — |
| 6. Resolve /brain-scan Reference | 0/? | Pending | — |
