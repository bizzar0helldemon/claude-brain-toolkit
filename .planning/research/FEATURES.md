# Feature Landscape

**Domain:** CLI AI Knowledge Management Mode / Autonomous Session Partner
**Researched:** 2026-03-19 (v1.0/v1.1 original); updated 2026-03-21 for v1.2 milestone
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
| Idle detection + state offer | No current tool proactively offers to capture or summarize when the user pauses. Claude-mem captures everything automatically (unfocused); this offers focused choices at natural pauses. | LOW-MEDIUM | **v1.2 target.** Native mechanism confirmed: Notification hook with `idle_prompt` matcher fires when Claude has been idle ~60s. Supports `additionalContext` injection into Claude's context. Cannot block or modify — advisory only. Implementation: configure Notification/idle_prompt hook to inject capture-offer context. Much simpler than the timestamp-tracking approach noted in v1.1 research. |
| Vault relocate command | Users reorganize drives. Vault relocation without breaking the entire system is a practical differentiator most tools ignore. | LOW | **v1.2 target.** Standard implementation: (1) move the vault directory, (2) update BRAIN_PATH in settings.json via jq atomic write, (3) update shell profile via sed in-place or append+deduplicate pattern. brain_path_validate already surfaces the "vault missing" error with relocation instructions — relocate skill closes the loop. |
| Pattern encounter tracking + progressive responses | Existing memory systems store facts. This adapts behavior based on how often the same pitfall has been hit: teach early, automate later, investigate at recurrence. Transforms the pattern store from a lookup table into a behavioral guide. | MEDIUM | **v1.2 target.** Infrastructure partially built: `update_encounter_count` and `pattern-store.json` exist and are already called in post-tool-use-failure.sh. Missing: (1) the response behavior varies only by whether a match was found, not by encounter_count value; (2) no progressive response logic reads encounter_count yet. Add: count-aware branching in post-tool-use-failure.sh (warn at 1, brief-note at 2-4, investigate-offer at 5+). |
| Adaptive mentoring progression (warn → silent fix → investigate) | Existing memory systems store facts but don't adapt their behavior based on encounter frequency. This creates a genuinely different interaction model: teaching mode early, automation mode later. | HIGH | **Deferred to v2+.** Full adaptive mentoring (auto-fix + root cause investigation) requires tuned thresholds from real usage data. v1.2 delivers the foundation (encounter counts + progressive responses) without the full automation. |
| Milestone auto-capture (commits, PR merges, phase completions) | No current CLI brain tool captures learnings at natural workflow milestones automatically. Users capture nothing unless they remember to. | MEDIUM | **Shipped in v1.0.** PostToolUse hook detects git commit Bash calls and triggers capture. |
| Color-coded brain states in statusline | Statusline customization is common but none show AI brain processing state. Provides at-a-glance workflow awareness unique to this tool. | LOW | **Shipped in v1.1.** Three states: idle (default), captured (green), error (red). Driven by .brain-state temp file. |
| Error pattern recognition and surfacing | Recognizing that a current error matches a previously-solved problem without being asked. | HIGH | **Shipped in v1.0.** PostToolUseFailure hook matches against pattern-store.json and injects past solution via additionalContext. |
| Cross-directory vault operations | Most brain-like tools are project-scoped. BRAIN_PATH enables a single vault across all projects. | LOW | **Shipped in v1.0.** Designed into the architecture from the start. |

### Anti-Features (Commonly Requested, Often Problematic)

Features to deliberately avoid even when they seem like natural extensions.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Multi-vault support | Power users want project-specific and personal vaults | Dramatically increases complexity. Every operation now requires vault selection logic. Ambiguity about where to save kills capture rate. | One brain per human. Use CLAUDE.md project files for project-specific instructions. |
| Cloud sync / remote vault | Users want vault available across machines | Out of scope per PROJECT.md. Adds auth, conflict resolution, privacy surface, and external service dependency. | Vault is local filesystem. Users who want sync can use their own tools (Dropbox, rsync) on the BRAIN_PATH directory. |
| Real-time capture of everything | Seems like "more is better" | Creates noise, bloat, and low-quality patterns. Claude-mem does this and produces compressed output requiring review. | Capture at natural milestones. Progressive responses surface repeated patterns selectively. |
| Forced idle-detection capture | Idle = opportunity to capture | Violates low-interruption principle established in v1.1. If idle detection captures without asking, it becomes the same anti-pattern as the stop hook firing 4x on empty sessions. | Idle detection OFFERS capture via additionalContext injection — does not force it. User decides. |
| Unlimited encounter history in pattern store | More history = better pattern detection | Pattern store JSON payload grows unboundedly. Hook invocations start slowing as store grows. | Rotate encounter history at a hard cap (50 entries max). Track encounter_count per pattern rather than full event history. |
| Interactive idle prompts that require yes/no | Make the offer explicit so user can't miss it | Blocks the session if user is unavailable. Interrupts flow mid-task. | Use additionalContext injection: context appears discretely in transcript, Claude mentions the offer conversationally. User can ignore without any friction. |
| Automatic BRAIN_PATH update on vault relocation | Detect new path automatically when vault moves | Unreliable without filesystem watchers (not available in Claude Code hooks context). Silent auto-update is worse than explicit relocation — user loses track of where vault is. | Explicit `/brain-relocate` command: user provides old path, new path. Script validates, moves files if needed, updates config. |

---

## Feature Details: v1.2 Targets

### LIFE-06: Idle Detection

**What it does:** When Claude finishes responding and the user hasn't prompted for ~60 seconds, inject an offer into Claude's context suggesting it could summarize the session or run /brain-capture.

**Native mechanism (HIGH confidence, verified against official Claude Code docs 2026-03-21):**
The `Notification` hook with matcher `"idle_prompt"` is the correct implementation path. It fires when Claude is waiting for user input (approximately 60 seconds idle). It supports `additionalContext` injection via `hookSpecificOutput`. It cannot block or modify the notification — advisory only.

This replaces the timestamp-tracking approach noted in v1.1 research. The native hook is simpler, more reliable, and doesn't require any polling or state file tricks.

**Implementation approach:**
```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/idle-detection.sh"
          }
        ]
      }
    ]
  }
}
```

The hook script reads transcript_path from hook input, evaluates whether the session has capturable content (same heuristic as stop.sh: file writes or git commits present), and only injects context when content warrants capture. Sessions with no capturable content get no context injection — silently.

**Expected behavior tiers:**
- Session has no capturable content: no output, no injection (silent)
- Session has capturable content: inject `additionalContext` offering to run /brain-capture
- inject context: "You've been idle for a moment. This session has [N file writes / N commits]. Would you like to run /brain-capture to preserve the key learnings? Or I can briefly summarize what we've done so far."

**Anti-intrusion guard:** The offer should appear at most once per session. Track via a state file flag (e.g., `.brain-idle-offered`) that the hook checks before injecting. Clear the flag on SessionStart.

**Complexity:** LOW-MEDIUM. The hook plumbing is straightforward. The main work is the capturable-content heuristic (already exists in stop.sh) and the one-offer-per-session guard.

---

### ONBR-03: Vault Relocate

**What it does:** When the user has moved their vault directory, update BRAIN_PATH in both settings.json and their shell profile so brain mode works again from the new location.

**Expected behavior:**
1. User invokes `/brain-relocate` (or `brain-relocate` skill)
2. Skill confirms the new vault path exists
3. Skill updates settings.json `env.BRAIN_PATH` via jq atomic write (temp + mv pattern — same as used in write_brain_state)
4. Skill updates shell profile (`~/.zshrc` or `~/.bashrc`) — uses sed to replace the existing `export BRAIN_PATH=` line, or appends if not found
5. Confirms update with a summary: "BRAIN_PATH updated to /new/path in settings.json and ~/.zshrc"
6. Reminds user to `source ~/.zshrc` (cannot be done automatically — sourcing a shell profile from a script only affects the subshell)

**Implementation approach:**
The skill is a Claude Code skill (SKILL.md + optional shell script). Because the shell profile update involves `sed -i` and the behavior differs between GNU sed (Linux) and BSD sed (macOS), the skill should use a portable pattern: write to a temp file, then mv — same pattern as all other brain-path.sh file operations.

The settings.json update:
```bash
jq --arg new_path "$NEW_BRAIN_PATH" '.env.BRAIN_PATH = $new_path' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp"
mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

Shell profile detection: check SHELL env var, map to profile file (`zsh` → `~/.zshrc`, `bash` → `~/.bashrc` or `~/.bash_profile`).

**Brain-path.sh integration:** `brain_path_validate` already surfaces the exact error message for a missing vault directory, with relocation instructions in the error text. The relocate skill is the command-form closure of that error path. Users who see the brain_path_validate error have a clear action to take.

**Complexity:** LOW. Mostly file I/O (jq + sed). No new hook plumbing required. Implemented as a skill, not a hook.

---

### MENT-01 + MENT-02: Pattern Encounter Tracking + Progressive Responses

**What they do:** The pattern store already records `encounter_count` per pattern (via `update_encounter_count` in brain-path.sh) and already increments on each match. MENT-01 and MENT-02 add the behavioral layer: the response Claude gives when a pattern matches should change based on how many times this pattern has been hit.

**Current behavior (already shipped):**
- Any match → inject `additionalContext` with `"Past solution found for this error:\n\n$MATCH"`
- The response is identical whether this is the 1st or 20th time the error occurred

**v1.2 target behavior (progressive responses):**

| encounter_count | Response | Rationale |
|-----------------|----------|-----------|
| 1 (first time) | Full warning: detailed explanation of the pattern + solution | User doesn't know this pitfall yet. Teach it fully. |
| 2-4 (repeat) | Brief note: "You've hit [pattern] before ([N] times). Solution: [short form]" | User has seen the explanation. Reminder is enough. |
| 5+ (recurring) | Investigate offer: "This is recurring ([N] times). Consider investigating root cause rather than applying the solution again." | Recurring after multiple fixes = systemic issue. Signal it. |

**Implementation approach:**
The branching logic lives in post-tool-use-failure.sh. After the pattern match and `update_encounter_count` call, read back the (now-incremented) count and select the response template.

```bash
# Read updated count after increment
CURRENT_COUNT=$(jq -r \
  --arg error_msg "$ERROR_MSG" \
  '.patterns[] |
   . as $p |
   select(($error_msg | ascii_downcase) | contains($p.key | ascii_downcase)) |
   .encounter_count' \
  "$PATTERN_STORE" 2>/dev/null | head -1)

# Select response tier
if [ "$CURRENT_COUNT" -ge 5 ]; then
  CONTEXT_MSG="RECURRING ISSUE (seen $CURRENT_COUNT times): $MATCH\n\nConsider investigating the root cause — applying the same fix repeatedly suggests a systemic problem."
elif [ "$CURRENT_COUNT" -ge 2 ]; then
  CONTEXT_MSG="Seen before ($CURRENT_COUNT times): $MATCH"
else
  CONTEXT_MSG="Pattern recognized (first time): $MATCH\n\nThis is a known pitfall. [Full explanation from solution field]"
fi
```

**Complexity:** LOW-MEDIUM. The infrastructure (`encounter_count`, `update_encounter_count`, pattern-store.json schema) is already in place. The delta is count-aware branching in one existing hook script, plus response template tuning.

**Threshold calibration risk:** The 1/2-4/5+ thresholds are a starting hypothesis. They may need tuning after real usage. Document the thresholds explicitly in the pattern store schema as configurable constants, not magic numbers.

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
    └──enhances──> Pattern encounter tracking
    └──feeds into──> Error pattern recognition

Pattern encounter tracking (MENT-01)
    └──required by──> Progressive responses (MENT-02)
    └──infrastructure already exists──> update_encounter_count in brain-path.sh
    └──missing piece──> count-aware branching in post-tool-use-failure.sh

Progressive responses (MENT-02)
    └──depends on──> Pattern encounter tracking (MENT-01)
    └──foundation for──> Full adaptive mentoring (v2+)

Brain active indicator (statusline)
    └──enhanced by──> Color-coded brain states (shipped v1.1)

Pre-clear capture
    └──required by──> "Don't lose context" table stake
    └──uses──> /brain-capture skill
    └──uses──> /daily-note skill

Milestone auto-capture
    └──depends on──> PostToolUse hook (git commands detected)
    └──uses──> /brain-capture skill

Error pattern recognition
    └──depends on──> PostToolUseFailure hook
    └──depends on──> pattern-store.json (pattern encounter tracking)

Idle detection (LIFE-06)
    └──depends on──> Notification/idle_prompt hook (native Claude Code hook)
    └──depends on──> capturable-content heuristic (exists in stop.sh, reuse)
    └──depends on──> one-offer-per-session guard (new: .brain-idle-offered flag)
    └──compatible with──> Low-interruption design principle (offer-only, no force)

Vault relocate (ONBR-03)
    └──depends on──> brain_path_validate (already surfaces missing-vault error)
    └──closes loop on──> BRAIN_PATH not set / vault moved error path
    └──updates──> settings.json env.BRAIN_PATH (jq write)
    └──updates──> shell profile BRAIN_PATH export (sed/append)
```

### Dependency Notes

- **Idle detection uses native hook, not timestamp polling:** The `Notification/idle_prompt` hook is the correct implementation path (HIGH confidence, verified 2026-03-21). No timestamp tracking, no state file polling, no separate process required.
- **Pattern tracking infrastructure already built:** `update_encounter_count` exists and is called. MENT-01 and MENT-02 are a behavioral upgrade to existing infrastructure, not new infrastructure.
- **Vault relocate is a skill, not a hook:** No new lifecycle hook required. The skill runs as a Claude-orchestrated sequence: validate new path, update two config files, confirm to user.
- **Progressive response thresholds are configurable:** Define as constants in the pattern store schema or a brain-mode config file, not hardcoded in the hook script, to allow tuning without code changes.
- **Idle detection must re-use stop.sh heuristic:** The capturable-content detection logic (file writes, git commits) should be extracted to a shared function in brain-path.sh, not duplicated. DRY principle applies here — two hooks needing the same logic is the signal to extract.

---

## MVP Definition

### v1.2 Shipped (targeting this milestone)

Minimum set to close out v1.2 with the four active requirements (LIFE-06, ONBR-03, MENT-01, MENT-02):

- [ ] **LIFE-06: Idle detection** — Notification/idle_prompt hook injects capture offer. Guard: one offer per session, only when capturable content detected. Implementation: new `~/.claude/hooks/idle-detection.sh` + settings.json Notification hook entry.
- [ ] **ONBR-03: Vault relocate** — `/brain-relocate` skill updates BRAIN_PATH in settings.json and shell profile. Implementation: new skill in `global-skills/brain-relocate/` + supporting shell logic.
- [ ] **MENT-01: Pattern encounter tracking** — Already implemented (update_encounter_count called on match). Verify encounter_count is incrementing correctly and is readable. No new code if existing implementation is confirmed working.
- [ ] **MENT-02: Progressive responses** — Count-aware branching in post-tool-use-failure.sh. Three tiers: full warn (1), brief note (2-4), investigate offer (5+). Implementation: modify existing hook script.

### Defer to v1.3 or v2

- [ ] **Full adaptive mentoring** — Auto-fix + root cause investigation (MENT-02 extended). Requires real encounter data to tune thresholds. Build v1.2 first, observe, then tune.
- [ ] **Capturable-content extraction to shared function** — Extract shared heuristic from stop.sh into brain-path.sh. Valuable for long-term maintainability, not blocking v1.2.
- [ ] **Encounter history rotation / pattern store pruning** — Cap pattern store at 50 entries, rotate oldest. Important for performance but pattern store is small at v1.2 scale.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | v1.2 Priority | Status |
|---------|------------|---------------------|----------------|--------|
| BRAIN_PATH + first-run onboarding | HIGH | LOW | — | Shipped v1.0 |
| Session context injection (SessionStart hook) | HIGH | MEDIUM | — | Shipped v1.0 |
| Pre-clear capture (PreCompact hook) | HIGH | MEDIUM | — | Shipped v1.0 |
| Brain active indicator in statusline | MEDIUM | LOW | — | Shipped v1.0 |
| Smart stop hook (no-capture on trivial sessions) | HIGH | MEDIUM | — | Shipped v1.1 |
| Color-coded brain states | MEDIUM | LOW | — | Shipped v1.1 |
| MENT-01: Pattern encounter tracking (infrastructure) | HIGH | LOW | P1 — verify existing impl | Partially shipped — update_encounter_count exists, count-aware branching missing |
| MENT-02: Progressive responses | HIGH | LOW-MEDIUM | P1 — builds on MENT-01 | Not started |
| LIFE-06: Idle detection | MEDIUM | LOW-MEDIUM | P2 — native hook simplifies | Not started |
| ONBR-03: Vault relocate | LOW-MEDIUM | LOW | P3 — utility feature | Not started |
| Capturable-content shared function (DRY refactor) | LOW | LOW | P4 — defer | Not started |
| Full adaptive mentoring (v2 adaptive behavior) | HIGH | HIGH | Defer to v2 | Not started |
| Pattern store rotation / pruning | MEDIUM | LOW | Defer to v1.3 | Not started |

**Priority key:**
- P1: Must have for v1.2 — core intelligence features
- P2: Should have — the headlining UX improvement
- P3: Nice to have — closes a real but low-frequency user need
- P4: Defer — technical debt cleanup, not blocking

---

## Competitor Feature Analysis

| Feature | claude-mem (thedotmack) | Claude Code MEMORY.md (native) | Claude Brain Mode (this project) |
|---------|------------------------|-------------------------------|----------------------------------|
| Session context injection | Yes — auto-injects compressed history | Yes — MEMORY.md first 200 lines at startup | Yes — injected via SessionStart hook with vault context |
| Capture mechanism | Automatic (captures everything) | Automatic (Claude decides what to save) | Milestone-triggered + manual |
| Quality control | AI compression (lossy) | Claude's judgment | Structured capture via /brain-capture interview |
| Cross-project vault | No — per-session | No — per-git-repo | Yes — single BRAIN_PATH vault across all projects |
| Pattern tracking | No | No | Yes — encounter counts drive progressive responses (v1.2) |
| Adaptive behavior | No | No | Yes — warn → brief note → investigate progression (v1.2) |
| Statusline integration | No | No | Yes — brain state visible at all times |
| Pre-clear protection | No | Survives /compact via reload | Yes — explicit capture before /clear |
| Personal identity data | No — code-focused | No | Yes — IDENTITY.md, intake sessions, creative works |
| Onboarding | No | /init command | Guided first-run flow |
| Manual skill invocation | No | N/A | Yes — existing skills still work independently |
| Idle detection | No | No | Yes — native Notification/idle_prompt hook (v1.2) |
| Vault relocate | No | No | Yes — /brain-relocate skill (v1.2) |

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

**Notification hook — idle_prompt** (source: official Claude Code docs, HIGH confidence, verified 2026-03-21)
- Fires when: Claude has been idle and is waiting for user input (~60 seconds idle)
- Can inject: `additionalContext` via hookSpecificOutput (appears discretely in transcript)
- Cannot: block or modify notifications (read-only/advisory only)
- This IS the native idle detection mechanism. No timestamp-polling approximation needed.
- Input fields: session_id, transcript_path, cwd, hook_event_name, message, title, notification_type

**Statusline** (source: official Claude Code docs, HIGH confidence)
- Updates after each assistant message
- Brain state communicated via temp file (.brain-state) that statusline script reads

**Pattern store (brain-path.sh)** (source: codebase, HIGH confidence)
- `update_encounter_count` function exists, is called in post-tool-use-failure.sh
- Schema: `{version, created, updated, patterns: [{key, solution, encounter_count, last_seen}]}`
- Missing for v1.2: count-aware response branching after increment

---

## Sources

- [Claude Code Hooks Reference — official docs](https://code.claude.com/docs/en/hooks) — HIGH confidence, authoritative, verified 2026-03-21
- [Claude Code Notifications: Get Alerts When Tasks Finish — alexop.dev](https://alexop.dev/posts/claude-code-notification-hooks/) — MEDIUM confidence, practical implementation examples
- [Claude Code Hooks Complete Guide with 20+ Examples — aiorg.dev](https://aiorg.dev/blog/claude-code-hooks) — MEDIUM confidence, comprehensive examples
- [Progressive Disclosure — IxDF](https://ixdf.org/literature/topics/progressive-disclosure) — MEDIUM confidence, UX pattern reference
- [Progressive Disclosure Matters: AI Agents — AI Positive Substack](https://aipositive.substack.com/p/progressive-disclosure-matters) — LOW confidence (single source), ecosystem context for adaptive behavior patterns
- [Claude Code Memory Docs (official)](https://code.claude.com/docs/en/memory) — HIGH confidence, verified 2026-03-19
- [Claude Code Statusline Docs (official)](https://code.claude.com/docs/en/statusline) — HIGH confidence, verified 2026-03-19
- [claude-mem GitHub (thedotmack)](https://github.com/thedotmack/claude-mem) — MEDIUM confidence, competitor analysis
- hooks/lib/brain-path.sh (codebase) — HIGH confidence, authoritative for existing implementation

---

*Feature research for: Claude Brain Mode — CLI AI Knowledge Management*
*Original research: 2026-03-19*
*v1.2 update: 2026-03-21 — idle detection native hook verified, vault relocate and progressive response patterns researched*
