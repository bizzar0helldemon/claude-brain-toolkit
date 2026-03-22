# Roadmap: Claude Brain Mode

## Milestones

- ✅ **v1.0 Claude Brain Mode MVP** - Phases 1-6 (shipped 2026-03-21)
- ✅ **v1.1 Quiet Brain** - Phases 7-8 (shipped 2026-03-21)
- 🚧 **v1.2 Polish & Intelligence** - Phases 9-11 (in progress)

## Phases

<details>
<summary>✅ v1.0 Claude Brain Mode MVP (Phases 1-6) - SHIPPED 2026-03-21</summary>

See full details: `.planning/milestones/v1.0-ROADMAP.md`

### Phase 1: Hook Infrastructure
**Goal**: Brain mode has a safe, working hook scaffold that all future features are built on
**Plans**: 2 plans

Plans:
- [x] 01-01: BRAIN_PATH validation library + settings.json hook registration
- [x] 01-02: Lifecycle hook scripts (all 4) + statusline script

### Phase 2: Session Lifecycle
**Goal**: Every session automatically loads relevant vault context, and knowledge is captured before context is cleared
**Plans**: 2 plans

Plans:
- [x] 02-01: Brain context library (vault query, token budget, project matching) + SessionStart context injection
- [x] 02-02: Stop/PreCompact capture triggers + end-to-end verification

### Phase 3: Onboarding + Entry Point
**Goal**: Any user can start brain mode from scratch and have a working vault within one guided session
**Plans**: 2 plans

Plans:
- [x] 03-01: brain-mode.md agent definition + brain-setup onboarding wizard skill
- [x] 03-02: setup.sh installer rewrite + project settings.json agent default + deployment verification

### Phase 4: Intelligence Layer
**Goal**: Brain mode actively captures knowledge at meaningful moments and surfaces past error solutions without the user invoking any commands
**Plans**: 2 plans

Plans:
- [x] 04-01: PostToolUse git commit detection hook + settings.json registration
- [x] 04-02: Error pattern recognition in PostToolUseFailure + pattern store + /brain-add-pattern skill

### Phase 5: Deploy Phase 4 Artifacts (Gap Closure)
**Goal**: All Phase 4 artifacts are deployed by setup.sh so git commit capture and error pattern recognition work post-install
**Plans**: 1 plan

Plans:
- [x] 05-01: Update setup.sh to deploy post-tool-use.sh hook and brain-add-pattern.md command

### Phase 6: Resolve /brain-scan Reference (Gap Closure)
**Goal**: brain-mode.md contains no dangling references to non-existent artifacts
**Plans**: 1 plan

Plans:
- [x] 06-01: Remove dangling /brain-scan references from brain-mode.md

</details>

<details>
<summary>✅ v1.1 Quiet Brain (Phases 7-8) - SHIPPED 2026-03-21</summary>

### Phase 7: Smart Stop Hook
**Goal**: The stop hook only triggers capture when the session produced something worth capturing
**Depends on**: Phase 6 (v1.0 stop hook exists as the baseline)
**Requirements**: STOP-01, STOP-02, STOP-03
**Success Criteria** (what must be TRUE):
  1. A session with tool usage, code changes, or git commits triggers capture as normal
  2. A trivial session (few messages, no code/commits/decisions) exits without triggering capture and without any visible output
  3. The hook exits 0 (non-blocking) when no capturable content is detected, and exits 2 (blocking) only when capture is warranted
  4. The detection logic checks for concrete signals: tool calls made, files changed, commits present, error resolutions attempted

**Plans**: 1 plan

Plans:
- [x] 07-01-PLAN.md — Add transcript signal detection to stop.sh

### Phase 8: Statusline States
**Goal**: The statusline passively communicates brain activity at a glance without requiring any user action
**Depends on**: Phase 7 (hook activity that drives state transitions)
**Requirements**: STAT-02, STAT-03
**Success Criteria** (what must be TRUE):
  1. Statusline shows 🧠 during a normal idle session (brain active, no recent hook activity)
  2. Statusline shows 🟢🧠 after a session where capture ran successfully
  3. Statusline shows 🔴🧠 when a hook error or degraded state is detected
  4. State transitions happen automatically as hook outcomes change — no user command needed

**Plans**: 1 plan

Plans:
- [x] 08-01-PLAN.md — Add state file writes to hooks + state-aware statusline display

</details>

### 🚧 v1.2 Polish & Intelligence (In Progress)

**Milestone Goal:** Make brain mode smarter and more manageable — adaptive error intelligence, vault portability, and ambient session awareness.

#### Phase 9: Error Pattern Intelligence
**Goal**: Brain mode delivers progressively smarter responses to recurring errors — not repeating the same explanation every time
**Depends on**: Phase 4 (error pattern store exists as baseline)
**Requirements**: MENT-01, MENT-02
**Plans**: 1 plan
**Success Criteria** (what must be TRUE):
  1. After each error match, encounter_count for that pattern increments in the pattern store (verifiable by inspecting the store file)
  2. The pattern store never grows unbounded — a soft-cap prune removes the least-used patterns when the cap is exceeded
  3. On first encounter of a known error, brain mode gives a full explanation with solution steps
  4. On encounters 2-4 of the same error, brain mode gives a brief reminder note instead of the full explanation
  5. On encounter 5+, brain mode flags the pattern for root cause investigation rather than repeating the solution

Plans:
- [x] 09-01-PLAN.md — Prune function, tier calculation, safe JSON, agent tier-response instructions

#### Phase 10: Vault Relocation
**Goal**: A user can move their vault to a new path without manual config surgery
**Depends on**: Phase 3 (settings.json and shell profile conventions established)
**Requirements**: ONBR-03
**Plans**: 1 plan
**Success Criteria** (what must be TRUE):
  1. Running `/brain-relocate` prompts the user for the new vault path and validates it exists
  2. After relocation, BRAIN_PATH in settings.json reflects the new path
  3. After relocation, BRAIN_PATH in the user's shell profile reflects the new path
  4. A post-relocate verification confirms brain mode can read the vault at the new path before declaring success

Plans:
- [x] 10-01-PLAN.md — Create /brain-relocate slash command + setup.sh deployment + brain-mode.md listing

#### Phase 11: Idle Capture Offer
**Goal**: Brain mode notices when the user has paused and quietly offers to capture if the session has something worth capturing
**Depends on**: Phase 7 (capturable-content detection logic from stop.sh)
**Requirements**: LIFE-06
**Plans**: 1 plan
**Success Criteria** (what must be TRUE):
  1. When the user is idle and the session has capturable content, brain mode offers to capture once
  2. The offer does not fire again in the same session regardless of further idle periods (one-offer-per-session guard)
  3. When the session has no capturable content, idle detection stays silent
  4. The offer fires via the idle hook without blocking or slowing down the session

Plans:
- [ ] 11-01-PLAN.md — Shared content detection, notification-idle.sh hook, one-offer guard, deployment

## Progress

**Execution Order:** Phases execute in numeric order: 9 → 10 → 11

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Hook Infrastructure | v1.0 | 2/2 | Complete | 2026-03-21 |
| 2. Session Lifecycle | v1.0 | 2/2 | Complete | 2026-03-21 |
| 3. Onboarding + Entry Point | v1.0 | 2/2 | Complete | 2026-03-21 |
| 4. Intelligence Layer | v1.0 | 2/2 | Complete | 2026-03-21 |
| 5. Deploy Phase 4 Artifacts | v1.0 | 1/1 | Complete | 2026-03-21 |
| 6. Resolve /brain-scan Reference | v1.0 | 1/1 | Complete | 2026-03-21 |
| 7. Smart Stop Hook | v1.1 | 1/1 | Complete | 2026-03-21 |
| 8. Statusline States | v1.1 | 1/1 | Complete | 2026-03-21 |
| 9. Error Pattern Intelligence | v1.2 | 1/1 | Complete | 2026-03-21 |
| 10. Vault Relocation | v1.2 | 1/1 | Complete | 2026-03-21 |
| 11. Idle Capture Offer | v1.2 | 0/1 | Planned | — |
