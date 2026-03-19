# Project Research Summary

**Project:** Claude Brain Mode — Claude Code CLI Extension
**Domain:** AI Knowledge Management / Autonomous Session Partner built on Claude Code hooks, skills, and statusline
**Researched:** 2026-03-19
**Confidence:** HIGH

## Executive Summary

Claude Brain Mode is a Claude Code CLI extension that transforms the AI from a stateless coding assistant into a persistent knowledge partner. The system is built entirely on first-party Claude Code extension points — hooks (lifecycle shell scripts), skills (SKILL.md command definitions), subagents (agent launch modes), and the native statusline — rather than any external framework. No npm packages or backend services are required. The vault is a local directory tree at `BRAIN_PATH`, and all persistence is plain markdown and JSON files, making the system portable, auditable, and compatible with any sync tool the user already uses.

The recommended approach is to build in strict dependency order: vault I/O foundation first, then statusline for immediate feedback, then the SessionStart hook that makes every session brain-aware, then pre-clear capture, and finally the adaptive mentoring layer on top. This order is not stylistic — each component is literally required by the one that follows it. The single most important architectural decision is that `BRAIN_PATH` is validated at every entry point: silent degradation when this variable is unset is the most common failure mode documented in the research and must be treated as a hard error, not a warning.

The primary risks are (1) the Stop hook infinite loop, which is a documented Claude Code bug trigger that is trivially prevented with a one-line guard, (2) context window bloat from over-eager SessionStart vault loading, which kills effective session length before the user notices, and (3) adaptive mentoring notification fatigue, which destroys user trust if enabled before patterns are well-calibrated. All three are preventable with explicit guards built into the earliest phases rather than retrofitted later. The research is sourced entirely from official Claude Code documentation and verified against the live CLI (v2.1.79), so confidence in the technical foundation is high.

---

## Key Findings

### Recommended Stack

The entire stack is Claude Code native. Skills (`SKILL.md` files at `~/.claude/skills/`) define all user-invocable and Claude-invocable brain commands. Hooks in `~/.claude/settings.json` handle all automatic event-driven behavior at session lifecycle points. The subagent mechanism (`~/.claude/agents/brain-mode.md` + `claude --agent brain-mode`) is the correct implementation of a dedicated "brain launch mode" — there is no `--brain` flag in Claude Code. The statusline (`~/.claude/statusline.sh`) provides persistent visual feedback after every assistant message.

Supporting tooling is minimal: `jq` (1.6+) is required for parsing hook event JSON in shell scripts and must be installed separately. Python 3 stdlib is an alternative for complex statusline logic. `BRAIN_PATH` as an environment variable is the single cross-directory bridge that all components depend on. No Node.js packages, no databases, no running daemons.

**Core technologies:**
- **Claude Code Skills (v2.1.79+):** Brain command definitions (`brain-mode`, `brain-capture`, `brain-audit`, `daily-note`) — the canonical extension point, successor to `.claude/commands/`
- **Claude Code Hooks:** Lifecycle automation (`SessionStart`, `PreCompact`, `Stop`, `PostToolUseFailure`) — the only mechanism for automatic, event-driven behavior without user invocation
- **Claude Code StatusLine:** Persistent brain state indicator (emoji, color, context %) — native, no third-party terminal integration needed
- **Claude Code Subagents:** `brain-mode` as a launchable agent via `claude --agent brain-mode` — the correct way to implement a custom launch mode
- **Bash + jq:** Hook execution layer and JSON parsing — available everywhere Claude Code runs, including Git Bash on Windows
- **`BRAIN_PATH` env var:** Cross-directory vault reference — set once in shell profile, inherited by all hooks, scripts, and skills

### Expected Features

**Must have (table stakes) — v1:**
- Session context injection at startup — users expect the AI to "know" context without being told; delivered via `SessionStart` hook `additionalContext`
- Persistent knowledge across sessions — CLAUDE.md + auto MEMORY.md handles baseline; brain mode augments with vault-level patterns and history
- Brain mode active indicator — statusline brain emoji is the minimum; without it the mode is invisible and disorienting
- Pre-clear capture — the most complained-about pain point in CLI AI workflows; `PreCompact` hook triggers capture before `/clear`
- `BRAIN_PATH` vault location — required for all cross-directory vault operations; established by first-run onboarding
- First-run onboarding — tools requiring setup that skip onboarding get abandoned; must be the first thing that runs

**Should have (competitive) — v1.x:**
- Milestone auto-capture at git commits/merges — `PostToolUse` hook detects bash tool calls matching git patterns; no current competitor does this
- Error pattern recognition — `PostToolUseFailure` hook matches current error against vault patterns; bridges MEMORY.md (passive) and active pattern matching
- Pattern encounter tracking — prerequisite infrastructure for adaptive mentoring; can be invisible to users initially
- Color-coded brain states in statusline (idle/loading/capturing) — unique to this tool; makes brain activity visible without interrupting flow

**Defer to v2+:**
- Adaptive mentoring progression (warn → silent fix → investigate) — highest complexity, highest payoff; requires encounter tracking data to tune thresholds safely
- Idle detection — no native hook exists; must be approximated; build only after seeing what "useful idle suggestions" look like in practice
- Vault relocate command — needed but rarely triggered; add when someone actually requests it
- Knowledge flow annotation / activity log — nice-to-have visibility feature; not blocking anything

**Deliberate anti-features (never build):**
- Multi-vault support — ambiguity about where to save kills capture rate
- Real-time capture of everything — creates noise; quality over quantity for injected knowledge
- Cloud sync / remote vault — users own their sync tool; out of scope

### Architecture Approach

The system has four independent runtime subsystems that communicate exclusively through shared files at `BRAIN_PATH`: the statusline script (reads session JSON stdin + cached disk state), hook scripts (read/write vault files on lifecycle events), skills (Claude reads vault files via tool calls during invocation), and the pattern store (JSON file that persists adaptive mentoring state). There is no shared in-memory state and no IPC other than file reads/writes. This makes the architecture resilient — any component can fail without taking down the others — but requires that all components agree on the `pattern-store.json` schema as a shared contract.

**Major components:**
1. **Vault I/O Foundation** (`hooks/lib/brain-path.sh`, `lib/vault-write.sh`) — `BRAIN_PATH` validation and atomic file writes shared by all hook scripts; everything else depends on these
2. **StatusLine Script** (`~/.claude/statusline.sh`) — renders brain emoji + color state from session JSON stdin and cached `pattern-store.json`; fires after every assistant message
3. **Hook Scripts** (`hooks/session-start.sh`, `pre-compact.sh`, `stop.sh`, `error-detect.sh`) — lifecycle interceptors that handle automatic vault operations without user invocation
4. **Pattern Store** (`$BRAIN_PATH/brain-mode/pattern-store.json`) — JSON file tracking encounter frequency; the shared state contract between hooks, statusline, and the brain-mode skill
5. **Brain Mode Skill** (`~/.claude/skills/brain-mode/SKILL.md`) — orchestration skill that runs inline (no `context: fork`), injects behavioral context, and encodes mentoring level instructions
6. **Brain Mode Subagent** (`~/.claude/agents/brain-mode.md`) — activated via `claude --agent brain-mode`; defines system prompt, preloads skills, wires hooks at launch

### Critical Pitfalls

1. **Stop hook infinite loop** — add `stop_hook_active` guard as the first line of every Stop hook script; if `true`, `exit 0` immediately. Missing this guard causes the session to loop indefinitely consuming tokens. Treat it as non-negotiable scaffolding in the hook template from Phase 1.

2. **Wrong exit code silences security gates** — `exit 1` is a non-blocking error in Claude Code; only `exit 2` blocks tool execution. A hook that uses `exit 1` to "block" an operation appears to work but silently passes through. Test every blocking hook with known-bad input and verify the tool does NOT execute.

3. **Shell profile output corrupts JSON parsing** — Claude Code spawns a shell that sources `~/.zshrc` or `~/.bashrc`; any unconditional `echo` in those profiles (nvm notices, conda output, welcome messages) prepends non-JSON text before the hook's output, breaking `jq` parsing. Guard all profile output with `[[ $- == *i* ]]` and test hook output with `| jq .` before deploying.

4. **Context window bloat from vault loading** — loading full vault content at `SessionStart` consumes 100K+ tokens before the first prompt, cutting effective session length in half. Keep `SessionStart` hook output under 2,000 tokens (navigation skeleton only); measure with `claude --verbose` before shipping anything that touches vault loading.

5. **BRAIN_PATH silent degradation** — when `BRAIN_PATH` is unset, shell expansion produces empty strings, vault writes go to wrong directories, and no error is thrown. Brain mode appears to work but captures nothing. Every hook must validate `BRAIN_PATH` is set and the directory exists before doing anything; fail loudly with a specific fix instruction.

6. **Adaptive mentoring notification fatigue** — unsolicited suggestions during focused work trains users to ignore brain output entirely; trust, once broken, is not recovered. Default to silent; surface suggestions only at natural pauses; start with logging-only for at least one milestone before enabling visible recommendations.

---

## Implications for Roadmap

Based on the dependency graph in FEATURES.md and the build order specified in ARCHITECTURE.md, the research points clearly to a 4-phase structure. Phases 1-3 build the foundation and the two P1 table-stakes features. Phase 4 adds the competitive differentiators that justify brain mode over manual skill invocation.

### Phase 1: Hook Infrastructure Foundation

**Rationale:** All other components depend on working hooks. The three critical "never ship without these" pitfalls (Stop loop, wrong exit code, shell profile corruption) must be resolved before any feature logic is built on top. Building the hook scaffolding template with guards baked in prevents retrofitting later.

**Delivers:** Working hook scaffolding with `stop_hook_active` guard, `exit 2` discipline, JSON output validation, `BRAIN_PATH` validation library (`lib/brain-path.sh`), and atomic vault write utility (`lib/vault-write.sh`). A minimal statusline showing brain emoji + context %. Developers can confirm hooks fire at the right lifecycle events.

**Addresses:** BRAIN_PATH env var (table stake), brain active indicator (table stake), vault I/O foundation (architecture prerequisite).

**Avoids:** Stop hook infinite loop, wrong exit code silences gates, shell profile JSON corruption — all three are addressed in scaffolding templates, not individually per hook.

**Research flag:** Standard patterns — well-documented in official Claude Code hooks reference. No additional research needed.

---

### Phase 2: Session Lifecycle (Context Injection + Pre-Clear Capture)

**Rationale:** Session context injection is the primary value delivery mechanism of brain mode. Pre-clear capture solves the most visible user pain point. Together they validate the core concept that brain mode compounds value over time. Both depend on Phase 1's vault I/O foundation.

**Delivers:** `SessionStart` hook that injects vault context (current project, recent daily note, active pitfalls) at session start. `PreCompact` hook that captures conversation state before `/clear`. `Stop` hook that captures session milestones. Pattern store schema defined and initialized (`pattern-store.json`).

**Addresses:** Session context injection (P1 table stake), pre-clear capture (P1 table stake), persistent knowledge across sessions (table stake).

**Avoids:** Context window bloat — SessionStart output capped at 2,000 tokens, measured with `claude --verbose` before shipping. SessionEnd timeout pitfall — critical captures moved to PreCompact, not SessionEnd.

**Research flag:** Standard patterns for context injection. The specific behavior of `/clear` mapping to `SessionStart` with `source=clear` (rather than a separate pre-clear hook) was a non-obvious finding — verify this in testing before building capture logic around it.

---

### Phase 3: First-Run Onboarding + Entry Point

**Rationale:** Without onboarding, BRAIN_PATH is the single highest-risk silent failure point. Onboarding must run before any hook features are useful to the user. The `claude --agent brain-mode` entry point is also required before non-developer users can activate brain mode. Built after Phases 1-2 so it can confidently onboard users into a working system.

**Delivers:** First-run detection (checks `onboarding-state.json`), guided BRAIN_PATH setup, vault directory structure creation, `brain-mode` subagent (`~/.claude/agents/brain-mode.md`) activated via `claude --agent brain-mode`, and optionally a shell alias `claude-brain`. BRAIN_PATH validation in all hooks fails loudly with specific fix instructions.

**Addresses:** First-run onboarding (table stake), `claude --brain` entry point (MVP feature), BRAIN_PATH silent degradation pitfall (critical), cross-directory vault operations (differentiator — now automatic via hooks).

**Avoids:** Silent BRAIN_PATH degradation — onboarding is the BRAIN_PATH gate; hooks validated before this phase shipped in Phase 1.

**Research flag:** The `--brain` flag does not exist in Claude Code; it must be implemented as a shell alias or wrapper invoking `claude --agent brain-mode`. Confirm subagent `skills` frontmatter field preloads existing brain-* skills correctly at v2.1.79.

---

### Phase 4: Competitive Differentiators (Adaptive Mentoring + Error Intelligence)

**Rationale:** With the foundation validated in daily use (Phases 1-3), the vault begins accumulating patterns. Phase 4 builds the features that differentiate brain mode from passive MEMORY.md: milestone auto-capture at git milestones, error pattern recognition, and adaptive mentoring progression. These are sequenced after the vault has real data to operate on.

**Delivers:** `PostToolUse` hook detecting git commit/merge patterns and triggering capture. `PostToolUseFailure` hook classifying errors and incrementing pattern-store counters. Adaptive mentoring logic in `brain-mode/SKILL.md` (warn → silent fix → investigate). Statusline color states reflecting mentoring level. Pattern encounter tracking with history rotation.

**Addresses:** Milestone auto-capture (P2), error pattern recognition (P2), pattern encounter tracking (P2), adaptive mentoring (future), color-coded brain states (P1 differentiator — color wiring to mentoring level).

**Avoids:** Notification fatigue — adaptive mentoring starts as logging-only for at least one milestone before enabling visible recommendations. Acknowledgment rate tracked; gate on >30% before increasing recommendation frequency.

**Research flag:** Needs phase research. Adaptive mentoring thresholds (warn_to_silent at 2 encounters, silent_to_investigate at 5) are research estimates — real thresholds will require tuning against actual usage. Error pattern classification (fuzzy matching vs structured tagging) is not yet designed and needs a concrete approach before implementation.

---

### Phase Ordering Rationale

- **Dependency chain is strict:** `BRAIN_PATH` library → hooks → session lifecycle → onboarding → adaptive features. Nothing works if the earlier layer is broken.
- **Pitfall-first approach:** Phases 1-2 exist specifically to address the three critical infrastructure pitfalls before any feature logic is built on top. Retrofitting guards into 6 hook scripts is more expensive than building them into the template at Phase 1.
- **Validate before differentiating:** Phase 3 onboarding ships before Phase 4 competitive features so that real users are using the system before the more complex behaviors are enabled. This directly prevents the adaptive mentoring fatigue pitfall — the vault needs real patterns before pattern matching is useful.
- **Context window discipline throughout:** The 2,000-token SessionStart budget is a constraint that shapes all phases. Phase 2 establishes and tests it; Phases 3-4 must not violate it when adding new context injection.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (Adaptive Mentoring):** Threshold tuning, error pattern classification design, and mentoring escalation logic are not yet specified. Run `/gsd:research-phase` before detailed planning.
- **Phase 3 (Onboarding UX):** The specific UX of first-run flow — what to show, what to ask, how to detect the two distinct cases (BRAIN_PATH unset vs set but vault empty) — needs more concrete design before implementation.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Hook Infrastructure):** Official docs fully specify hook event types, exit codes, JSON schemas, and `stop_hook_active` guard. Build directly from docs.
- **Phase 2 (Session Lifecycle):** Context injection via `additionalContext`, PreCompact transcript reading, and atomic vault writes are all well-documented patterns.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Sourced from official Claude Code docs, verified against live v2.1.79. All hook events, statusline schema, skill frontmatter, and subagent configuration confirmed. |
| Features | HIGH | Table stakes and differentiators verified against official docs and multiple community sources. Platform constraints (PreCompact read-only, no native idle hook, `--brain` flag nonexistent) are confirmed, not inferred. |
| Architecture | HIGH | Component boundaries, data flow, and build order sourced from official docs. Pattern store schema and IPC via shared files is the only approach available given hook subprocess isolation. |
| Pitfalls | HIGH | Top pitfalls verified from official issue tracker (Stop hook loop), official Anthropic engineering docs (context bloat), and official hooks reference (exit code contract). Not speculative. |

**Overall confidence:** HIGH

### Gaps to Address

- **Adaptive mentoring thresholds:** The warn/silent/investigate encounter count thresholds (2 and 5) are estimates from research — not validated. Treat as starting points and plan for threshold tuning after Phase 4 ships.
- **Error pattern classification approach:** PITFALLS.md notes this requires "fuzzy matching or structured tagging" but does not specify which. This design decision must be made before Phase 4 implementation begins. Structured tagging is lower complexity; fuzzy matching is higher fidelity.
- **`/clear` pre-capture timing:** FEATURES.md confirms `/clear` maps to `SessionStart` with `source=clear` rather than a separate pre-clear hook — meaning capture happens retroactively (reading the transcript) rather than intercepting the clear. This is a confirmed platform constraint, not a design choice, but the UX implications (capture after clear vs before) should be validated in Phase 2 testing.
- **Windows Git Bash compatibility:** `stat` flags differ between macOS (`-f %m`) and Linux/Git Bash (`-c %Y`). The `lib/brain-path.sh` shared library must detect OS and branch accordingly. This is noted in STACK.md but not yet implemented anywhere.
- **Subagent `skills` frontmatter field:** Whether the `skills` field in `agents/brain-mode.md` preloads existing `brain-capture`, `brain-audit`, and `daily-note` skills at session start needs verification in a live session before Phase 3 ships.

---

## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — hook event types, exit code contract, `stop_hook_active`, JSON schema, async mode
- [Claude Code Skills Reference](https://code.claude.com/docs/en/skills) — SKILL.md frontmatter, `context: fork`, `disable-model-invocation`, `${CLAUDE_SKILL_DIR}`
- [Claude Code StatusLine Reference](https://code.claude.com/docs/en/statusline) — stdin JSON schema, ANSI support, caching pattern, update frequency
- [Claude Code Subagents Reference](https://code.claude.com/docs/en/sub-agents) — `--agent` flag, agent frontmatter, `~/.claude/agents/` location
- [Claude Code Memory Reference](https://code.claude.com/docs/en/memory) — CLAUDE.md locations, auto memory, `@path` imports
- [Claude Code Settings Reference](https://code.claude.com/docs/en/settings) — `settings.json` schema, `env` block, scope hierarchy
- [Effective Context Engineering for AI Agents — Anthropic Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — context window budget guidance
- [Claude Code Issue #10205 — Stop hook infinite loop](https://github.com/anthropics/claude-code/issues/10205) — confirmed Stop hook loop behavior
- Live Claude Code v2.1.79 — confirmed via `claude --version` on Windows 10, 2026-03-19

### Secondary (MEDIUM confidence)
- [claude-mem GitHub (thedotmack)](https://github.com/thedotmack/claude-mem) — competitor feature analysis
- [Claude Code Hooks Guide (claudefa.st)](https://claudefa.st/blog/tools/hooks/hooks-guide) — hook patterns, consistent with official docs
- [5 Claude Code Hook Mistakes (DEV Community)](https://dev.to/yurukusa/5-claude-code-hook-mistakes-that-silently-break-your-safety-net-58l3) — exit code and JSON corruption pitfalls
- [When Your AI Memory System Eats Its Own Context Window (zolty.systems)](https://blog.zolty.systems/posts/2026-02-23-ai-context-window-audit) — context bloat case study with measurements
- [Claude Code Context Optimization: 54% token reduction (GitHub Gist)](https://gist.github.com/johnlindquist/849b813e76039a908d962b2f0923dc9a) — token budget measurements
- [Awesome Claude Code (hesreallyhim)](https://github.com/hesreallyhim/awesome-claude-code) — ecosystem signal

### Tertiary (LOW confidence)
- [AI memory frameworks overview (machinelearningmastery.com)](https://machinelearningmastery.com/the-6-best-ai-agent-memory-frameworks-you-should-try-in-2026/) — ecosystem context only
- [PKM features analysis (golinks.com)](https://www.golinks.com/blog/10-best-personal-knowledge-management-software-2026/) — table stakes validation only
- [UX and AI in 2026 (Cleverit Group)](https://www.cleveritgroup.com/en/blog/ux-and-ai-in-2026-from-experimentation-to-trust) — notification fatigue general UX research

---
*Research completed: 2026-03-19*
*Ready for roadmap: yes*
