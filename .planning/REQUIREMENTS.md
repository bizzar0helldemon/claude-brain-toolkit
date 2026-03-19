# Requirements: Claude Brain Mode

**Defined:** 2026-03-19
**Core Value:** The brain compounds over time — every session makes future sessions smarter by actively capturing and applying knowledge without the user having to ask.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Hook Infrastructure

- [ ] **HOOK-01**: Stop hook loop guard baked into all brain mode hook templates
- [ ] **HOOK-02**: Exit code discipline enforced — `exit 2` for blocking hooks, `exit 1` for non-blocking
- [ ] **HOOK-03**: BRAIN_PATH validation on every hook invocation with clear error if missing/invalid
- [ ] **HOOK-04**: JSON output self-test included in hook scaffolding template

### Session Lifecycle

- [ ] **LIFE-01**: SessionStart hook loads relevant vault context for current project (pitfalls, patterns, preferences)
- [ ] **LIFE-02**: Pre-clear auto-capture triggers `/brain-capture` then `/daily-note` before `/clear`
- [ ] **LIFE-03**: Token budget management limits vault content injection to prevent context window bloat
- [ ] **LIFE-04**: Milestone auto-capture triggers after commits, merges, and phase completions
- [ ] **LIFE-05**: Error pattern recognition detects recurring errors and surfaces past solutions from vault

### Statusline

- [ ] **STAT-01**: Brain emoji appears in statusline left of model name when brain mode is active

### Onboarding

- [ ] **ONBR-01**: First-run guided setup walks user through creating vault directory and configuring BRAIN_PATH
- [ ] **ONBR-02**: `claude --agent brain-mode` entry point launches brain mode via native subagent pattern

## v2 Requirements

### Statusline

- **STAT-02**: Color-coded brain states in statusline (idle vs active processing)

### Session Lifecycle

- **LIFE-06**: Idle detection offers to summarize or capture current state when user pauses

### Onboarding

- **ONBR-03**: Vault relocate command updates BRAIN_PATH if vault directory moves

### Adaptive Mentoring

- **MENT-01**: Pattern encounter tracking records frequency per pattern/pitfall
- **MENT-02**: Progressive response changes behavior based on encounter count (warn → silent fix → investigate)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-vault support | One brain per system keeps things simple |
| Cloud sync | Vault is local filesystem only — no external services |
| Non-Claude-Code integrations | This is specifically for the Claude Code CLI |
| New brain skills beyond orchestration | Will emerge from usage, not pre-designed |
| Mobile/web interface | CLI-only tool |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| HOOK-01 | — | Pending |
| HOOK-02 | — | Pending |
| HOOK-03 | — | Pending |
| HOOK-04 | — | Pending |
| LIFE-01 | — | Pending |
| LIFE-02 | — | Pending |
| LIFE-03 | — | Pending |
| LIFE-04 | — | Pending |
| LIFE-05 | — | Pending |
| STAT-01 | — | Pending |
| ONBR-01 | — | Pending |
| ONBR-02 | — | Pending |

**Coverage:**
- v1 requirements: 12 total
- Mapped to phases: 0
- Unmapped: 12 ⚠️

---
*Requirements defined: 2026-03-19*
*Last updated: 2026-03-19 after initial definition*
