# Phase 4: Intelligence Layer - Research

**Researched:** 2026-03-21
**Domain:** Claude Code hooks automation — PostToolUse git commit detection, PostToolUseFailure error pattern recognition, pattern-store JSON, vault capture triggers
**Confidence:** HIGH (core hook mechanisms verified against official docs; pattern store design derived from established project conventions)

---

## Summary

Phase 4 adds two autonomous behaviors on top of the existing hook infrastructure: (1) automatic brain-capture triggered after git commits, and (2) error pattern recognition that surfaces past vault solutions when a matching error recurs. Both behaviors build entirely on the existing hook system — no new infrastructure is needed, only new hook scripts and a pattern store file.

The key technical finding is that **PostToolUse is the correct hook for commit detection, not a dedicated git hook**. The official Claude Code issue tracker confirms that dedicated PreCommit/PostCommit hooks were requested and closed as not-planned (Issue #4834). The workaround is a PostToolUse hook with a `Bash` matcher that inspects `tool_input.command` for `git commit`. The commit fires synchronously through Claude's Bash tool, so the PostToolUse hook receives the full command including flags and message. There is one critical limitation: PostToolUse only fires for **successful** Bash commands (exit 0). A git commit that fails (e.g., pre-commit hook rejection) will not trigger the PostToolUse hook — it will trigger PostToolUseFailure instead. This means successful commits are captured by PostToolUse and failed commit attempts by PostToolUseFailure, each requiring a separate detection path.

For error pattern recognition, the existing `hooks/post-tool-use-failure.sh` already logs every tool failure via `brain_log_error`. Phase 4 extends this to: (1) extract the error message, (2) look up matching patterns in `pattern-store.json`, and (3) if a match exists, inject the past solution via `additionalContext` in the hook's JSON output. The pattern store is a JSON file at `$BRAIN_PATH/brain-mode/pattern-store.json` — already established as the right location in the Phase 1 stack research. Encounter counts increment on each match to enable future adaptive mentoring (v2 requirement), but adaptive mentoring thresholds are deferred — Phase 4 only implements logging counts and surfacing solutions.

**Primary recommendation:** PostToolUse hook with `Bash` matcher detects `git commit` in `tool_input.command` and triggers a brain capture instruction via `decision:block` + `reason`. PostToolUseFailure hook extracts the error, matches against `pattern-store.json`, and injects the matching solution via `additionalContext`. Pattern store is a flat JSON file updated atomically (temp + mv).

---

## Standard Stack

### Core

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| Claude Code `PostToolUse` hook, `Bash` matcher | v2.1.79+ | Detect successful `git commit` calls | Only mechanism to intercept bash tool completions. Matcher `Bash` narrows firing to bash commands only. `tool_input.command` contains the full command string. |
| Claude Code `PostToolUseFailure` hook, `Bash` matcher | v2.1.79+ | Detect bash tool failures and surface error patterns | Fires when a tool exits non-zero. `error` field contains the error message. `tool_input.command` contains the command that failed. Already used in Phase 1 scaffold. |
| `pattern-store.json` (flat JSON at `$BRAIN_PATH/brain-mode/`) | N/A (file convention) | Persist error patterns, solutions, and encounter counts across sessions | Already decided in Phase 1 stack research. Shell scripts can read/write it without extra deps. Atomic write via temp+mv. |
| `jq` 1.6+ | Already hard dep | Parse hook JSON input; read/write pattern store; extract error fields | Hard dependency since Phase 1. All hook scripts use it. |
| `lib/brain-path.sh` + `lib/brain-context.sh` | Existing | BRAIN_PATH validation, error logging, emit_json | Already built. Every new hook sources brain-path.sh as its first action. |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `git log -1 --oneline` | System git | Get the commit hash and message after a successful commit | Run inside the PostToolUse handler to extract commit metadata for the capture entry |
| `mktemp` + `mv` | System | Atomic write pattern for pattern-store.json | Every write to pattern-store.json must use this pattern to prevent corruption from concurrent writes |
| `grep -F` or `jq` pattern matching | System | Match error message fragments against stored pattern keys | Use `jq` for structured JSON matching; `grep -F` for simple substring matching fallback |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| PostToolUse Bash matcher for commit detection | Native git post-commit hook via `.git/hooks/post-commit` | Git hooks only fire for commits made from the terminal directly, not for commits Claude makes via the Bash tool inside a Claude Code session. PostToolUse is the correct interception point for Claude-initiated commits. |
| PostToolUse commit detection | PreToolUse commit detection | PreToolUse can block the commit before it runs. For capture-after-commit, PostToolUse is correct — we want to capture what was committed, not pre-empt it. Use PostToolUse. |
| `decision:block` + `reason` for capture trigger | `additionalContext` in PostToolUse output | `additionalContext` injects text into Claude's context without blocking. `decision:block` forces Claude to act on the reason before proceeding. For auto-capture we want Claude to pause and capture — use `decision:block`. For error pattern surfacing we want to enrich context without interrupting — use `additionalContext`. |
| Flat JSON pattern store | SQLite | SQLite requires the `sqlite3` binary, which hook scripts cannot assume. JSON + jq is already the project convention. At this scale (tens of patterns), JSON is fine. |
| Inline pattern matching in hook script | Separate pattern-classifier script | A separate classifier adds complexity. The PostToolUseFailure hook already has the error message — simple substring/regex matching against stored pattern keys is sufficient in-line for v1. |

**Installation:**

```bash
# No new dependencies — pattern-store.json directory created on first write
mkdir -p "$BRAIN_PATH/brain-mode"
# pattern-store.json initialized by the hook on first run if not present
```

---

## Architecture Patterns

### Recommended File Structure for Phase 4

```
hooks/
├── lib/
│   ├── brain-path.sh          # existing — BRAIN_PATH validation, emit_json
│   └── brain-context.sh       # existing — vault query, session state
├── session-start.sh           # existing — unchanged
├── stop.sh                    # existing — unchanged
├── pre-compact.sh             # existing — unchanged
├── post-tool-use-failure.sh   # EXTEND — add error pattern matching
└── post-tool-use.sh           # NEW — git commit detection + capture trigger

$BRAIN_PATH/
└── brain-mode/
    └── pattern-store.json     # NEW — error patterns, solutions, encounter counts
```

### Pattern 1: PostToolUse Git Commit Detection

**What:** PostToolUse hook fires after every successful Bash tool call. Matcher narrows to `Bash`. Script checks if `tool_input.command` contains `git commit`. If yes, blocks Claude to trigger brain capture.

**When to use:** After any successful git commit made by Claude via the Bash tool.

**Critical limitation:** PostToolUse fires only for exit-0 Bash commands. A failed commit attempt fires PostToolUseFailure instead. Design for this split: PostToolUse handles success, PostToolUseFailure handles failure (which is already used for error detection).

**Example:**

```bash
#!/usr/bin/env bash
# hooks/post-tool-use.sh
# Source: https://code.claude.com/docs/en/hooks (PostToolUse schema)

HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 0  # degrade gracefully — don't interrupt tool use for brain failures
fi

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

# Only act on Bash tool calls that include "git commit"
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

if ! printf '%s' "$COMMAND" | grep -q 'git commit'; then
  exit 0
fi

# Successful git commit detected — trigger brain capture
brain_log_error "PostToolUse" "git commit detected: $COMMAND"

REASON="A git commit just completed. Before continuing, please run /brain-capture to preserve any useful patterns or decisions from this work session. After capturing, briefly summarize what was committed and what was captured."

BLOCK_JSON=$(jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
```

**Settings.json registration:**

```json
"PostToolUse": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "~/.claude/hooks/post-tool-use.sh",
        "timeout": 10
      }
    ]
  }
]
```

Note: No `matcher` field in the outer object — filtering is done in the script, not the matcher. This avoids requiring `Bash` matcher which might conflict with other PostToolUse hooks added later. Alternatively, use `"matcher": "Bash"` in the hook config to narrow firing at the settings level.

### Pattern 2: Error Pattern Matching via PostToolUseFailure

**What:** PostToolUseFailure hook receives `tool_name`, `tool_input`, and `error` fields. Script extracts normalized error message, checks against `pattern-store.json` for a matching pattern, and if found, injects the stored solution via `additionalContext`. Encounter count increments on match.

**When to use:** Any Bash tool failure where the error matches a stored pattern.

**Input schema for PostToolUseFailure:**

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" },
  "error": "Command exited with non-zero status code 1",
  "is_interrupt": false
}
```

**Extended hook implementation:**

```bash
#!/usr/bin/env bash
# hooks/post-tool-use-failure.sh (Phase 4 extension of Phase 1 scaffold)
# Source: https://code.claude.com/docs/en/hooks

HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 1
fi

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
ERROR_MSG=$(printf '%s' "$HOOK_INPUT" | jq -r '.error // "no error message"')
COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

brain_log_error "ToolFailure:$TOOL_NAME" "$ERROR_MSG"

# Phase 4: error pattern matching
PATTERN_STORE="${BRAIN_PATH}/brain-mode/pattern-store.json"
if [ ! -f "$PATTERN_STORE" ]; then
  emit_json '{"status":"ok","logged":true}'
  exit 0
fi

# Find a matching pattern by checking if any stored pattern key is a substring of the error
MATCH=$(jq -r --arg err "$ERROR_MSG" --arg cmd "$COMMAND" '
  .patterns[]
  | select(
      ($err | ascii_downcase | contains(.key | ascii_downcase)) or
      ($cmd | ascii_downcase | contains(.key | ascii_downcase))
    )
  | .solution
  | select(. != null)
' "$PATTERN_STORE" 2>/dev/null | head -1)

if [ -n "$MATCH" ]; then
  # Increment encounter count atomically
  update_encounter_count "$PATTERN_STORE" "$ERROR_MSG"

  CONTEXT="Past solution found for this error:\n\n${MATCH}"
  OUTPUT=$(jq -n \
    --arg ctx "$CONTEXT" \
    '{"hookSpecificOutput":{"hookEventName":"PostToolUseFailure","additionalContext":$ctx}}')
  emit_json "$OUTPUT"
else
  emit_json '{"status":"ok","logged":true,"tool":"'"$TOOL_NAME"'"}'
fi
exit 0
```

### Pattern 3: pattern-store.json Schema

**What:** Flat JSON file storing error patterns with keys (substring match tokens), solutions (markdown text), and encounter counts. Lives at `$BRAIN_PATH/brain-mode/pattern-store.json`.

**Schema:**

```json
{
  "version": "1",
  "updated": "2026-03-21T00:00:00Z",
  "patterns": [
    {
      "id": "jq-invalid-json",
      "key": "invalid JSON",
      "solution": "Check for shell profile output corrupting JSON. Add `[[ $- == *i* ]]` guards to ~/.zshrc.",
      "source_file": "prompts/coding/jq-invalid-json.md",
      "encounter_count": 3,
      "first_seen": "2026-03-20T10:00:00Z",
      "last_seen": "2026-03-21T09:00:00Z"
    }
  ]
}
```

**Key design decisions:**
- `key` is a substring used for matching (not regex) — simple and safe for shell grep
- `solution` is inline markdown text — no vault file read required at match time (fast)
- `source_file` is optional vault reference for the full entry (for future deep-link)
- `encounter_count` increments on every match — enables v2 adaptive mentoring
- Atomic write via `mktemp` + `mv` on every update

### Pattern 4: Atomic Pattern Store Update

**What:** Update pattern-store.json without corruption risk. Uses temp file + atomic mv.

```bash
update_encounter_count() {
  local store="$1"
  local error_msg="$2"
  local tmp
  tmp=$(mktemp)

  jq --arg err "$error_msg" --arg now "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '
    .updated = $now |
    .patterns = [
      .patterns[] |
      if ($err | ascii_downcase | contains(.key | ascii_downcase)) then
        .encounter_count += 1 |
        .last_seen = $now
      else . end
    ]
  ' "$store" > "$tmp" && mv "$tmp" "$store"
}
```

### Anti-Patterns to Avoid

- **Matching against raw error messages without normalization:** Error messages include paths, line numbers, and session-specific text. Match on normalized substrings (e.g., "invalid JSON") not full error text. Store minimal keys.
- **Blocking on PostToolUseFailure:** PostToolUseFailure cannot block actions (the tool already failed). It can only inject `additionalContext`. Never return `decision:block` from this hook — it has no effect and wastes the hook call.
- **Using PostToolUse for error pattern capture:** PostToolUse only fires on exit 0. Failed commands route through PostToolUseFailure. Design for this explicitly.
- **Firing PostToolUse commit detection on every Bash call:** Without filtering, the hook fires on every `git status`, `ls`, `npm test`, etc. Check for `git commit` in `tool_input.command` explicitly before doing any expensive work.
- **Writing pattern-store.json synchronously in a blocking hook:** If the write fails (disk full, permission error), the hook must still exit 0 gracefully. Wrap writes in error-guarded subshells.
- **Skipping the loop guard on PostToolUse:** PostToolUse with `decision:block` does NOT have a `stop_hook_active` equivalent for loop prevention. However, `decision:block` in PostToolUse prompts Claude to act and then continue — it does not re-fire PostToolUse. The capture instruction fires once. This is safe without a loop guard.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Git commit message parsing | Custom commit parser | `git log -1 --oneline` or `jq -r '.tool_input.command'` | The command is already in `tool_input.command`. After a successful commit, `git log -1 --oneline` gives hash + message. No custom parser needed. |
| Error message normalization | Custom NLP/tokenizer | Substring matching with `ascii_downcase` in jq | v1 needs to match known patterns, not classify unknowns. Simple substring matching on lowercase is sufficient and has zero deps. |
| Pattern similarity scoring | Edit distance / embedding search | Exact substring match on stored keys | Stored keys are written by the user/Claude and are chosen to be distinctive. Exact match is correct for v1. |
| Concurrent write safety | File locking (`flock`) | Atomic temp+mv | Hooks fire sequentially per event in Claude Code. True concurrency (two hooks writing simultaneously) does not occur in this architecture. Temp+mv is sufficient and always available. |
| Branch/PR detection for merge events | Custom git log parsing | Not in scope — see Open Questions | PR merges are not detectable via the current hook system without post-merge bash commands. See section below. |

**Key insight:** The entire phase is buildable with bash, jq, and the existing hook infrastructure. No new dependencies are required.

---

## Common Pitfalls

### Pitfall 1: PostToolUse Does Not Fire for Failed Commits

**What goes wrong:** A pre-commit hook (e.g., linting) rejects the commit. The Bash tool exits non-zero. PostToolUse never fires. The auto-capture trigger silently doesn't happen.

**Why it happens:** PostToolUse only fires for exit-0 tool completions. This is documented and intentional. Failed git commits exit non-zero.

**How to avoid:** Accept this behavior. PostToolUse handles successful commits. PostToolUseFailure handles failed commit attempts (and can note "commit failed, no capture triggered"). Do not attempt to work around the exit-code split.

**Warning signs:** Testing commit detection only against successful commits misses the failure case.

---

### Pitfall 2: PostToolUse Commit Detection Fires on `git commit` Contained in Other Commands

**What goes wrong:** A command like `echo "git commit message"` or `git commit --dry-run` triggers the capture instruction unnecessarily.

**Why it happens:** Naive `grep 'git commit'` matches any command containing those words, including dry runs, echo statements, and comments.

**How to avoid:** Filter more precisely. Check that the command starts with `git commit` or contains `git commit` as a distinct token (not as part of a string argument). At minimum, exclude `--dry-run`:

```bash
if printf '%s' "$COMMAND" | grep -q 'git commit' && \
   ! printf '%s' "$COMMAND" | grep -q -- '--dry-run'; then
```

**Warning signs:** Capture instruction fires during documentation searches or test runs.

---

### Pitfall 3: additionalContext in PostToolUseFailure Has Known Rendering Issues

**What goes wrong:** The PostToolUseFailure hook outputs `additionalContext` with a past solution, but Claude does not appear to act on it or the context is not visible.

**Why it happens:** GitHub issue #27886 documents that PostToolUseFailure hooks show "hook error" even with exit 0. Issue #24788 shows `additionalContext` not surfacing for MCP tool calls. These are known bugs in certain versions. For Bash tool failures (non-MCP), `additionalContext` works correctly.

**How to avoid:** Verify `additionalContext` surfacing during Phase 4 testing with a known error + known pattern. Use `claude --debug` to confirm the hook output reaches Claude. If it does not surface, fallback to `decision:block` with `reason` containing the solution text (trades invisibility for guaranteed delivery).

**Warning signs:** Pattern matches are logged in `.brain-errors.log` but Claude doesn't mention the past solution when an error occurs.

---

### Pitfall 4: Pattern Store Missing or Empty on First Run

**What goes wrong:** PostToolUseFailure hook tries to read `pattern-store.json` but the file doesn't exist. Hook crashes or emits invalid JSON.

**Why it happens:** The pattern store is created lazily (on first pattern add). New installs have no file.

**How to avoid:** Guard every read with a file existence check. If the file doesn't exist, skip matching and exit cleanly:

```bash
if [ ! -f "$PATTERN_STORE" ]; then
  emit_json '{"status":"ok","logged":true}'
  exit 0
fi
```

Initialize the file on first write with a valid empty schema: `{"version":"1","patterns":[]}`.

**Warning signs:** PostToolUseFailure hook crashes on fresh install before any patterns are added.

---

### Pitfall 5: Commit Detection Triggers Capture for Every `git commit --amend`

**What goes wrong:** `git commit --amend` (amending a previous commit without changes) triggers the capture instruction. This is a low-value trigger that interrupts workflow for a maintenance operation.

**Why it happens:** `--amend` contains `git commit` as a substring.

**How to avoid:** Optionally filter out `--amend` commits from the capture trigger, or accept that amends are valid capture moments. Decision: for v1, trigger on all `git commit` calls including `--amend`. Users can adjust.

---

### Pitfall 6: Encounter Count Does Not Increment Correctly

**What goes wrong:** Pattern counts stay at 1 no matter how many times the error recurs. Pattern store updates appear to write but the count stays the same.

**Why it happens:** The `jq` update expression was wrong, or the temp file write succeeded but the `mv` failed silently, or the key matching is case-sensitive when the error message changed slightly.

**How to avoid:** Use `ascii_downcase` on both sides of the comparison in jq. Verify atomic write with an explicit check:

```bash
jq ... "$store" > "$tmp" && mv "$tmp" "$store" || brain_log_error "PatternStore" "atomic write failed"
```

After each update, verify with `jq '.patterns[] | .encounter_count' pattern-store.json`.

---

## Code Examples

### PostToolUse input for Bash git commit

```bash
# Source: https://code.claude.com/docs/en/hooks (PostToolUse schema)
# When Claude runs: git commit -m "feat: add error detection"
# The hook receives on stdin:
{
  "session_id": "abc123",
  "hook_event_name": "PostToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "git commit -m \"feat: add error detection\"",
    "description": "Commit the changes"
  },
  "tool_response": {
    "stdout": "[main abc1234] feat: add error detection\n 2 files changed",
    "exit_code": 0
  },
  "cwd": "/Users/.../"
}
```

### PostToolUseFailure input

```bash
# Source: https://code.claude.com/docs/en/hooks (PostToolUseFailure schema)
# When a Bash command fails (exits non-zero):
{
  "hook_event_name": "PostToolUseFailure",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  },
  "error": "Command exited with non-zero status code 1",
  "is_interrupt": false
}
```

### PostToolUseFailure additionalContext output

```bash
# Source: https://code.claude.com/docs/en/hooks (PostToolUseFailure output schema)
# Inject past solution into Claude's context:
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": "Past solution found for this error:\n\nCheck for shell profile output corrupting JSON..."
  }
}
```

### jq pattern-store.json pattern match

```bash
# Match stored patterns against error message (case-insensitive substring)
# Source: jq documentation (ascii_downcase, contains)
MATCH=$(jq -r --arg err "$ERROR_MSG" '
  .patterns[]
  | select(($err | ascii_downcase) | contains(.key | ascii_downcase))
  | .solution
  | select(. != null)
' "$PATTERN_STORE" 2>/dev/null | head -1)
```

### Initialize pattern-store.json on first write

```bash
# Source: project convention (atomic write pattern from lib/brain-context.sh write_session_state)
init_pattern_store() {
  local store="$1"
  local dir
  dir=$(dirname "$store")
  mkdir -p "$dir"

  if [ ! -f "$store" ]; then
    local tmp
    tmp=$(mktemp)
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq -n --arg now "$now" '{
      "version": "1",
      "created": $now,
      "updated": $now,
      "patterns": []
    }' > "$tmp" && mv "$tmp" "$store"
  fi
}
```

---

## State of the Art

| Old Approach | Current Approach | Notes | Impact |
|--------------|------------------|-------|--------|
| Dedicated PreCommit/PostCommit hooks | PostToolUse Bash matcher | Issue #4834 closed not-planned | Detection requires checking `tool_input.command` for `git commit` substring |
| PostToolUse fires on all Bash completions | PostToolUse only fires on exit-0 | By design | Failed commits route to PostToolUseFailure |
| additionalContext unknown behavior | additionalContext confirmed for PostToolUseFailure (Bash tool) | Issues #27886, #24788 scope known bugs to MCP tools | Bash tool failure context injection is reliable |

**Deprecated/outdated:**
- `PostToolFailure` (non-standard naming): The official hook is `PostToolUseFailure`. Earlier community posts used different names — the official schema uses `PostToolUseFailure`.

---

## Open Questions

1. **PR merge detection**
   - What we know: There is no PostCommit or PostMerge hook in Claude Code. PR merges happen via `gh pr merge` or web UI — neither is guaranteed to go through Claude's Bash tool.
   - What's unclear: Can we reliably detect `gh pr merge` in PostToolUse? Only if Claude makes the merge call via Bash. If the user merges from GitHub web, no hook fires.
   - Recommendation: Scope Phase 4 to git commits only (detectable). Add PR merge detection as a note in the PLAN with a caveat: "fires only for merges Claude executes via Bash, not web-initiated merges." The success criterion says "PR merge" but the blocker analysis already called this out — limit to what's technically achievable.

2. **Pattern population strategy — who adds patterns to pattern-store.json?**
   - What we know: The pattern store starts empty. Patterns need to be added before error matching can surface solutions.
   - What's unclear: Should Phase 4 include a skill command (e.g., `/brain-add-pattern`) for the user to manually add patterns? Or should patterns be added automatically when a solution is confirmed during a PostToolUseFailure session?
   - Recommendation: Phase 4 provides the store structure and the matching hook. Adding patterns is done by Claude (instructed via the brain-mode agent) when the user confirms "yes, that fixed it." A simple `/brain-add-pattern` skill is a thin wrapper — Claude reads the error, solution, and writes to pattern-store.json. This can be a single task in the plan.

3. **PostToolUse `decision:block` for capture — will Claude always comply?**
   - What we know: `decision:block` feeds the reason text to Claude as an instruction. Claude is expected to follow it. The existing Stop hook uses this pattern successfully.
   - What's unclear: PostToolUse `decision:block` is slightly different from Stop hook `decision:block`. Stop hook has dedicated `stop_hook_active` for loop prevention. PostToolUse block re-prompts Claude but does not re-fire PostToolUse after the capture action.
   - Recommendation: Use `decision:block` with a clear instruction (as shown in Pattern 1 above). Verify in testing that Claude follows the instruction and that PostToolUse does not loop. If looping occurs, fall back to `additionalContext` (advisory, not blocking).

4. **Async vs synchronous PostToolUse hook**
   - What we know: The existing PostToolUseFailure hook uses `async: true`. PostToolUse for commit capture uses `decision:block` which requires a synchronous response.
   - What's unclear: Can `decision:block` work with `async: true`? Likely not — async hooks do not block the tool pipeline.
   - Recommendation: PostToolUse commit detection hook must NOT use `async: true`. Keep it synchronous (no `async` field, defaults to synchronous).

---

## Sources

### Primary (HIGH confidence)

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — PostToolUse schema, PostToolUseFailure schema, `tool_input.command` field, `additionalContext` output, `decision:block` behavior
- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide) — Bash matcher pattern `"Edit|Write"`, full event table, PostToolUse Bash tool example with `tool_input.command` extraction
- `.planning/research/STACK.md` (project) — `pattern-store.json` location and schema decisions from Phase 1 research, atomic write pattern, Windows compatibility notes
- `.planning/research/PITFALLS.md` (project) — notification fatigue pitfall, pattern tracker history rotation warning, atomic write pattern

### Secondary (MEDIUM confidence)

- [GitHub Issue #4834 — Feature Request: PreCommit/PostCommit hooks](https://github.com/anthropics/claude-code/issues/4834) — Closed not-planned. Confirms no native PreCommit/PostCommit hooks. PostToolUse Bash matcher is the only workaround.
- [GitHub Issue #6371 — PostToolUse hooks don't execute for failed Bash commands](https://github.com/anthropics/claude-code/issues/6371) — Confirms PostToolUse only fires for exit-0. PostToolUseFailure is the correct hook for failed commands.
- [deepwiki.com trailofbits/claude-code-config PostToolUse examples](https://deepwiki.com/trailofbits/claude-code-config/4.3-posttooluse-hook-examples) — Real-world PostToolUse patterns showing `tool_input.command` extraction and JSON logging

### Tertiary (LOW confidence — flagged for validation)

- [GitHub Issue #27886 — PostToolUseFailure hook always shows 'hook error' even with exit 0](https://github.com/anthropics/claude-code/issues/27886) — Documents rendering issue with PostToolUseFailure hooks. Status unclear — may be fixed in current version. Test `additionalContext` surfacing in Phase 4 verification.
- [GitHub Issue #24788 — PostToolUse hooks with additionalContext not surfacing for MCP tool calls](https://github.com/anthropics/claude-code/issues/24788) — Scopes the `additionalContext` issue to MCP tools specifically. Bash tool should be unaffected. Verify during testing.

---

## Metadata

**Confidence breakdown:**

- Standard stack: HIGH — PostToolUse/PostToolUseFailure schemas verified against official docs; jq, brain-path.sh, pattern-store conventions established in prior phases
- Architecture patterns: HIGH — PostToolUse git commit detection pattern confirmed via official docs + community examples; pattern store schema derived from established project conventions
- Pitfalls: HIGH — exit-code behavior (PostToolUse only on exit-0) confirmed via official docs and GitHub issue #6371; additionalContext rendering issue documented in GitHub issues with known scope
- Open questions: MEDIUM — PR merge detection limitation is a known gap; pattern population strategy is a design decision not yet made

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (30 days — Claude Code hook API is stable but fast-moving; re-verify if Claude Code version advances significantly)
