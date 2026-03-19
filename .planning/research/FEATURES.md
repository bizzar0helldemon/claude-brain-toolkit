# Feature Research

**Domain:** CLI AI Knowledge Management Mode / Autonomous Session Partner
**Researched:** 2026-03-19
**Confidence:** HIGH (Claude Code platform mechanics verified via official docs; ecosystem patterns verified via multiple sources)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that any credible brain/memory mode must have. Missing these = product feels broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Session context injection at startup | Every AI memory tool in 2026 does this. Users expect the AI to "know" relevant context without being told. | MEDIUM | SessionStart hook fires on startup, resume, clear, and compact — verified in Claude Code docs. Use `additionalContext` field in hookSpecificOutput. |
| Persistent knowledge across sessions | Core promise of any "brain" or memory system. Short-term context only = user frustration. | LOW | CLAUDE.md + auto MEMORY.md system already handles this in Claude Code natively. Brain mode must leverage and augment it, not fight it. |
| Clear indicator that brain mode is active | Users need to know when a special mode is engaged. No feedback = disorienting. | LOW | Statusline is the natural place. Claude Code statusline docs confirm ANSI color codes and multi-line output are fully supported. |
| Pre-clear capture (don't lose context) | Context loss on /clear is the most complained-about pain point in CLI AI workflows. Users will expect brain mode to solve this. | MEDIUM | PreCompact hook fires before /compact. Need to verify whether a pre-clear hook exists independently of PreCompact. PreCompact covers auto-compact and manual /compact — /clear maps to SessionStart with source=clear. |
| BRAIN_PATH vault location | Users working across multiple projects need a single authoritative vault location. Without this, brain operations have no stable home. | LOW | Env var pattern is established. Claude Code supports env vars in hooks and scripts natively. `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` env var shows Anthropic already uses this pattern. |
| First-run onboarding | Any tool requiring initial setup that skips onboarding gets abandoned. Setting BRAIN_PATH and creating the vault are friction points that need guided handling. | LOW | One-time setup flow. No platform complexity — just detection + guided prompts. |
| Manual skill invocation still works | Users who prefer explicit control should not lose the ability to call /brain-capture, /brain-intake etc. directly. | LOW | Additive orchestration. Brain mode activates hooks; manual invocations remain independent. Zero regression risk. |

### Differentiators (Competitive Advantage)

Features that make this meaningfully different from passive CLAUDE.md + MEMORY.md. Not expected, but high value.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Adaptive mentoring progression (warn → silent fix → investigate) | Existing memory systems store facts but don't adapt their behavior based on encounter frequency. This creates a genuinely different interaction model: teaching mode early, automation mode later. | HIGH | Requires pattern encounter tracking in the vault. Each pattern stored with a `seen_count` field. Logic: count=1 → proactive warning, count=2-4 → silent correction with note, count=5+ → root cause investigation trigger. |
| Milestone auto-capture (commits, PR merges, phase completions) | No current CLI brain tool captures learnings at natural workflow milestones automatically. Users capture nothing unless they remember to. | MEDIUM | PostToolUse hook detects bash tool calls matching git commit / git merge patterns. Trigger /brain-capture with milestone context. |
| Color-coded brain states in statusline | Statusline customization is common (ccstatusline, starship-claude) but none show AI brain processing state. Provides at-a-glance workflow awareness unique to this tool. | LOW | Three states: idle (default color), actively loading vault context (yellow/amber), capturing/writing (green). Driven by a temp state file the brain writes to and the statusline script reads. |
| Idle detection + state offer | No current tool proactively offers to capture or summarize when the user pauses. Claude-mem captures everything automatically (unfocused); this offers focused choices at natural pauses. | HIGH | Idle detection is not a built-in Claude Code hook event (TeammateIdle is for agent teams only, not interactive sessions). Must be approximated via timestamp tracking between Stop hook events. Complexity: HIGH. |
| Error pattern recognition and surfacing | Recognizing that a current error matches a previously-solved problem, without being asked. The gap between MEMORY.md (passive recall) and active pattern matching. | HIGH | PostToolUseFailure hook provides the entry point. Brain reads vault patterns, compares against current error text. Requires fuzzy matching or structured tagging. |
| Cross-directory vault operations | Most brain-like tools are project-scoped. BRAIN_PATH enables a single vault across all projects — a genuine architectural differentiator. | LOW | Already designed into the toolkit. Brain mode makes it automatic via hook context injection. CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 with --add-dir covers the load path. |
| Knowledge bidirectional flow annotation | Explicitly tracking what flows brain→session (pitfalls injected, prefs loaded) vs session→brain (captures, daily notes) gives users insight into what the brain is doing. Builds trust. | MEDIUM | Logging in MEMORY.md or a brain-activity.log file. Shown in startup summary. |
| Vault relocate command | Users reorganize drives. Vault relocation without breaking the entire system is a practical differentiator most tools ignore. | LOW | Simple: update BRAIN_PATH in shell profile, run a re-index command. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem like natural extensions but should be deliberately avoided.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Multi-vault support | Power users want project-specific and personal vaults | Dramatically increases complexity. Every operation now requires vault selection logic. Ambiguity about where to save kills capture rate. The PROJECT.md explicitly scopes to single vault. | One brain per human. Use CLAUDE.md project files for project-specific instructions. |
| Cloud sync / remote vault | Users want vault available across machines | Out of scope per PROJECT.md. Adds auth, conflict resolution, privacy surface, and dependency on external services. | Vault is local filesystem. Users who want sync can use their own tools (Dropbox, Obsidian Sync, etc.) on the BRAIN_PATH directory. |
| Real-time capture of everything | Seems like "more is better" — capture every exchange | Creates noise, bloat, and low-quality patterns. Claude-mem does this and the compressed output requires review. Quality > quantity for a knowledge base that gets injected into sessions. | Capture at natural milestones (commits, clears, explicit invocation). Adaptive mentoring captures repeated patterns selectively. |
| New brain skills pre-designed during build | Anticipating future skill needs before real usage | Pre-designed skills that don't match real workflows go unused. PROJECT.md correctly defers this. | Ship the orchestration layer. New skills emerge from observing which manual invocations users repeat most. |
| Full conversation history storage | Users want to search past sessions | Storage grows unboundedly. Full history is different from distilled knowledge. Recall (github.com/zippoxer) already does full-text search of Claude Code sessions. | Capture distilled patterns and insights into MEMORY.md topic files. Let session transcripts (which Claude Code already stores) handle raw history. |
| Non-Claude-Code integrations | Users may want the brain in other AI tools | Out of scope per PROJECT.md. Each integration is a new testing surface and compatibility dependency. | CLAUDE.md exports (brain-scan output) are plain markdown — portable to any tool that accepts text context. |
| Interactive permission prompts for every capture | Safety-first instinct | Every prompt interrupts flow. If brain mode requires constant approval, users disable it. | Capture automatically at milestones (hooks). Use dry-run/auto modes on /brain-inbox for explicit control when users want it. |

---

## Feature Dependencies

```
BRAIN_PATH env var
    └──required by──> Session context injection
    └──required by──> Pre-clear capture
    └──required by──> Milestone auto-capture
    └──required by──> Error pattern recognition
    └──required by──> Cross-directory vault operations
    └──required by──> Vault relocate command

First-run onboarding
    └──establishes──> BRAIN_PATH env var
    └──creates──> Brain vault directory structure

Session context injection at startup
    └──enhances──> Adaptive mentoring progression
    └──feeds into──> Error pattern recognition

Pattern encounter tracking
    └──required by──> Adaptive mentoring progression (warn → silent → investigate)

Brain active indicator (statusline)
    └──enhanced by──> Color-coded brain states

Pre-clear capture
    └──required by──> "Don't lose context" table stake
    └──uses──> /brain-capture skill
    └──uses──> /daily-note skill

Milestone auto-capture
    └──depends on──> PostToolUse hook (git commands detected)
    └──uses──> /brain-capture skill

Error pattern recognition
    └──depends on──> PostToolUseFailure hook
    └──depends on──> Pattern encounter tracking

Idle detection
    └──depends on──> Stop hook timestamp tracking
    └──conflicts with──> Low-interruption design principle (use sparingly)
```

### Dependency Notes

- **BRAIN_PATH is the keystone**: every feature that touches the vault requires it. First-run onboarding must establish BRAIN_PATH before any other feature can function. This makes onboarding Phase 1 work, not Phase 2.
- **Pattern tracking required before adaptive mentoring**: adaptive mentoring is the highest-value differentiator, but it cannot function without the pattern encounter counter infrastructure being in place first. Build tracking, then build the mentoring behavior on top.
- **Idle detection conflicts with low-interruption principle**: the feature has value but can easily become noise. Build it as opt-in, not default-on. This resolves the conflict.
- **Statusline states depend on state file writing**: brain scripts must write a temp state file that the statusline script reads. This is a lightweight IPC mechanism, not a formal dependency. Keep the state file simple (one word: idle/loading/capturing).

---

## MVP Definition

### Launch With (v1)

Minimum viable product — what validates the core concept that brain mode compounds over time.

- [ ] First-run onboarding — establishes BRAIN_PATH, creates vault structure, confirms tools available. Without this, nothing else works.
- [ ] `claude --brain` entry point — launches with brain mode active. Even a stub that just confirms mode is active validates the launch pattern.
- [ ] Brain emoji in statusline — single indicator that brain mode is active. Low effort, immediately reinforces mode awareness.
- [ ] Session context injection — SessionStart hook loads relevant vault context (pitfalls, preferences, project history for current cwd). This is the primary value delivery mechanism.
- [ ] Pre-clear capture — PreCompact hook auto-triggers /brain-capture then /daily-note. Solves the most visible pain point (losing context on /clear).
- [ ] Color-coded brain states — idle/loading/capturing states in statusline. Makes the brain's activity visible without interrupting flow.

### Add After Validation (v1.x)

Features to add once core session injection + pre-clear capture are working and in daily use.

- [ ] Milestone auto-capture — add after confirming users find value in manual captures at commits/milestones. Trigger: users start calling /brain-capture manually after commits.
- [ ] Error pattern recognition — add after vault has accumulated enough patterns to make matching useful. Trigger: vault has 10+ patterns tagged with error context.
- [ ] Pattern encounter tracking — add as infrastructure for adaptive mentoring. Can be invisible to users at first.

### Future Consideration (v2+)

Features to defer until the v1 pattern is validated.

- [ ] Adaptive mentoring progression — highest complexity, highest payoff. Requires encounter tracking infrastructure plus tuning the warn/silent/investigate thresholds. Defer until encounter tracking is running and generating data.
- [ ] Idle detection — opt-in only. Requires user feedback on what "useful idle suggestions" actually look like in practice. Don't design blind.
- [ ] Vault relocate command — needed but low urgency. Users relocate vaults rarely. Add when someone actually needs it.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| BRAIN_PATH + first-run onboarding | HIGH | LOW | P1 |
| Session context injection (SessionStart hook) | HIGH | MEDIUM | P1 |
| Pre-clear capture (PreCompact hook) | HIGH | MEDIUM | P1 |
| Brain active indicator in statusline | MEDIUM | LOW | P1 |
| Color-coded brain states | MEDIUM | LOW | P1 |
| Milestone auto-capture (PostToolUse hook) | HIGH | MEDIUM | P2 |
| Error pattern recognition (PostToolUseFailure hook) | HIGH | HIGH | P2 |
| Pattern encounter tracking | HIGH | MEDIUM | P2 — enables adaptive mentoring |
| Adaptive mentoring (warn → silent → investigate) | HIGH | HIGH | P2 |
| Idle detection | MEDIUM | HIGH | P3 — opt-in only |
| Knowledge flow annotation / activity log | LOW | LOW | P3 — visibility feature, nice to have |
| Vault relocate command | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch — validates the core concept
- P2: Should have — adds the differentiation that justifies brain mode over manual skill invocation
- P3: Nice to have — polish and edge cases

---

## Competitor Feature Analysis

| Feature | claude-mem (thedotmack) | Claude Code MEMORY.md (native) | Claude Brain Mode (this project) |
|---------|------------------------|-------------------------------|----------------------------------|
| Session context injection | Yes — auto-injects compressed history | Yes — MEMORY.md first 200 lines at startup | Yes — injected via SessionStart hook with vault context |
| Capture mechanism | Automatic (captures everything) | Automatic (Claude decides what to save) | Milestone-triggered + manual |
| Quality control | AI compression (lossy) | Claude's judgment | Structured capture via /brain-capture interview |
| Cross-project vault | No — per-session | No — per-git-repo | Yes — single BRAIN_PATH vault across all projects |
| Pattern tracking | No | No | Yes — encounter counts drive adaptive mentoring |
| Adaptive behavior | No | No | Yes — warn → silent → investigate progression |
| Statusline integration | No | No | Yes — brain state visible at all times |
| Pre-clear protection | No | Survives /compact via reload | Yes — explicit capture before /clear |
| Personal identity data | No — code-focused | No | Yes — IDENTITY.md, intake sessions, creative works |
| Onboarding | No | /init command | Guided first-run flow |
| Manual skill invocation | No | N/A | Yes — existing skills still work independently |

---

## Platform Constraints Affecting Features

These are verified platform facts that shape what's possible:

**SessionStart hook** (source: official Claude Code docs, HIGH confidence)
- Fires on: startup, resume, clear, compact
- Can inject: `additionalContext` in hookSpecificOutput JSON
- Data available: session_id, transcript_path, cwd, source, model

**PreCompact hook** (source: official Claude Code docs, HIGH confidence)
- Fires before: manual /compact and auto-compact
- Capability: read-only observability only — cannot inject content, cannot block
- Note: This means pre-clear capture must be triggered differently. /clear maps to SessionStart with source=clear. The brain must detect source=clear on startup and offer retroactive capture from the transcript, not intercept the clear itself.

**Statusline** (source: official Claude Code docs, HIGH confidence)
- Updates: after each assistant message, on permission mode change, on vim mode toggle
- Can output: multiple lines, ANSI colors, OSC 8 links
- Data available: full JSON session state including model, cwd, context usage, cost, agent name
- Note: statusline does NOT receive brain-specific state — brain state must be communicated via a temp file or env var that the statusline script reads independently.

**Idle detection** (source: official Claude Code docs + hooks guide, HIGH confidence)
- TeammateIdle hook exists but only fires for agent team teammates, not interactive sessions
- No native idle hook for interactive sessions
- Must be approximated: track timestamps of Stop hook events, compare against configurable threshold
- Confidence on approximation approach: MEDIUM (pattern is common but not verified as working implementation)

**`--brain` launch flag** (source: CLI reference research, MEDIUM confidence)
- Custom flags require the `--agent` flag pattern or environment variable injection
- `claude --brain` is not a native flag — requires implementation via wrapper script or alias that sets env vars and launches with appropriate hooks/settings
- No official "custom launch mode" plugin API found — this is a UX design decision, not a platform capability
- Recommend: implement as a shell alias or wrapper script that sets BRAIN_MODE=1 env var and launches claude with pre-configured hooks active

---

## Sources

- [Claude Code Memory Docs (official)](https://code.claude.com/docs/en/memory) — HIGH confidence, verified 2026-03-19
- [Claude Code Statusline Docs (official)](https://code.claude.com/docs/en/statusline) — HIGH confidence, verified 2026-03-19
- [Claude Code Hooks Guide (claudefa.st, multi-source verified)](https://claudefa.st/blog/tools/hooks/hooks-guide) — MEDIUM confidence (third-party but detailed, consistent with official docs)
- [claude-mem GitHub (thedotmack)](https://github.com/thedotmack/claude-mem) — MEDIUM confidence (active community project, competitor analysis)
- [Awesome Claude Code (hesreallyhim)](https://github.com/hesreallyhim/awesome-claude-code) — MEDIUM confidence (community curation, ecosystem signal)
- [claude-mem article (aitoolly.com)](https://aitoolly.com/ai-news/article/2026-03-17-claude-mem-a-new-plugin-for-automated-coding-session-memory-and-context-injection-via-claude-code) — LOW confidence (single source, used for competitor feature analysis only)
- [AI memory frameworks overview (machinelearningmastery.com)](https://machinelearningmastery.com/the-6-best-ai-agent-memory-frameworks-you-should-try-in-2026/) — LOW confidence (ecosystem context only)
- [PKM features analysis (golinks.com)](https://www.golinks.com/blog/10-best-personal-knowledge-management-software-2026/) — LOW confidence (used for table stakes validation only)

---

*Feature research for: Claude Brain Mode — CLI AI Knowledge Management*
*Researched: 2026-03-19*
