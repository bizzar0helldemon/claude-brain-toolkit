# Requirements: Claude Brain Mode

**Defined:** 2026-03-21
**Core Value:** The brain compounds over time — every session makes future sessions smarter by actively capturing and applying knowledge without the user having to ask.

## v1.1 Requirements

Requirements for v1.1 Quiet Brain. Each maps to roadmap phases.

### Stop Hook Intelligence

- [x] **STOP-01**: Stop hook evaluates session content before triggering capture (detects tool usage, code changes, git commits, error resolutions)
- [x] **STOP-02**: Trivial sessions (few messages, no code/commits/decisions) skip capture silently
- [x] **STOP-03**: Stop hook exits non-blocking (exit 0) when no capturable content detected, blocking (decision:block + exit 0) only when capture is warranted

### Statusline States

- [ ] **STAT-02**: Statusline shows distinct visual states — idle (🧠), active/captured (🟢🧠), error/degraded (🔴🧠)
- [ ] **STAT-03**: State transitions happen automatically based on hook activity (no user action needed)

## Future Requirements

Deferred beyond v1.1. Tracked but not in current roadmap.

### Idle Detection

- **LIFE-06**: Idle detection offers to summarize or capture current state when user pauses — deferred, fix intrusiveness first

### Vault Management

- **ONBR-03**: Vault relocate command updates BRAIN_PATH if vault directory moves — utility, not UX-critical

### Adaptive Mentoring

- **MENT-01**: Pattern encounter tracking records frequency per pattern/pitfall — needs real usage data
- **MENT-02**: Progressive response changes behavior based on encounter count — same intrusiveness risk

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Multi-vault support | One brain per system keeps things simple |
| Cloud sync | Vault is local filesystem only, no external services |
| Non-Claude-Code integrations | Specifically for Claude Code CLI |
| Mobile/web interface | CLI-only tool |
| Force-capture override | Unnecessary complexity — user can always run /brain-capture manually |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| STOP-01 | Phase 7 | Complete |
| STOP-02 | Phase 7 | Complete |
| STOP-03 | Phase 7 | Complete |
| STAT-02 | Phase 8 | Pending |
| STAT-03 | Phase 8 | Pending |

**Coverage:**
- v1.1 requirements: 5 total
- Mapped to phases: 5
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-03-21 after roadmap creation*
