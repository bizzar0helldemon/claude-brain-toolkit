# Project Research Summary

**Project:** Claude Brain Mode v1.2
**Domain:** Claude Code CLI extension — autonomous session partner with idle detection, vault relocate, pattern encounter tracking, and progressive responses
**Researched:** 2026-03-21
**Confidence:** HIGH (stack and architecture sourced from direct codebase inspection + official docs; pitfalls verified against official hooks reference and GitHub issues)

## Executive Summary

Claude Brain Mode v1.2 adds four targeted capabilities on top of the v1.0/v1.1 foundation: idle detection (LIFE-06), vault relocate (ONBR-03), pattern encounter tracking verification (MENT-01), and progressive responses based on encounter frequency (MENT-02). The v1.1 baseline is fully operational — the statusline shows brain state, the Stop hook suppresses trivial sessions, and the pattern store records encounter counts on every match. What v1.2 delivers is the behavioral intelligence layer that was deliberately deferred: the system now adapts its tone and urgency based on how many times a pattern has been hit, and it offers to capture work at natural idle pauses rather than only at session end.

The recommended implementation approach requires no new binaries, no new hook event types beyond the `Notification/idle_prompt` event already available in Claude Code v2.1.79, and no schema changes to pattern-store.json. The biggest complexity concentration is vault relocate (ONBR-03), which requires atomic updates to two separate configuration targets — settings.json and the shell profile — and must validate symlink integrity in the copied vault before committing. The progressive responses feature (MENT-02) is the highest-value/lowest-cost change: a small modification to `post-tool-use-failure.sh` to include encounter count in the additionalContext output, plus updated agent instructions in brain-mode.md.

The central risk for this milestone is the `Notification/idle_prompt` hook's reliability. GitHub issue #11964 (closed NOT PLANNED, January 2026) confirms the `notification_type` field was absent from actual payloads in some versions, and GitHub issue #12048 suggests `idle_prompt` may fire after every response rather than after genuine 60-second inactivity in some configurations. Defensive fallback logic — checking the `message` field when `notification_type` is absent, plus a one-offer-per-session guard — is non-negotiable. The second critical risk is vault relocate: any implementation that updates only the shell profile and not `~/.claude/settings.json` will silently continue writing to the old vault path, because Claude Code hooks read BRAIN_PATH from the settings.json env block, not from the user's shell profile.

## Key Findings

### Recommended Stack

v1.2 introduces zero new technologies. Every feature runs on the existing stack: Claude Code hooks, Bash, jq 1.7.1, sed (POSIX), and the established tmp+mv atomic write pattern. The `Notification` hook event with `idle_prompt` matcher is the correct idle detection mechanism — it replaces the timestamp-polling approximation that was noted as a risk in v1.1 research and is the purpose-built native hook for this use case. `jq` handles all JSON writes (settings.json, pattern-store.json) with the guard `(.env // {})` for missing env blocks. `sed` handles the shell profile line replacement in portable temp+mv form (no GNU `-i` flag required).

**Core technologies:**
- `Notification/idle_prompt` hook (Claude Code v2.1.79+): idle detection — native mechanism, fires at ~60 second user inactivity, no polling required
- `jq` 1.7.1 (existing): vault relocate settings.json update + pattern encounter count reading — atomic via tmp+mv
- `sed` POSIX (existing): vault relocate shell profile line replacement — portable across macOS, Linux, Git Bash
- `additionalContext` hook output (existing): MENT-02 enriched context injection — encounter count included in pattern match message

One version caveat: `messageIdleNotifThresholdMs` in `~/.claude.json` appeared in a single GitHub comment (March 2026) claiming it controls idle timeout. It is NOT in official docs. Treat as undocumented/experimental and omit from setup.sh.

### Expected Features

v1.2 closes out the four items deferred from v1.1. The table stakes (session injection, pre-clear capture, brain state in statusline, milestone auto-capture, error pattern recognition) are fully shipped. This milestone completes the intelligence layer.

**Must have (table stakes — already shipped in v1.0/v1.1):**
- Session context injection at startup — users expect the AI to know relevant context without being told
- Pre-clear capture — context loss on /clear is the top complaint in CLI AI workflows
- Brain state indicator in statusline — users need to know when brain mode is engaged
- Milestone auto-capture at git commits — no competitor does this automatically
- Error pattern recognition against pattern store — shipped v1.0, produces the encounter_count data MENT-01 depends on

**Should have (v1.2 targets):**
- MENT-02: Progressive responses — adapts from full explanation (1st encounter) to brief note (2-4x) to root cause investigation flag (5+x); highest value/lowest cost change in this milestone
- LIFE-06: Idle detection — offer to capture at natural pauses; differentiator no existing tool offers; native `Notification/idle_prompt` hook available
- ONBR-03: Vault relocate — closes the "vault moved, brain broken" error path that brain_path_validate already surfaces but cannot resolve
- MENT-01: Pattern encounter tracking verification — confirm encounter_count increments on match; precondition for MENT-02

**Defer (v2+):**
- Full adaptive mentoring (auto-fix + root cause investigation) — needs real usage data to tune thresholds reliably
- Pattern store rotation / pruning — important for long-term health but store is small at v1.2 scale
- Capturable-content shared function (DRY refactor) — technical debt cleanup, not blocking v1.2

### Architecture Approach

v1.2 makes targeted, minimal changes to the existing hook architecture. The core pattern is: hooks provide data (encounter count in additionalContext, context window percentage in PostToolUse), and the agent instructions in brain-mode.md decide what to do with that data. This split keeps shell scripts as simple interceptors and concentrates reasoning logic in the agent layer. Two files receive meaningful changes — `post-tool-use-failure.sh` gets count-aware context output, and `agents/brain-mode.md` gets progressive response instructions and idle awareness guidance. One new file is created: the `brain-relocate` slash command.

**Major components:**
1. `post-tool-use-failure.sh` — modified to include encounter_count in additionalContext, enabling MENT-02 progressive response tiers in the agent
2. `agents/brain-mode.md` — modified with MENT-02 response tier instructions, LIFE-06 idle pause behavior guidance, and ONBR-03 skill listing
3. `commands/brain/brain-relocate.md` — new slash command; Claude-orchestrated file ops with user confirmation, jq settings.json update, and symlink integrity check
4. `~/.claude/settings.json` — new Notification hook entry registering `idle_prompt` handler
5. `hooks/notification.sh` (new) — defensive idle detection script with `notification_type` + `message` fallback, one-offer-per-session guard

### Critical Pitfalls

1. **`notification_type` field absent from idle hook payload** — GitHub issue #11964 confirmed the field was missing in some versions (closed NOT PLANNED, no fix shipped). Always check both `notification_type` and `message` fields: gate on either `NTYPE = "idle_prompt"` OR `MSG` matching "waiting\|idle". Do not gate on `notification_type` alone.

2. **Vault relocate updates only shell profile, not settings.json** — Claude Code hooks read BRAIN_PATH from the `env` block in settings.json, not from the user's shell profile (hooks run in non-interactive subshells). Any relocate that updates only ~/.zshrc silently continues writing to the old vault path. Both targets are mandatory and must be verified: `jq` atomic write to settings.json AND sed replacement in shell profile.

3. **Idle prompt fires during long-running tool calls, not true idleness** — `idle_prompt` (and any timestamp-gap approximation) cannot distinguish "user is away" from "user is watching a 3-minute test suite run." The one-offer-per-session guard (`.brain-idle-offered` flag cleared on SessionStart) prevents repeat interruptions regardless of how often the hook fires.

4. **Pattern store grows unbounded** — `update_encounter_count` increments but never prunes. Add a soft cap (100 patterns) with eviction by lowest encounter_count + oldest last_seen composite score. Archive evicted patterns rather than hard-deleting. This must ship in the same phase as MENT-01, not deferred.

5. **Vault relocate breaks relative symlinks** — `cp -r` copies dangling symlinks silently. `brain_path_validate` passes on `[ -d "$BRAIN_PATH" ]` even when key files inside are broken symlinks. After copy, run `find "$NEW_PATH" -type l ! -exec test -e {} \; -print` to surface broken symlinks before committing the BRAIN_PATH update.

## Implications for Roadmap

Phases continue from Phase 8 (v1.1 complete at Phase 8). Research identifies four implementation phases with a clear dependency order: MENT-01 verification first (unblocks MENT-02), then MENT-02 (highest value, self-contained), then ONBR-03 (most complex, isolated), then LIFE-06 (lowest risk, agent-only approach viable as safe floor).

### Phase 9: MENT-01 — Verify Pattern Encounter Tracking

**Rationale:** MENT-02 (progressive responses) cannot be implemented until encounter_count is confirmed to increment correctly on error matches. This phase is zero-code — inspect the pattern store after a real error match, confirm values. If `update_encounter_count` has a bug, fix it here before building on top of it. The pattern store soft cap (Pitfall 4) must also be wired in this phase — adding counter tracking without pruning is the technical debt that causes unbounded growth.
**Delivers:** Confirmed encounter_count tracking with documented behavior; pattern store soft cap (100 entries, archive-on-eviction); concurrent-write limitation documented in code comments.
**Addresses:** MENT-01 requirement; unblocks MENT-02.
**Avoids:** Pattern store unbounded growth (Pitfall 4); encounter counter race condition (Pitfall 4 from PITFALLS.md — document limitation, defer flock to v2).

### Phase 10: MENT-02 — Progressive Responses

**Rationale:** Highest value / lowest implementation cost of the four v1.2 features. Depends directly on Phase 9 confirming encounter_count data. Changes are contained to two files: enrich `post-tool-use-failure.sh` additionalContext to include count, then add response tier instructions to `agents/brain-mode.md`. Three tiers: full explanation at count=1, brief note at count 2-4, root-cause investigation flag at count 5+. Document thresholds as named constants — not magic numbers.
**Delivers:** Adaptive mentor behavior — the pattern store transforms from a lookup table into a behavioral guide that adjusts tone based on recurrence frequency.
**Uses:** Existing jq query in post-tool-use-failure.sh; existing additionalContext hook output pattern; hook enrichment pattern (Pattern 2 from ARCHITECTURE.md).
**Implements:** Agent instructions as behavior layer (Pattern 1 from ARCHITECTURE.md); hook enrichment for downstream agent use (Pattern 2).

### Phase 11: ONBR-03 — Vault Relocate Command

**Rationale:** Most complex v1.2 feature; completely isolated from MENT-01/MENT-02 (no shared dependencies). Building last among the code features ensures MENT-02 is stable first. The complexity is in the dual-target update requirement and symlink validation — not in the logic itself. Implemented as a Claude slash command (not a hook) so Claude can confirm with the user, handle errors gracefully, and provide a recoverable path if something goes wrong.
**Delivers:** `/brain-relocate` slash command that atomically updates settings.json env.BRAIN_PATH and shell profile, runs symlink integrity check post-copy, and includes session restart reminder.
**Avoids:** Shell-profile-only update (Pitfall 2); broken symlinks post-copy (Pitfall 5); running session stale path — warn user to restart any open Claude Code sessions.

### Phase 12: LIFE-06 — Idle Detection

**Rationale:** Lowest risk of the four features. The agent-instructions approach (add idle awareness behavior to brain-mode.md) requires zero hook changes and zero risk of intrusiveness regression. The `Notification/idle_prompt` hook is higher-capability but carries reliability uncertainty. Recommend shipping both in this phase: agent instructions as the safe floor, Notification hook as the enhancement, with defensive fallback on `notification_type` absence. One-offer-per-session guard is mandatory regardless of approach.
**Delivers:** Idle capture offer injected via `Notification/idle_prompt` hook when session has capturable content. Silent when session is trivial. Agent instructions provide baseline idle-aware behavior even in non-hook contexts.
**Avoids:** Idle prompt fires during long tool calls (Pitfall 1); platform-dependent `stat` usage (Pitfall 6 from PITFALLS.md — embed epoch seconds in state file if needed, never use stat); `notification_type` field absence (Critical Pitfall 1 above).

### Phase Ordering Rationale

- MENT-01 before MENT-02: progressive responses require confirmed encounter_count data. Debugging the display layer while the data layer is unverified wastes effort.
- MENT-02 before ONBR-03: MENT-02 is the highest-value feature and should be stabilized before the more complex vault operations work begins. No shared code paths between them.
- ONBR-03 before LIFE-06: vault relocate is more operationally critical — users with a broken vault are blocked. Idle detection is a quality-of-life enhancement.
- LIFE-06 last: carries the most implementation uncertainty (`notification_type` reliability, idle timing edge cases) and can be implemented conservatively as agent instructions only with the hook as an optional enhancement.

### Research Flags

Phases needing attention during implementation planning:
- **Phase 12 (LIFE-06):** `Notification/idle_prompt` reliability is uncertain. GitHub issues #11964 and #12048 both closed NOT PLANNED — field absence and incorrect firing frequency are confirmed real-world risks. Test against live Claude Code v2.1.79 before finalizing implementation approach. Design one-offer-per-session guard to be robust regardless of hook firing frequency.
- **Phase 11 (ONBR-03):** Shell profile detection on Windows (Git Bash) needs live testing. `$SHELL` in Git Bash resolves to `/usr/bin/bash` and the correct profile may be `~/.bash_profile` rather than `~/.bashrc`. Confirm on target platform before writing profile update code.

Phases with standard patterns (lower planning overhead):
- **Phase 9 (MENT-01):** Verification-only phase. Established jq query patterns, no new code expected unless a bug is found. Build order unambiguous.
- **Phase 10 (MENT-02):** Additive change to existing hook output format. Pattern for enriching additionalContext is established throughout the codebase. Low risk of regression.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new technologies. All stack elements verified against official docs and live codebase. One LOW-confidence item: `messageIdleNotifThresholdMs` — treat as experimental, omit from setup.sh. |
| Features | HIGH | v1.2 scope is narrow and well-defined. MENT-01 infrastructure confirmed implemented by direct codebase inspection. Platform constraints for all four features verified against official Claude Code docs. |
| Architecture | HIGH | Sourced from direct codebase inspection of hook scripts, lib functions, and agent definition. Component boundaries, modification targets, and build order are based on reading actual source files, not inference. |
| Pitfalls | HIGH (system-level) / MEDIUM (idle timing) | Vault relocate and pattern store pitfalls sourced from official docs + confirmed GitHub issues. Idle detection timing edge cases are MEDIUM — behavior may differ between Claude Code versions. |

**Overall confidence:** HIGH

### Gaps to Address

- **`idle_prompt` firing frequency:** Research found conflicting evidence — designed to fire at 60-second inactivity (GitHub #8320, confirmed by related #9708 fix) but reported to fire after every response in some configurations (GitHub #12048). Test against live v2.1.79 before finalizing idle detection logic. Design the one-offer-per-session guard to be robust regardless.
- **`messageIdleNotifThresholdMs` viability:** Cannot be verified against official docs. Do not add to setup.sh. If users request a shorter idle window, document as an undocumented/experimental option with a warning.
- **Progressive response thresholds:** The 1 / 2-4 / 5+ encounter count tiers are a starting hypothesis. Document as named constants with the explicit intent to tune after real usage data accumulates.
- **Windows Git Bash shell profile detection:** Shell profile detection for vault relocate needs live testing on the target platform. Verify `$SHELL` resolves correctly and maps to the right profile file before shipping ONBR-03.

## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — Notification event, idle_prompt matcher, additionalContext output, non-interactive subshell env injection, TeammateIdle scope (team only, not single-agent)
- [Claude Code Settings Reference](https://code.claude.com/docs/en/settings) — settings.json schema, env block; confirmed `messageIdleNotifThresholdMs` is NOT in official docs
- `hooks/lib/brain-path.sh` (codebase) — `update_encounter_count`, `init_pattern_store`, `encounter_count` field, `last_seen`, atomic tmp+mv pattern — confirmed fully implemented
- `hooks/post-tool-use-failure.sh` (codebase) — confirmed encounter_count write on match; current additionalContext format (solution text only, no count)
- `hooks/stop.sh`, `hooks/post-tool-use.sh`, `agents/brain-mode.md` (codebase) — confirmed patterns for transcript parsing, context_window reading, agent instruction structure
- [GitHub #29217, #28813 — race condition: .claude.json corrupted by concurrent writes](https://github.com/anthropics/claude-code/issues/29217) — confirmed tmp+mv is insufficient for multiple concurrent writers; flock advisory lock documented

### Secondary (MEDIUM confidence)
- [GitHub issue #8320: 60-Second Idle Notifications Not Triggering](https://github.com/anthropics/claude-code/issues/8320) — confirms idle_prompt design intent (60-second inactivity); related #9708 marked COMPLETED suggests execution bug was fixed
- [GitHub issue #11964: Notification hook events missing notification_type field](https://github.com/anthropics/claude-code/issues/11964) — closed NOT PLANNED; confirms field was absent from payloads in real use; motivates defensive fallback
- [GitHub issue #12048: Add notification matcher for when Claude is waiting](https://github.com/anthropics/claude-code/issues/12048) — closed as duplicate; reports idle_prompt fires after every response in some configurations; risk flag
- Claude Code Notifications practical guide (alexop.dev) + comprehensive hook examples (aiorg.dev) — implementation patterns consistent with official docs
- [Using Lock Files for Job Control in Bash Scripts — putorius.net](https://www.putorius.net/lock-files-bash-scripts.html) — flock advisory lock approach for concurrent write safety
- [Things UNIX can do atomically — rcrowley.org](https://rcrowley.org/2010/01/06/things-unix-can-do-atomically.html) — rename() atomicity, foundation for tmp+mv pattern

### Tertiary (LOW confidence)
- [GitHub issue #13922 comment, March 2026](https://github.com/anthropics/claude-code/issues/13922) — single unverified comment claims `messageIdleNotifThresholdMs` was implemented; not in official docs; treat as experimental only

---
*Research completed: 2026-03-21*
*Updated from v1.0 summary (2026-03-19) — v1.2 milestone synthesis*
*Ready for roadmap: yes*
