# Architecture Patterns

**Domain:** Claude Brain Mode v1.2 — idle detection, vault relocate, pattern encounter tracking
**Researched:** 2026-03-21
**Confidence:** HIGH (sourced from codebase direct inspection + existing architectural decisions)

---

## System Overview (v1.1 Baseline + v1.2 Additions)

```
Claude Code CLI Session
├── settings.json — hook registration, BRAIN_PATH env, statusLine command
│
├── statusline.sh ─────────────────────────────────────────────────────┐
│     reads: .brain-state (idle | captured | error)                    │
│     reads: stdin JSON (model, context %)                             │
│     [v1.2: no changes needed]                                        │
│                                                                       │
├── hooks/                                                              │
│   ├── session-start.sh ─── fires: SessionStart                       │
│   │     calls: brain_path_validate, build_brain_context              │
│   │     writes: .brain-state ("idle"), .brain-session-state.json     │
│   │     emits: additionalContext JSON                                 │
│   │     [v1.2: no changes needed]                                    │
│   │                                                                   │
│   ├── stop.sh ─────────────── fires: Stop                            │
│   │     reads: transcript_path (JSONL)                               │
│   │     writes: .brain-state ("captured" | "idle")                   │
│   │     emits: decision:block when capture warranted                 │
│   │     [v1.2: no changes needed]                                    │
│   │                                                                   │
│   ├── pre-compact.sh ───── fires: PreCompact                         │
│   │     emits: additionalContext (capture instruction)               │
│   │     [v1.2: no changes needed]                                    │
│   │                                                                   │
│   ├── post-tool-use.sh ── fires: PostToolUse                         │
│   │     watches: git commit commands                                  │
│   │     emits: decision:block to trigger /brain-capture              │
│   │     [v1.2: no changes needed]                                    │
│   │                                                                   │
│   ├── post-tool-use-failure.sh ── fires: PostToolUseFailure          │
│   │     reads: pattern-store.json (match error against keys)         │
│   │     writes: pattern-store.json (update_encounter_count)          │
│   │     emits: additionalContext with past solution (if match found) │
│   │     [v1.2: encounter_count already written — MENT-01 complete]   │
│   │                                                                   │
│   └── lib/
│       ├── brain-path.sh ── provides: brain_path_validate,           │
│       │     brain_log_error, emit_json, write_brain_state,           │
│       │     init_pattern_store, update_encounter_count               │
│       │     [v1.2: no changes needed for MENT-01]                    │
│       │     [v1.2: add vault_relocate helper for ONBR-03]            │
│       │                                                               │
│       └── brain-context.sh ── provides: build_brain_context,        │
│             collect_vault_entries, get_project_name,                 │
│             write_session_state, build_summary_block                 │
│             [v1.2: no changes needed]                                │
│                                                                       │
├── agents/brain-mode.md ─── agent definition                          │
│     [v1.2: update Available Skills to list new commands]             │
│                                                                       │
└── commands/ ─────────────────────────────────────────────────────────┘
    ├── brain/brain-add-pattern.md
    └── brain/brain-relocate.md  [v1.2: NEW — ONBR-03]

global-skills/
├── brain-capture/SKILL.md
├── brain-audit/SKILL.md
└── daily-note/SKILL.md

onboarding-kit/skills/
└── brain-setup/SKILL.md

$BRAIN_PATH/
├── .brain-state           — "idle | captured | error TIMESTAMP"
├── .brain-errors.log      — timestamped event log
├── .brain-session-state.json — loaded files + mtimes (delta detection)
└── brain-mode/
    └── pattern-store.json — patterns[] with encounter_count, last_seen
```

---

## Component Responsibilities

| Component | Current Responsibility | v1.2 Changes |
|-----------|----------------------|--------------|
| `post-tool-use-failure.sh` | Match errors, surface past solutions, increment encounter_count | None — encounter_count already written by `update_encounter_count` |
| `lib/brain-path.sh` | BRAIN_PATH validation, state writes, JSON emit, pattern store ops | Add `vault_relocate` helper function for ONBR-03 |
| `agents/brain-mode.md` | Agent definition, session behavior, available skills | Add `/brain-relocate` to Available Skills list |
| `commands/brain/brain-relocate.md` | (new) | New slash command: vault relocate wizard |
| `brain-mode.md` agent behavior | Idle-aware behavior guidance | Add LIFE-06 idle detection behavior instructions |

---

## v1.2 Feature Analysis — What Each Requires

### MENT-01: Pattern Encounter Tracking

**Status: ALREADY IMPLEMENTED.**

Inspection of `post-tool-use-failure.sh` (lines 43-44) and `lib/brain-path.sh` (lines 178-213) confirms:
- `update_encounter_count` is called on every matched pattern
- It increments `encounter_count` and sets `last_seen` atomically via jq + tmp+mv
- `pattern-store.json` schema already has `encounter_count` and `last_seen` per pattern

**What is NOT implemented:** Reading and acting on encounter_count (MENT-02 progressive responses). MENT-01 the data collection piece is done. MENT-02 the behavior change piece is deferred.

**New components needed:** None.
**Modified components:** None. This is a documentation/verification task.

---

### MENT-02: Progressive Responses Based on Encounter Count

**Status: NOT STARTED. Data is available (MENT-01), behavior change is not wired.**

The encounter_count field exists in pattern-store.json for every matched pattern. To make behavior change:

**Where behavior change belongs:** In `agents/brain-mode.md`. The agent already reads injected context at SessionStart. The pattern store is loaded as part of vault context if it matches the project. The agent needs instructions on how to interpret encounter_count and modify its response style.

**Two approaches:**

1. **Agent-side only (low complexity):** Add instructions to brain-mode.md: "When PostToolUseFailure surfaces a past solution via additionalContext, check if `encounter_count` is present. If count >= 3, respond more directly without preamble ('I've seen this before — [solution]'). If count >= 5, proactively suggest /brain-add-pattern or root cause investigation."

2. **Hook-side enrichment (medium complexity):** Modify `post-tool-use-failure.sh` to include encounter_count in the additionalContext it emits (currently only emits the solution text). Agent then has the count available in context without reading the pattern store file.

**Recommendation:** Approach 2 (hook-side enrichment) because the agent currently only receives the solution string, not the count. Enriching the hook output is a minimal change that unlocks the agent to respond progressively.

**Modified components:**
- `post-tool-use-failure.sh` — include encounter_count in additionalContext JSON
- `agents/brain-mode.md` — add progressive response instructions

---

### ONBR-03: Vault Relocate Command

**Status: NOT STARTED.**

**What it needs to do:**
1. Accept a new vault path from the user
2. Validate the new path exists (or offer to create it)
3. Copy or move vault contents from old BRAIN_PATH to new path
4. Update BRAIN_PATH in `~/.claude/settings.json` (the env block)
5. Advise user to update their shell profile manually (cannot be done programmatically)
6. Verify the relocated vault is accessible

**Architecture fit:** This is a slash command (skill), not a hook. It requires Claude to orchestrate file operations (Read, Write, Bash) and it requires a conversation with the user to confirm the new path.

**Key constraint:** `~/.claude/settings.json` can be read and written by the Bash tool within a Claude session. The vault relocate command uses jq to update `settings.json`'s `env.BRAIN_PATH` field.

**Shell profile limitation:** Claude cannot write to `~/.bashrc` or `~/.zshrc` reliably across platforms. The command should remind the user to update their shell profile manually and provide the exact export line.

**Data flow for vault relocate:**
```
user: /brain-relocate /new/vault/path
    |
    v
brain-relocate.md skill
    |-- read current BRAIN_PATH (from env or prompt user)
    |-- validate new path (exists? if not, offer mkdir -p)
    |-- confirm: "Move vault from X to Y?"
    |-- cp -r "$OLD_PATH" "$NEW_PATH" (or mv with warning)
    |-- update ~/.claude/settings.json env.BRAIN_PATH via jq
    |-- print: "Update your shell profile: export BRAIN_PATH=/new/path"
    |-- write_brain_state "idle" at new path (verify write works)
    |-- confirm success
```

**New components:**
- `commands/brain/brain-relocate.md` — slash command skill
- `onboarding-kit/skills/brain-relocate/SKILL.md` — installer-deployable copy

**Modified components:**
- `onboarding-kit/setup.sh` — deploy brain-relocate command
- `agents/brain-mode.md` — add `/brain-relocate` to Available Skills

---

### LIFE-06: Idle Detection

**Status: NOT STARTED. Explicitly deferred in v1.1 due to intrusiveness concerns.**

**The intrusiveness problem (from project decisions):** Stop hook previously fired on every session including empty scoping sessions. The v1.1 fix was smart threshold detection (HAS_FILE_CHANGES || HAS_GIT_COMMIT). Idle detection that fires proactively on user pauses carries the same intrusiveness risk — must be opt-in or threshold-gated.

**What idle detection could mean:**
- Offer to capture/summarize after N minutes of user inactivity within a session
- Detect context window approaching limit and proactively suggest capture

**Claude Code hook constraint:** There is no `Idle` or `Timeout` hook event in Claude Code. The available hook events are: SessionStart, Stop, PreToolUse, PostToolUse, PostToolUseFailure, PreCompact. None fire based on time elapsed.

**Feasible approaches given hook constraints:**

1. **Agent-side only (viable):** Add instructions to brain-mode.md: "If the user appears to have paused (session has substantial tool use but user asks an open-ended question unrelated to recent work), proactively offer to capture: 'We've done a fair amount of work — want to run /brain-capture before continuing?'" This is behavioral guidance, not a hook.

2. **PostToolUse context-window monitor (viable):** `post-tool-use.sh` already fires on every tool use. It receives `context_window.used_percentage` via stdin JSON. When context usage exceeds a threshold (e.g., 70%), emit an additionalContext advisory suggesting capture. This is not idle detection per se, but addresses the same "don't lose work" concern.

3. **External cron/timer (not viable):** A background process that watches for Claude inactivity would require OS-level process management outside Claude Code's model. Out of scope.

**Recommendation:** Implement approach 1 (agent behavior instructions) for the subjective "user paused" case and approach 2 (context window threshold) for the objective "approaching limit" case. Both are low-risk, additive changes.

**New components:**
- None (approach 1: agent instructions only, approach 2: post-tool-use.sh minor modification)

**Modified components:**
- `agents/brain-mode.md` — idle awareness behavioral instructions
- `hooks/post-tool-use.sh` — optional context window threshold check

---

## Recommended Project Structure (Changes Only)

Changes relative to v1.1 deployed structure at `~/.claude/`:

```
# NEW files
commands/brain/brain-relocate.md        [ONBR-03 slash command]

# MODIFIED files
agents/brain-mode.md                     [LIFE-06 behavior, MENT-02 instructions,
                                          ONBR-03 skill listing]
hooks/post-tool-use-failure.sh           [MENT-02 encounter_count in additionalContext]
hooks/post-tool-use.sh                   [LIFE-06 optional: context window threshold]

# Source repo additions
commands/brain-relocate.md               [source for deployment]
onboarding-kit/skills/brain-relocate/   [installer-deployable skill]
onboarding-kit/setup.sh                  [deploy brain-relocate command]
```

No new lib/ functions are required for MENT-01/MENT-02 or LIFE-06. `vault_relocate` logic belongs in the skill itself (uses Claude's file tools), not in a shell lib function.

---

## Architectural Patterns

### Pattern 1: Agent Instructions as Behavior Layer (LIFE-06, MENT-02)

**What:** For features that require contextual judgment (when has the user paused? how should response tone change?), encode the behavior as instructions in `agents/brain-mode.md` rather than as shell logic.

**Why:** Shell hooks are binary interceptors — they fire on fixed events with fixed logic. Nuanced, contextual behavior ("respond more directly when encounter_count >= 3") belongs in the agent instructions where Claude can reason about context. Hooks provide the data (encounter_count in additionalContext, context window percentage); the agent decides what to do with it.

**Constraint:** Agent instructions only affect brain-mode sessions (claude --agent brain-mode). They have no effect on other sessions or on hook behavior.

### Pattern 2: Hook Enrichment for Downstream Agent Use (MENT-02)

**What:** When a hook has data the agent needs to reason with, include that data in the additionalContext output, not just the human-readable text.

**Current gap:** `post-tool-use-failure.sh` emits `"Past solution found for this error:\n\n$MATCH"` but does not include encounter_count. Agent cannot vary its response without knowing the count.

**Fix:** Emit structured context:
```
Past solution found (seen N times): [solution text]
```
Or as JSON in the hookSpecificOutput additionalContext field. The agent can read either form.

### Pattern 3: Slash Command for User-Driven Vault Management (ONBR-03)

**What:** Operations that involve irreversible or potentially destructive file operations (moving the vault) belong in slash commands (skills), not in hooks. Hooks are automatic and cannot pause for confirmation. Skills run inside the agent session where Claude can ask for confirmation, show diffs, and handle errors gracefully.

**Why this matters for vault relocate:** Moving a vault incorrectly could destroy data. The slash command pattern lets Claude confirm with the user, validate paths, handle partial failures, and provide a recoverable path if something goes wrong.

### Pattern 4: Atomic Write for Pattern Store Updates (Existing — Confirmed)

Already implemented in `update_encounter_count` in `lib/brain-path.sh`. The tmp+mv write pattern prevents corruption when hooks fire in rapid succession. This pattern must be preserved when extending the pattern store schema.

---

## Data Flow (New Flows for v1.2)

### MENT-02: Progressive Response Flow

```
Bash tool fails
    |
    v
post-tool-use-failure.sh fires
    |
    v
match error against pattern-store.json
    |-- if match: get solution AND encounter_count
    |
    v
emit additionalContext with enriched message:
  "Past solution found (seen N times): [solution]"
    |
    v
brain-mode agent receives context in next turn
    |-- if N == 1: standard "I found a past solution: [solution]"
    |-- if N >= 3: more direct "This is the [N]th time — [solution]"
    |-- if N >= 5: add suggestion to investigate root cause
```

### ONBR-03: Vault Relocate Flow

```
user: /brain-relocate
    |
    v
brain-relocate.md skill activates
    |
    v
Claude: "What is the new vault path?"
    |
    v
user provides new path
    |
    v
Claude validates:
  - does new path exist? (Read tool attempt or Bash ls)
  - if not: "Create it?" → mkdir -p
    |
    v
Claude confirms: "Move vault from $OLD to $NEW?"
    |
    v
user confirms
    |
    v
Claude executes:
  cp -r "$BRAIN_PATH" "$NEW_PATH"   (copy, not move — safer)
  jq update ~/.claude/settings.json env.BRAIN_PATH
    |
    v
Claude advises:
  "Add to your shell profile: export BRAIN_PATH=$NEW_PATH"
  "Then run: source ~/.zshrc (or ~/.bashrc)"
    |
    v
Claude verifies:
  write_brain_state "idle" at new path (via Bash call)
  confirm .brain-state exists at new path
```

### LIFE-06: Context Window Threshold Flow (approach 2)

```
Claude executes any tool (PostToolUse fires)
    |
    v
post-tool-use.sh reads stdin JSON
    |
    v
check context_window.used_percentage
    |-- if < 70%: exit 0 (no action, as today)
    |-- if >= 70% AND no prior threshold advisory in session:
        emit additionalContext:
          "Context window at N% — consider /brain-capture if this session
           has capturable work before the window fills."
        write threshold-notified flag to avoid repeat advisories
```

**Flag mechanism for deduplication:** Write a temp file `/tmp/brain-context-warned-$SESSION_ID` on first advisory. Check for it on subsequent calls. Session ID is available in hook input JSON.

---

## Integration Points

### New Integration: brain-relocate.md slash command

| Reads | Writes |
|-------|--------|
| `~/.claude/settings.json` (current BRAIN_PATH) | `~/.claude/settings.json` (updated BRAIN_PATH) |
| `$BRAIN_PATH` directory listing | `$NEW_PATH` (vault copy) |
| | `.brain-state` at new path (verification write) |

### Modified Integration: post-tool-use-failure.sh → brain-mode agent

| Before | After |
|--------|-------|
| Emits: `"Past solution found for this error:\n\n$MATCH"` | Emits: `"Past solution found (seen N times):\n\n$MATCH"` |
| Agent sees: solution text only | Agent sees: solution text + frequency signal |

### Modified Integration: post-tool-use.sh → brain-mode agent (LIFE-06 approach 2)

| Before | After |
|--------|-------|
| Only fires on git commit detection | Also checks context_window.used_percentage |
| Exit 0 for non-commit tools | Emits advisory when >= 70% threshold (once per session) |

---

## Build Order for v1.2 (Dependency-Ordered)

Dependencies flow left to right: items on the right depend on items on the left.

```
MENT-01 verification   (no code change — confirm existing behavior works)
    |
    v
MENT-02 hook enrichment → MENT-02 agent instructions
    (post-tool-use-failure.sh)   (agents/brain-mode.md)

ONBR-03 command → ONBR-03 setup.sh → ONBR-03 agent listing
    (commands/brain-relocate.md)   (setup.sh)   (brain-mode.md)

LIFE-06 agent instructions  [independent — no hook required for approach 1]
    (agents/brain-mode.md)
LIFE-06 hook threshold      [optional enhancement, independent of above]
    (post-tool-use.sh)
```

**Recommended phase order:**

1. **MENT-01 verification** — Zero-code phase. Inspect pattern-store.json after a real error match, confirm encounter_count increments. If it does not, fix update_encounter_count before proceeding. This unblocks MENT-02.

2. **MENT-02** — Hook enrichment (post-tool-use-failure.sh: add count to message) + agent instructions (brain-mode.md: progressive response tiers). Small, contained, testable.

3. **ONBR-03** — New slash command. Most complex (file ops, settings.json surgery, user confirmation flow). Isolated — no other v1.2 feature depends on it. Build last among the code features so MENT-02 is stable first.

4. **LIFE-06** — Agent instructions only (low risk, low effort). Context window threshold check in post-tool-use.sh is optional and can be a separate plan if desired.

---

## What is NOT Needed for v1.2

- **No new hook event types** — all three features fit within existing hook events (PostToolUse, PostToolUseFailure) or are agent-only
- **No new lib/ shell functions** — vault_relocate is agent-orchestrated (uses Claude's file tools), not a shell function
- **No settings.json hook additions** — all existing hooks remain unchanged in registration
- **No new data files** — pattern-store.json schema already supports MENT-01/MENT-02; no new JSON schema needed
- **No statusline changes** — v1.1 statusline states (idle/captured/error) are sufficient for v1.2 features

---

## Sources

- `hooks/post-tool-use-failure.sh` — direct code inspection, confirms encounter_count write is already implemented
- `hooks/lib/brain-path.sh` lines 178-213 — `update_encounter_count` function, confirms atomic write pattern
- `hooks/stop.sh` — direct code inspection, confirms transcript_path + context_window parsing patterns
- `hooks/post-tool-use.sh` — direct code inspection, confirms stdin JSON parsing for context_window threshold approach
- `agents/brain-mode.md` — direct code inspection, confirms agent instruction pattern for behavioral guidance
- `.planning/PROJECT.md` — requirements LIFE-06, ONBR-03, MENT-01, MENT-02 definitions and rationale
- `.planning/STATE.md` — key decisions, especially intrusiveness lessons from v1.1
- `.planning/REQUIREMENTS.md` — explicit deferred status of LIFE-06, ONBR-03, MENT-01, MENT-02
- Claude Code hook events (HIGH confidence from prior research): SessionStart, Stop, PreCompact, PostToolUse, PostToolUseFailure are the complete set — no Idle/Timer event exists

---

*Architecture research for: Claude Brain Mode v1.2 — idle detection, vault relocate, pattern encounter tracking*
*Researched: 2026-03-21*
*Supersedes: prior ARCHITECTURE.md sections on v1.0 build order and component responsibilities*
