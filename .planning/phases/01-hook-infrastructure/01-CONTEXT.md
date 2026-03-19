# Phase 1: Hook Infrastructure - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Safe, validated hook scaffolding that all future brain mode features build on. Delivers lifecycle hooks (SessionStart, PreCompact, Stop, PostToolUseFailure), BRAIN_PATH library with validation, stop-loop guard, exit code discipline (exit 1 = non-blocking, exit 2 = blocking), and a brain statusline indicator. No session logic, no vault reading/writing — just the scaffold.

</domain>

<decisions>
## Implementation Decisions

### Error experience
- Contextual explanation style: when BRAIN_PATH is unset, show what it is, why it matters, and the exact fix command — not just a one-liner
- When BRAIN_PATH directory doesn't exist: offer to create it (prompt user), don't auto-create or hard-fail
- Error messages are self-contained — no forward references to commands/features that don't exist yet (e.g., no "run /brain-setup")
- Dual-channel errors: stderr for the human in the terminal, JSON error field for the LLM to read and act on

### Failure behavior
- Per-hook degradation: Claude decides whether to degrade-with-warning or stop brain mode based on which hook failed and severity
- Stop-loop guard: strict — 1 retry allowed, then immediately kill the hook. Zero tolerance for loops
- Log all hook failures to a persistent file in the vault (BRAIN_PATH/.brain-errors.log) for post-mortem debugging
- Recovery attempts: each hook event re-checks prerequisites — if the problem is fixed mid-session, brain mode recovers automatically

### Shell output hygiene
- JSON isolation approach: Claude's discretion (delimiter markers, clean subshell, or redirect strategy — pick most robust)
- Self-validate: each hook validates its own JSON output before returning — catches corruption early
- Shell support: bash + zsh (covers macOS default zsh, Linux default bash, Windows Git Bash)
- When shell noise detected: strip silently and extract the JSON — don't bother the user about their shell profile

### Claude's Discretion
- Statusline display design (emoji, text, what info to show)
- JSON isolation implementation approach
- Per-hook degradation vs stop decisions (severity-based)
- Exact error message wording and formatting

</decisions>

<specifics>
## Specific Ideas

- Error messages should feel like a contextual explanation, not a cryptic failure — modeled on the preview: "Brain mode requires BRAIN_PATH. BRAIN_PATH tells brain mode where your knowledge vault lives. Set it in your shell profile..."
- The stop-loop guard should be extremely conservative (1 retry) — loops are the worst failure mode for hooks

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-hook-infrastructure*
*Context gathered: 2026-03-19*
