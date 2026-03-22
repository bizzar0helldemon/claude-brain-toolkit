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

- [x] **STAT-02**: Statusline shows distinct visual states — idle (🧠), active/captured (🟢🧠), error/degraded (🔴🧠)
- [x] **STAT-03**: State transitions happen automatically based on hook activity (no user action needed)

## v1.2 Requirements

Requirements for v1.2 Polish & Intelligence. Each maps to roadmap phases.

### Intelligence Layer

- [x] **MENT-01**: Pattern store encounter_count is verified incrementing on each error match and pattern store has soft-cap pruning
- [x] **MENT-02**: Error pattern responses adapt based on encounter count — full explanation at first encounter, brief note at 2-4, root cause investigation flag at 5+

### Vault Management

- [x] **ONBR-03**: User can relocate their vault via `/brain-relocate`, which updates BRAIN_PATH in both settings.json and shell profile with post-relocate verification

### Session Intelligence

- [x] **LIFE-06**: Idle detection offers to capture when the session has capturable content and the user is idle, with a one-offer-per-session guard

## Future Requirements

Deferred beyond v1.2. Tracked but not in current roadmap.

### Adaptive Mentoring (Extended)

- **MENT-03**: Full adaptive mentoring — auto-fix + root cause investigation based on tuned thresholds from real usage data

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
| STAT-02 | Phase 8 | Complete |
| STAT-03 | Phase 8 | Complete |
| MENT-01 | Phase 9 | Complete |
| MENT-02 | Phase 9 | Complete |
| ONBR-03 | Phase 10 | Complete |
| LIFE-06 | Phase 11 | Complete |

**Coverage:**
- v1.1 requirements: 5 total — all complete
- v1.2 requirements: 4 total — all complete
- Mapped to phases: 5 (v1.1) + 4 (v1.2)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-21*
*Last updated: 2026-03-21 — v1.2 complete, all requirements shipped*
