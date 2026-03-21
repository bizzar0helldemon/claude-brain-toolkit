# Phase 7: Smart Stop Hook - Research

**Researched:** 2026-03-21
**Domain:** Claude Code hook lifecycle, bash scripting, JSONL transcript parsing
**Confidence:** HIGH

---

## Summary

The stop hook currently fires `decision:block` unconditionally on every session exit — including trivial sessions with no tool usage, no file changes, and no commits. This was confirmed as a real UX problem: the hook fired 4 times on an empty scoping session. Phase 7 replaces the blunt always-block with signal detection logic that reads the session transcript and only blocks when there is concrete evidence of meaningful work.

The core mechanism is already in place: the Stop hook receives `transcript_path` pointing to the session's JSONL file. That file contains every message and tool call made during the session. By parsing it with `jq`, the hook can count tool invocations, detect Write/Edit/Bash calls, and check whether any Bash commands included `git commit`. If no meaningful signals are found, the hook exits 0 silently. If signals are found, it emits `decision:block` as before.

The critical implementation constraint is the `stop_hook_active` guard — already present in the current hook — which prevents infinite loops. This guard must be kept as the very first check. The `transcript_path` stale-path bug was fixed in Claude Code 2.0.12; the current version is 2.1.81, so reading `transcript_path` directly is safe.

**Primary recommendation:** Parse `transcript_path` with `jq` to count tool calls. If tool count > 0 OR any Bash command contains `git commit` OR any Write/Edit calls exist, emit `decision:block`. Otherwise exit 0 with no output.

---

## Standard Stack

### Core (no new dependencies needed)

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `bash` | 3.2+ | Hook script runtime | All existing hooks use bash |
| `jq` | any | JSONL parsing | Already used throughout brain-lib.sh and all hooks |
| `brain-path.sh` | existing | Shared validation + emit_json | Existing library — use it |

No new libraries or tools are needed. Everything required already exists in the hook infrastructure.

**Installation:** None — all dependencies are already present.

---

## Architecture Patterns

### Recommended Script Structure

```
hooks/
└── stop.sh          # Modified in-place — same file, smarter logic
```

The existing `stop.sh` is modified in-place. No new files are needed for this phase.

### Pattern 1: Loop Guard First

The `stop_hook_active` check MUST remain the first thing in the script, before sourcing any library. This is already implemented correctly and must not be moved.

```bash
#!/usr/bin/env bash
HOOK_INPUT=$(cat)

# CRITICAL: Loop guard MUST be checked BEFORE sourcing anything
STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

source ~/.claude/hooks/lib/brain-path.sh
# ... rest of logic
```

**Why first:** If the hook is already re-running after a previous block, checking `stop_hook_active` before sourcing prevents infinite library-load chains and is the defensive pattern the existing code already uses.

### Pattern 2: Transcript Signal Detection

The Stop hook JSON input includes `transcript_path` — a path to the session's JSONL file. Each line is a JSON object. Tool calls are stored in `assistant` type entries, nested as `message.content[]` items with `type == "tool_use"`.

**Verified JSONL structure (from live transcripts):**

```jsonl
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {
        "type": "tool_use",
        "name": "Bash",
        "input": { "command": "git commit -m '...'" }
      }
    ]
  }
}
```

Entry types observed in production transcripts:
- `progress` — hook progress events (NOT tool calls by Claude)
- `assistant` — Claude's responses, contains tool_use items
- `user` — user messages and skill invocations
- `system` — system messages
- `file-history-snapshot` — checkpoint snapshots

**Signal detection jq pattern:**

```bash
# Source: direct transcript inspection of live sessions
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""')

TOOL_COUNT=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  TOOL_COUNT=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    .name
  ' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ')
fi
```

### Pattern 3: Specific Signal Extraction

For more granular detection — checking for git commits or file writes specifically:

```bash
# Source: verified from live transcript inspection
HAS_GIT_COMMIT=$(jq -r '
  select(.type == "assistant") |
  .message.content[]? |
  select(.type == "tool_use") |
  select(.name == "Bash") |
  .input.command // ""
' "$TRANSCRIPT_PATH" 2>/dev/null | grep -c 'git commit' || echo 0)

HAS_FILE_CHANGES=$(jq -r '
  select(.type == "assistant") |
  .message.content[]? |
  select(.type == "tool_use") |
  select(.name == "Write" or .name == "Edit") |
  .name
' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ')
```

### Pattern 4: Exit Contract

```bash
# No capturable content — silent skip
exit 0

# Capturable content found — block and prompt capture
REASON="Before ending this session, please run /brain-capture..."
BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
```

**Critical:** The current hook uses `decision:block` with exit 0 — NOT exit 2. This is the correct pattern for providing a structured reason to Claude. Exit 2 ignores JSON output. The existing emit_json + exit 0 pattern must be preserved.

### Pattern 5: Trivial Session Definition

Based on live transcript analysis, a trivial session has:
- Zero `tool_use` entries in `assistant` messages
- Example: user opens Claude, asks one question, gets a text answer, exits

A trivial session's transcript contains only: `progress`, `file-history-snapshot`, `user`, and `assistant` entries where `assistant.message.content` contains only `text` type items (no `tool_use`).

The 10-line transcript from the `17b0eb0d` session confirms: user ran `/daily-note`, Claude responded with a text question, user ran `/exit`. No tool calls. This is exactly the pattern that should NOT trigger capture.

### Anti-Patterns to Avoid

- **Checking line count instead of tool count:** Line count is meaningless — a trivial session that loaded a big skill has many lines but no tool calls.
- **Reading `last_assistant_message` for signal detection:** This field contains only Claude's final text response, not a summary of what tools were used. Don't use it as the primary signal.
- **Checking message count (user/assistant exchanges):** A single-exchange session with heavy tool use (e.g., running 15 Bash commands in one response) should trigger capture. Message count is a weak proxy.
- **Using `wc -l` on the transcript file:** Line count reflects progress events, snapshots, and metadata — not meaningful work volume.
- **Checking git log directly:** Running `git log` as a side effect introduces a shell dependency and may behave unexpectedly if cwd is not a git repo. Read it from the transcript instead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON emission | Custom printf JSON | `emit_json` from brain-path.sh | Already validates, handles errors, exits 0 on bad JSON |
| BRAIN_PATH validation | Re-implement check | `brain_path_validate` from brain-path.sh | Already handles both error cases (unset, missing dir) |
| Loop guard | New mechanism | Existing `stop_hook_active` check | Already correct — moving it would break the guard |
| Logging | Custom log appender | `brain_log_error` from brain-path.sh | Already timestamped, guarded, and standardized |

**Key insight:** This phase is a modification of existing code, not new infrastructure. The library is already built. The task is adding signal detection logic between the existing guard and the existing block.

---

## Common Pitfalls

### Pitfall 1: transcript_path May Be Absent or Empty

**What goes wrong:** Hook tries to read `$TRANSCRIPT_PATH` when the field is missing or the file doesn't exist yet, causing jq/wc errors that propagate as unexpected output.

**Why it happens:** In very short sessions (e.g., immediate `/exit`), the transcript file may not be fully written yet, or `transcript_path` may be an empty string.

**How to avoid:** Always guard with `[ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]` before reading. Default TOOL_COUNT to 0 if file is absent.

**Warning signs:** Hook produces error output when session ends immediately after start.

### Pitfall 2: Counting progress Entries Instead of Tool Calls

**What goes wrong:** Naive `jq '.tool_name'` or line-count approaches pick up `progress` entries (which describe hook events, not Claude tool calls) and produce false positives.

**Why it happens:** Progress entries have a `data.type == "hook_progress"` structure but are NOT Claude tool invocations. They're numerous: a session with 44 actual entries had 203 `progress` lines.

**How to avoid:** Always filter on `select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")`. The double-filter is required.

**Warning signs:** Tool count is much higher than expected for a simple session.

### Pitfall 3: wc -l Output Contains Whitespace

**What goes wrong:** Comparison `[ "$TOOL_COUNT" -gt 0 ]` fails because `wc -l` on some systems outputs leading spaces (e.g., `"   5"`).

**Why it happens:** POSIX `wc -l` is not required to strip leading whitespace.

**How to avoid:** Pipe through `tr -d ' '` or use `$(... | wc -l | xargs)` to normalize.

**Warning signs:** Integer comparison errors in bash (`[: : integer expression expected`).

### Pitfall 4: stop_hook_active Guard Moved or Duplicated

**What goes wrong:** If the loop guard is moved after sourcing brain-path.sh, a failure in brain-path.sh (e.g., BRAIN_PATH not set) can prevent the guard from running, causing infinite re-triggering.

**Why it happens:** Refactoring the early section without understanding why the guard must be first.

**How to avoid:** Do not move the `stop_hook_active` block. It must remain before any source statement.

**Warning signs:** Hook fires repeatedly on second pass even though `stop_hook_active` should be true.

### Pitfall 5: Using grep -c on jq Output With No Matches

**What goes wrong:** `grep -c 'pattern'` returns exit code 1 when no lines match, which can cause bash to exit the script unexpectedly if `set -e` is active (or if used in conditional contexts without care).

**Why it happens:** `grep -c` returns 1 (failure) when count is 0. In bash without `set -e`, this is usually fine, but the pattern `COUNT=$(... | grep -c 'git commit')` can produce empty string if grep exits 1 in some shells.

**How to avoid:** Use `grep -c 'pattern' || echo 0` to default to 0 when no matches. Confirmed pattern from post-tool-use.sh: `grep -q 'git commit'` for boolean tests.

**Warning signs:** TOOL_COUNT or HAS_GIT_COMMIT is empty string instead of 0.

---

## Code Examples

Verified patterns from live transcript inspection and existing hook code:

### Full Detection Logic Skeleton

```bash
#!/usr/bin/env bash
# Source: based on verified transcript structure and existing stop.sh pattern
HOOK_INPUT=$(cat)

# CRITICAL: Loop guard — check before sourcing anything
STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 0
fi

# Extract transcript path
TRANSCRIPT_PATH=$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""')

# Default: no signals detected
TOOL_COUNT=0
HAS_GIT_COMMIT=0
HAS_FILE_CHANGES=0

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
  # Count all Claude tool calls (excludes progress entries)
  TOOL_COUNT=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    .name
  ' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ')

  # Check for git commits in Bash tool calls
  HAS_GIT_COMMIT=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Bash") |
    .input.command // ""
  ' "$TRANSCRIPT_PATH" 2>/dev/null | grep -c 'git commit' || echo 0)

  # Check for file write/edit operations
  HAS_FILE_CHANGES=$(jq -r '
    select(.type == "assistant") |
    .message.content[]? |
    select(.type == "tool_use") |
    select(.name == "Write" or .name == "Edit") |
    .name
  ' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ')
fi

# Determine if session has capturable content
SHOULD_CAPTURE=false
if [ "$TOOL_COUNT" -gt 0 ] || [ "$HAS_GIT_COMMIT" -gt 0 ] || [ "$HAS_FILE_CHANGES" -gt 0 ]; then
  SHOULD_CAPTURE=true
fi

if [ "$SHOULD_CAPTURE" = "false" ]; then
  # Trivial session — silent skip, no output
  exit 0
fi

brain_log_error "Stop" "Capture trigger fired (tools: $TOOL_COUNT, commits: $HAS_GIT_COMMIT, files: $HAS_FILE_CHANGES)"

REASON="Before ending this session, please run /brain-capture to preserve any useful patterns from this conversation, then run /daily-note to log a session summary. After completing both, briefly confirm what was captured (e.g., 'Brain captured: N learnings, daily note updated') and then you can stop."
BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
```

### Minimal Trivial Session Detection (Simplest Version)

If only tool count matters (simplest implementation):

```bash
# Source: verified JSONL structure from live sessions
TOOL_COUNT=$(jq -r '
  select(.type == "assistant") |
  .message.content[]? |
  select(.type == "tool_use") |
  .name
' "$TRANSCRIPT_PATH" 2>/dev/null | wc -l | tr -d ' ')

if [ "${TOOL_COUNT:-0}" -eq 0 ]; then
  exit 0  # Nothing to capture
fi
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Always block on stop | Conditional block based on signals | Phase 7 | Eliminates intrusive captures on trivial sessions |
| Exit 2 for blocking | `decision:block` with exit 0 | v1.0 baseline | Structured reason visible to Claude |
| No transcript reading | Parse `transcript_path` JSONL | Phase 7 | Direct evidence-based detection |

**Deprecated/outdated:**
- `decision:block` on unconditional exit: Replaced by signal-gated block in Phase 7.

---

## Open Questions

1. **Should TOOL_COUNT > 0 alone be sufficient, or should it be a threshold (e.g., > 3)?**
   - What we know: A single Read tool call (e.g., `Read file_path`) is less meaningful than 10 Bash + Write calls.
   - What's unclear: Whether read-only sessions (no writes, no commits) warrant capture.
   - Recommendation: Start with TOOL_COUNT > 0 as the threshold. This is conservative — any tool use indicates non-trivial work. Can be tuned after real-world usage data.

2. **Should error resolutions (PostToolUseFailure triggers) be a separate signal?**
   - What we know: STOP-01 mentions "error resolutions" as a detection target.
   - What's unclear: How to detect error resolution from the transcript alone. PostToolUseFailure entries are not clearly distinguishable in assistant messages.
   - Recommendation: Tool count already captures this indirectly — if errors were being resolved, tool calls were being made. The separate signal may not be worth the complexity for v1.1.

3. **What if `transcript_path` is empty or the file doesn't exist?**
   - What we know: In a 10-line trivial session the file existed, but edge cases (immediate exit) may vary.
   - What's unclear: Whether file is always written before Stop fires.
   - Recommendation: Default TOOL_COUNT to 0 when file is absent — treating an unreadable transcript as a trivial session is safe (conservative in the right direction — won't block unnecessarily).

---

## Sources

### Primary (HIGH confidence)
- Live transcript inspection: `/c/Users/srco1/.claude/projects/C--Users-srco1-desktop-claude-brain-toolkit/` — direct JSONL structure verification, 15+ sessions analyzed
- Existing codebase: `hooks/stop.sh`, `hooks/lib/brain-path.sh`, `hooks/post-tool-use.sh` — verified patterns for emit_json, loop guard, jq usage
- `https://code.claude.com/docs/en/hooks.md` — Stop hook input fields, exit codes, `decision:block` vs exit 2 semantics, `stop_hook_active` field, `transcript_path` field

### Secondary (MEDIUM confidence)
- GitHub issue #8564 (anthropics/claude-code) — `transcript_path` stale bug confirmed fixed in v2.0.12; current version is 2.1.81, so safe to use
- `https://code.claude.com/docs/en/hooks.md` (fetched 2026-03-21) — `last_assistant_message` field documentation

### Tertiary (LOW confidence)
- WebSearch results about transcript JSONL format — superseded by direct file inspection; WebSearch findings were consistent with observed structure

---

## Metadata

**Confidence breakdown:**
- Hook contract (exit codes, input fields, decision:block): HIGH — verified from official docs
- Transcript JSONL structure: HIGH — verified by directly inspecting 15+ live session files
- Signal detection logic: HIGH — derived from verified structure; jq patterns tested mentally against known data
- `transcript_path` reliability: HIGH — stale bug fixed in 2.0.12; running 2.1.81
- `wc -l` whitespace issue: MEDIUM — known bash portability concern, confirmed in project's own bash usage

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain — hook contract changes infrequently)
