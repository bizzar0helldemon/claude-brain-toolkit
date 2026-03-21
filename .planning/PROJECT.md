# Claude Brain Mode

## What This Is

A dedicated "brain mode" for Claude Code CLI that transforms the brain toolkit from a collection of passive, manually-invoked skills into an active, autonomous knowledge partner. Launched via `claude --agent brain-mode`, it hooks into the full session lifecycle — loading relevant knowledge at start, capturing learnings after commits, surfacing past error solutions, and preserving context before clears. Works across any project directory with a single persistent brain vault.

## Core Value

The brain compounds over time — every session makes future sessions smarter by actively capturing and applying knowledge without the user having to ask.

## Requirements

### Validated

- ✓ HOOK-01: Stop hook loop guard baked into all brain mode hook templates — v1.0
- ✓ HOOK-02: Exit code discipline enforced (`exit 2` blocking, `exit 0` non-blocking) — v1.0
- ✓ HOOK-03: BRAIN_PATH validation on every hook invocation with clear error if missing/invalid — v1.0
- ✓ HOOK-04: JSON output self-test included in hook scaffolding template — v1.0
- ✓ STAT-01: Brain emoji in statusline when brain mode is active — v1.0
- ✓ LIFE-01: SessionStart loads relevant vault context for current project — v1.0
- ✓ LIFE-02: Pre-clear auto-capture triggers brain-capture before /clear — v1.0
- ✓ LIFE-03: Token budget management limits vault injection — v1.0
- ✓ LIFE-04: Milestone auto-capture after commits — v1.0
- ✓ LIFE-05: Error pattern recognition surfaces past solutions — v1.0
- ✓ ONBR-01: First-run guided setup for vault creation and BRAIN_PATH — v1.0
- ✓ ONBR-02: `claude --agent brain-mode` entry point — v1.0

### Active

- [ ] STOP-01: Smart stop hook — detect whether session produced capturable content before triggering capture
- [ ] STAT-02: Color-coded brain states in statusline (idle vs active processing)

### Future

- [ ] LIFE-06: Idle detection offers to summarize or capture current state when user pauses — deferred, fix intrusiveness first
- [ ] ONBR-03: Vault relocate command updates BRAIN_PATH if vault directory moves — utility, not UX-critical
- [ ] MENT-01: Pattern encounter tracking records frequency per pattern/pitfall — needs real usage data
- [ ] MENT-02: Progressive response changes behavior based on encounter count — same intrusiveness risk

### Out of Scope

- Multi-vault support — one brain per system keeps things simple
- Cloud sync — vault is local filesystem only, no external services
- Non-Claude-Code integrations — specifically for Claude Code CLI
- Mobile/web interface — CLI-only tool

## Current Milestone: v1.1 Quiet Brain

**Goal:** Reduce brain mode intrusiveness — make it helpful without being annoying.

**Target features:**
- Smart stop hook that only triggers capture when the session produced something worth capturing
- Color-coded statusline states that passively show brain activity without interrupting

## Context

Shipped v1.0 with ~1,580 LOC (shell + JSON).
Tech stack: Bash 3.2+/zsh 5.0+ shell scripts, jq 1.7.1, Claude Code hooks/agents/skills.
6 phases, 10 plans, 53 commits over 3 days.
Initial deployment covers 5 lifecycle hooks, 1 agent definition, 1 onboarding skill, 1 slash command, and a complete setup.sh installer.

## Constraints

- **Platform**: Claude Code CLI only — must work within its hook, skill, and statusline systems
- **Storage**: All brain data lives in the local vault at BRAIN_PATH — no external services
- **Performance**: Brain operations must not noticeably slow down normal Claude Code interactions
- **Compatibility**: Must work alongside existing brain toolkit skills without breaking them

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single vault, not multi-vault | Simplicity — one brain per human, one place to look | ✓ Good |
| Orchestrate existing skills first | Ship fast, learn what's missing from real usage | ✓ Good |
| BRAIN_PATH env var for vault location | Cross-directory access needs a stable reference point | ✓ Good |
| Adaptive mentoring deferred to v2 | Needs real vault data to tune thresholds safely | ✓ Good — avoids premature optimization |
| jq as hard dependency | Required for JSON validation in hooks | ✓ Good — reliable, available everywhere |
| BRAIN_PATH in both shell profile AND settings.json | Subshells don't load profiles | ✓ Good — solved cross-context access |
| Dual-channel errors (stderr + JSON stdout) | Humans see readable errors, Claude sees structured data | ✓ Good |
| emit_json exits 0 on invalid JSON | Formatting bugs must not break sessions | ✓ Good — resilient |
| Stop hook uses decision:block | Capture must be guaranteed before session ends | ✓ Good |
| PreCompact uses additionalContext (advisory) | Compaction cannot be blocked | ✓ Good |
| PostToolUse/Failure hooks synchronous | Filtering done in-script, no async race conditions | ✓ Good |
| /brain-scan is toolkit skill, not brain-mode artifact | Available Skills must only list deployed skills | ✓ Good — clear boundary |

| Fix intrusiveness before adding features | Stop hook firing 4x on empty sessions proved proactive features need intelligence before expansion | — Pending |

---
*Last updated: 2026-03-21 after v1.1 milestone started*
