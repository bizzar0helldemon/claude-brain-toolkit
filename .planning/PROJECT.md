# Claude Brain Mode

## What This Is

A dedicated "brain mode" for Claude Code CLI that transforms the brain toolkit from a collection of passive, manually-invoked skills into an active, autonomous knowledge partner. Launched via `claude --brain`, it hooks into the full session lifecycle — loading relevant knowledge at start, capturing learnings throughout, and preserving context before clears. It works across any project directory while maintaining a single persistent brain vault.

## Core Value

The brain compounds over time — every session makes future sessions smarter by actively capturing and applying knowledge without the user having to ask.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] `claude --brain` launch flag enters brain mode
- [ ] Brain emoji appears in statusline left of model name
- [ ] Color-coded brain states in statusline (idle vs active processing)
- [ ] Pre-clear hooks auto-trigger `/brain-capture` then `/daily-note` before `/clear`
- [ ] Session start: brain loads relevant vault context for current project (past pitfalls, preferences, where user left off)
- [ ] Error pattern recognition: brain detects recurring errors and surfaces past knowledge
- [ ] Milestone auto-capture: brain captures learnings after commits, PR merges, phase completions
- [ ] Idle detection: brain offers to summarize or capture current state when user pauses
- [ ] Adaptive mentoring: first encounters get proactive warnings, repeated patterns get silent correction, persistent issues trigger root cause investigation
- [ ] Pattern awareness tracking: brain tracks encounter frequency per pattern to drive adaptive mentoring behavior
- [ ] Knowledge flows brain→session: pitfalls, solutions, communication preferences, project patterns
- [ ] Knowledge flows session→brain: new learnings, captures, daily notes
- [ ] Cross-directory operation: brain reads/writes to vault while user works in any project directory
- [ ] First-run guided onboarding: walks user through creating brain vault directory and setting BRAIN_PATH
- [ ] BRAIN_PATH env var: stable vault location used by all brain operations
- [ ] Vault relocate command: update brain path if vault directory moves

### Out of Scope

- New brain skills beyond orchestration — will emerge from usage, not pre-designed
- Multi-vault support — one brain per system keeps things simple
- Cloud sync — vault is local filesystem only
- Non-Claude-Code integrations — this is specifically for the Claude Code CLI

## Context

The claude-brain-toolkit already has a set of working skills: `/brain-capture`, `/brain-intake`, `/brain-discover`, `/brain-inbox`, `/brain-scan`, `/daily-note`. These work well when manually invoked but require the user to remember to call them. Brain mode's primary job is to orchestrate these existing skills automatically, making the brain an active participant rather than a passive tool.

The toolkit uses `BRAIN_PATH` environment variable to locate the vault. Claude Code supports hooks (pre/post command triggers), statusline customization, and custom launch flags — all of which brain mode will leverage.

The adaptive mentoring system (warn → silent fix → investigate) requires the brain to track not just what patterns exist but how many times each has been encountered, creating a progression from teaching to automation.

## Constraints

- **Platform**: Claude Code CLI only — must work within its hook, skill, and statusline systems
- **Storage**: All brain data lives in the local vault at BRAIN_PATH — no external services
- **Performance**: Brain operations must not noticeably slow down normal Claude Code interactions
- **Compatibility**: Must work alongside existing brain toolkit skills without breaking them

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single vault, not multi-vault | Simplicity — one brain per human, one place to look | — Pending |
| Orchestrate existing skills first | Ship fast, learn what's missing from real usage | — Pending |
| Adaptive mentoring progression (warn → silent → investigate) | Teaches the user while reducing noise over time | — Pending |
| BRAIN_PATH env var for vault location | Cross-directory access needs a stable reference point | — Pending |

---
*Last updated: 2026-03-19 after initialization*
