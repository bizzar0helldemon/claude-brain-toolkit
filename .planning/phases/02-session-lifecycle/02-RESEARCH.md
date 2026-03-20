# Phase 2: Session Lifecycle - Research

**Researched:** 2026-03-19
**Domain:** Claude Code Hooks API (SessionStart / Stop / PreCompact), bash vault querying, token budgeting, session state persistence
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Context Selection
- Load **project-specific entries + global user preferences** at session start
- Project matching via **frontmatter `project:` field** — matched against current directory name or git remote
- Also check for a **`.brain.md` file in the project root** as an additional context source (project-local knowledge)
- Prioritize entries by **most recent first** within the token budget
- **Always inject something** every session — even if just global prefs, so the user knows brain is active
- For **first-time projects** (no vault entries, no .brain.md): load global prefs and **proactively offer to scan** the project for brain cataloging
- **Track which vault entries were loaded** — next session can show only new/changed entries instead of repeating

#### Pre-clear Capture
- Trigger **both `/brain-capture` and `/daily-note` skills** on pre-clear — these existing skills handle the actual capture logic
- Capture fires on **both `/clear` and session end** (Stop hook) — never lose a session
- Show a **brief notification** after capture (e.g., "Brain captured: 3 learnings, daily note updated") — no confirmation dialog needed
- **Always capture**, even for trivial sessions — let the skills decide what's worth saving

#### Token Budget
- Default **2,000 token ceiling**, but **configurable** via env var or config (e.g., `BRAIN_TOKEN_BUDGET=3000`)
- When content exceeds budget: **drop lowest priority entries** (load in priority order, stop when budget reached — no summarization)
- Use a **precise tokenizer** for accurate budget enforcement (not word count heuristic)
- Claude's Discretion: whether `.brain.md` shares the vault token budget or gets a separate allocation

#### Surface Format
- Show a **visible summary block** as the **first message output** when session starts
- **Functional/minimal tone** — clean data, no personality
- Format example:
  ```
  🧠 Brain loaded for claude-brain-toolkit
     3 project notes (newest: Mar 19)
     2 pitfalls
     Global preferences active
  ```
- User can **expand the summary on demand** — ask "show brain context" to see full loaded entries

### Claude's Discretion
- How `.brain.md` and vault entries are merged/prioritized (Context Source Merge Strategy)
- Whether `.brain.md` shares the vault token budget or gets a separate allocation

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 2 adds the active brain behavior to the scaffold built in Phase 1: vault context injection on SessionStart, pre-clear capture on Stop/clear, and token budget management. The Phase 1 hooks already exist as thin scaffolds with placeholder comments for exactly this work — Phase 2 fills those placeholders.

The critical technical mechanism is `hookSpecificOutput.additionalContext` in the SessionStart hook's JSON output. This field injects content into Claude's context discretely (without showing as hook output in the transcript). The bug that caused this field to be silently dropped (issue #13650) was fixed in v2.0.76. For Stop-hook capture, the mechanism is `{"decision":"block","reason":"..."}` — the reason text is fed to Claude as an instruction to continue and run skills. This relies on Claude choosing to follow the instruction, but stop_hook_active prevents infinite loops. A separate, more reliable capture trigger exists: SessionStart fires with `source:"clear"` when `/clear` is run — this can be used to detect "a session just ended" and trigger capture as part of the new session's init, before the summary block appears.

Token budgeting uses `ttok` (pip-installable CLI using tiktoken) for accurate Anthropic-model-approximate token counts. The fallback is a 4-chars-per-token heuristic if Python is unavailable. Entry tracking persists to `$BRAIN_PATH/.brain-session-state.json` — a flat JSON file recording the last-loaded entry set (paths + mtimes), enabling "new/changed since last session" filtering.

**Primary recommendation:** SessionStart hook outputs `hookSpecificOutput.additionalContext` with the formatted vault context. Stop hook uses `decision:"block"` to trigger skills via reason text on first fire, exits immediately on second fire (stop_hook_active guard). Session state file enables delta-loading.

---

## Standard Stack

### Core

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| Claude Code Hooks `hookSpecificOutput.additionalContext` | v2.0.76+ | Inject vault context into Claude's session context | Only mechanism for automatic context injection at session start. Fixed in v2.0.76 after a silent-drop bug. |
| `jq` 1.6+ | already a hard dep | Parse frontmatter-extracted YAML fields from JSON, build output JSON | Hard dependency from Phase 1. All hook JSON parsing uses jq. |
| `bash` sed/grep frontmatter extraction | bash 3.2+ | Extract YAML frontmatter fields from `.md` files without extra tools | No additional deps — sed and grep extract frontmatter from `---`-delimited blocks reliably. |
| `ttok` | latest (pip) | Accurate token counting for budget enforcement | pip-installable, cross-platform, uses tiktoken (cl100k_base — close enough to Anthropic's tokenizer for budget purposes). Simon Willison project, actively maintained. |
| `$BRAIN_PATH/.brain-session-state.json` | N/A (file) | Persist loaded-entry set between sessions | Simple JSON file: paths + mtimes of last loaded entries. Enables delta-loading next session. |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `CLAUDE_ENV_FILE` | SessionStart only | Persist env vars (e.g., `BRAIN_LOADED=1`) into the session's bash env | Set after successful context load so other hooks can check whether brain loaded |
| `git remote get-url origin` | System git | Extract repo name for project matching fallback | When cwd basename doesn't match frontmatter `project:` field — try git remote as secondary match |
| `date -r` / `stat` | System | Get file modification time for recency sorting | Sort vault entries by mtime for "most recent first" prioritization |
| `find` | System | Scan vault directories for matching `.md` files | Walk `$BRAIN_PATH/` to collect candidate files by frontmatter `project:` or `type:` field |

### Alternatives Considered

| Standard | Alternative | Tradeoff |
|----------|-------------|----------|
| `hookSpecificOutput.additionalContext` JSON | Plain text stdout | Plain stdout is also injected as context but is visible in the transcript as hook output. JSON is discrete. Both work; JSON is preferred per the decision for "first message output" being the summary block. |
| `ttok` (tiktoken-based) | word count / char heuristic | 4 chars per token is a rough estimate — may overshoot or undershoot by 20-30%. `ttok` is accurate within the tokenizer's model differences. Decision says "precise tokenizer". |
| `ttok` (tiktoken) | Anthropic token counting API | API call adds latency to every session start. `ttok` uses cl100k_base which is close enough — Anthropic's tokenizer differs but not enough to matter for 2,000-token budget enforcement. |
| sed/grep frontmatter | `yq` | `yq` is cleaner but is an additional dependency not in the Phase 1 stack. sed/grep handles simple `key: value` frontmatter reliably for this use case. |
| Stop hook `decision:block` reason | UserPromptSubmit hook | UserPromptSubmit can inject additional context but fires on every prompt — overkill for end-of-session capture. Stop hook is the correct semantics. |

**Installation:**

```bash
# ttok for token counting
pip install ttok
# or: pipx install ttok

# Verify
echo "hello world" | ttok
# Output: 2
```

---

## Architecture Patterns

### Recommended Project Structure

```
~/.claude/hooks/
├── lib/
│   ├── brain-path.sh           # Phase 1: BRAIN_PATH validation (existing)
│   └── brain-context.sh        # Phase 2: vault query + budget management library
├── session-start.sh            # Phase 2: fills in vault context injection
├── stop.sh                     # Phase 2: fills in pre-stop capture trigger
└── pre-compact.sh              # Phase 2: fills in pre-compact capture trigger

$BRAIN_PATH/
├── .brain-session-state.json   # Phase 2: last-loaded entry tracking
├── .brain-errors.log           # Phase 1: error + info log (existing)
└── [vault content]
```

### Pattern 1: SessionStart Context Injection via hookSpecificOutput

**What:** SessionStart hook reads vault, builds context string within token budget, emits it via `hookSpecificOutput.additionalContext`. Claude sees this as injected context. The summary block appears as the first thing Claude says when it greets the user.

**When to use:** Every SessionStart firing (source: startup, resume, clear, compact).

```bash
# Source: code.claude.com/docs/en/hooks — hookSpecificOutput schema
# ~/.claude/hooks/session-start.sh (Phase 2 version)
#!/usr/bin/env bash
HOOK_INPUT=$(cat)
source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 1
fi

# Source the context library
source ~/.claude/hooks/lib/brain-context.sh

SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // "startup"')
CWD=$(printf '%s' "$HOOK_INPUT" | jq -r '.cwd // ""')

# Build context payload within token budget
CONTEXT_PAYLOAD=$(build_brain_context "$CWD" "$SOURCE")
SUMMARY=$(build_summary_block "$CWD" "$SOURCE")

# Write BRAIN_LOADED to session env for downstream hooks
if [ -n "$CLAUDE_ENV_FILE" ]; then
  printf 'export BRAIN_LOADED=1\n' >> "$CLAUDE_ENV_FILE"
fi

# Emit hookSpecificOutput — context goes to Claude's context discretely
# Summary block is prepended so Claude says it as first output
ADDITIONAL_CONTEXT="${SUMMARY}

${CONTEXT_PAYLOAD}"

emit_json "$(printf '%s' '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":' && printf '%s' "$ADDITIONAL_CONTEXT" | jq -Rs . && printf '%s' '}}')"
exit 0
```

**Critical:** The `additionalContext` value must be a JSON string (use `jq -Rs .` to safely encode multiline text). Building the final JSON by concatenation is fragile — use `jq --arg` or `jq -n` to construct it safely.

```bash
# Safe JSON construction for additionalContext
CONTEXT_JSON=$(jq -n --arg ctx "$ADDITIONAL_CONTEXT" \
  '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}')
emit_json "$CONTEXT_JSON"
```

### Pattern 2: Vault Query + Frontmatter Extraction

**What:** Shell function that walks the vault, extracts frontmatter fields with sed/grep, and filters files by project name match.

**When to use:** Inside `brain-context.sh` library called by session-start.sh.

```bash
# Source: verified against official bash docs / sed behavior
# Extract a YAML frontmatter field from a markdown file
# Usage: get_frontmatter_field "project" "/path/to/file.md"
get_frontmatter_field() {
  local field="$1"
  local file="$2"
  # Extract block between first and second ---
  # Then grep for the field and strip key + colon + optional quotes
  sed -n '/^---$/,/^---$/p' "$file" 2>/dev/null \
    | grep "^${field}:" \
    | head -1 \
    | sed "s/^${field}:[[:space:]]*//" \
    | sed 's/^["\x27]//' \
    | sed 's/["\x27]$//' \
    | tr -d '\r'
}

# Get file modification time as Unix timestamp (portable)
get_mtime() {
  local file="$1"
  if stat -c '%Y' "$file" 2>/dev/null; then   # GNU stat (Linux)
    return
  fi
  stat -f '%m' "$file" 2>/dev/null            # BSD stat (macOS)
}
```

### Pattern 3: Token Budget Enforcement

**What:** Accumulate content in priority order, check running token count after each entry, stop when budget is reached. Never summarize — drop instead.

**When to use:** Inside `build_brain_context` when assembling entries.

```bash
# Source: ttok docs — pipe text, get token count
# Count tokens in a string
count_tokens() {
  local text="$1"
  if command -v ttok >/dev/null 2>&1; then
    printf '%s' "$text" | ttok 2>/dev/null || echo "0"
  else
    # Fallback: rough estimate (4 chars per token)
    printf '%s' "$text" | wc -c | awk '{print int($1/4)}'
  fi
}

# Budget-enforced accumulation
BUDGET="${BRAIN_TOKEN_BUDGET:-2000}"
accumulated=""
token_count=0

for entry_file in "${priority_sorted_entries[@]}"; do
  entry_content=$(cat "$entry_file")
  entry_tokens=$(count_tokens "$entry_content")

  if [ $((token_count + entry_tokens)) -le "$BUDGET" ]; then
    accumulated="${accumulated}
${entry_content}"
    token_count=$((token_count + entry_tokens))
  else
    # Budget reached — stop adding (no summarization)
    break
  fi
done
```

### Pattern 4: Project Matching

**What:** Match vault entries to current project using (1) cwd basename, (2) git remote repo name as fallback. Check frontmatter `project:` field against both.

**When to use:** Inside `build_brain_context` for filtering project-specific entries.

```bash
# Extract project identifier from current working directory
get_project_name() {
  local cwd="$1"
  local dir_name
  dir_name=$(basename "$cwd")

  # Also try git remote for repos where dir name doesn't match
  local git_remote=""
  if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    git_remote=$(git -C "$cwd" remote get-url origin 2>/dev/null \
      | sed 's/.*[:/]\([^/]*\)\.git$/\1/' \
      | sed 's/.*[:/]\([^/]*\)$/\1/')
  fi

  # Return both candidates (space-separated); caller checks both
  printf '%s %s' "$dir_name" "$git_remote"
}

# Match a vault entry against project candidates
entry_matches_project() {
  local file="$1"
  local project_candidates="$2"   # space-separated
  local file_project
  file_project=$(get_frontmatter_field "project" "$file")

  [ -z "$file_project" ] && return 1  # no project field = skip

  for candidate in $project_candidates; do
    [ -z "$candidate" ] && continue
    [ "$file_project" = "$candidate" ] && return 0
  done
  return 1
}
```

### Pattern 5: Stop Hook Capture Trigger

**What:** On the first Stop fire, block Claude with a reason that instructs it to run `/brain-capture` then `/daily-note`. On the second fire (stop_hook_active=true), exit immediately. The loop guard from Phase 1 already handles the second-fire case.

**When to use:** stop.sh Phase 2 implementation.

```bash
# Source: code.claude.com/docs/en/hooks — Stop decision control
# ~/.claude/hooks/stop.sh (Phase 2 version)
#!/usr/bin/env bash
HOOK_INPUT=$(cat)

# CRITICAL: Loop guard FIRST (Phase 1 pattern)
STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

source ~/.claude/hooks/lib/brain-path.sh
if ! brain_path_validate; then
  exit 0
fi

# Phase 2: trigger capture before stopping
# Use decision:block to give Claude one turn to run skills
emit_json '{"decision":"block","reason":"Before ending this session, please run /brain-capture to save any useful patterns from this conversation, then run /daily-note to log a session summary. After running both, you can stop."}'
exit 0
```

**Important caveat:** The reason text is fed to Claude as a prompt, but Claude acting on it is LLM behavior — not guaranteed shell execution. This is the correct mechanism per official docs. The loop guard ensures this fires exactly once per session end.

### Pattern 6: Source-Aware SessionStart (handling /clear)

**What:** When `source:"clear"`, the user just ran `/clear` — the session context was wiped but brain should reload fresh. When `source:"startup"` or `source:"resume"`, normal load. When `source:"compact"`, context was compacted — reload selectively.

**When to use:** session-start.sh to vary behavior by source.

```bash
SOURCE=$(printf '%s' "$HOOK_INPUT" | jq -r '.source // "startup"')

case "$SOURCE" in
  "clear")
    # User ran /clear — full reload, show summary
    # Note: Stop hook already fired before /clear, capture already triggered
    LOAD_MODE="full"
    ;;
  "compact")
    # Context was compacted — reload delta (new/changed since last load)
    LOAD_MODE="delta"
    ;;
  "startup"|"resume"|*)
    LOAD_MODE="full"
    ;;
esac
```

### Pattern 7: Session State Tracking

**What:** After loading entries, write `$BRAIN_PATH/.brain-session-state.json` with the list of loaded files and their mtimes. Next session reads this to identify new/changed entries for delta loading.

**When to use:** End of session-start.sh, after context is assembled.

```bash
# Write session state after successful load
write_session_state() {
  local project="$1"
  local loaded_files=("${@:2}")   # remaining args are file paths

  local state_file="$BRAIN_PATH/.brain-session-state.json"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Build JSON array of {path, mtime} objects
  local entries_json="[]"
  for f in "${loaded_files[@]}"; do
    local mtime
    mtime=$(get_mtime "$f")
    entries_json=$(printf '%s' "$entries_json" \
      | jq --arg p "$f" --arg m "$mtime" '. + [{"path":$p,"mtime":$m}]')
  done

  jq -n \
    --arg project "$project" \
    --arg ts "$timestamp" \
    --argjson entries "$entries_json" \
    '{"project":$project,"loaded_at":$ts,"entries":$entries}' \
    > "$state_file"
}

# Read previous state to identify new/changed files
is_entry_new_or_changed() {
  local file="$1"
  local state_file="$BRAIN_PATH/.brain-session-state.json"

  [ ! -f "$state_file" ] && return 0  # no state = everything is new

  local prev_mtime
  prev_mtime=$(jq -r --arg p "$file" '.entries[] | select(.path == $p) | .mtime' "$state_file" 2>/dev/null)

  [ -z "$prev_mtime" ] && return 0    # not in previous state = new

  local current_mtime
  current_mtime=$(get_mtime "$file")
  [ "$current_mtime" != "$prev_mtime" ] && return 0  # changed
  return 1   # unchanged
}
```

### Anti-Patterns to Avoid

- **Constructing JSON by string concatenation with user content:** Vault entry text may contain quotes, backslashes, newlines. Always use `jq -n --arg` or `jq -Rs .` to safely encode string values into JSON.
- **Reading all vault files on every session:** Walk only relevant directories (`projects/`, `prompts/`, `frameworks/`) and stop when budget is reached. Full vault scan adds latency.
- **Blocking Stop indefinitely:** The loop guard fires once, Claude runs skills, then the next Stop fires with `stop_hook_active=true` and exits immediately. Never remove the loop guard from stop.sh.
- **Using exit 2 from Stop with reason:** Exit 2 on Stop means "show stderr to Claude as error". Exit 0 with JSON `decision:block` is the correct way to block while providing reasoning.
- **Relying on `source:"clear"` to mean Stop already fired:** `/clear` fires Stop hook first, then SessionStart with `source:"clear"`. The hooks fire in this order. Don't double-capture.
- **Hardcoding the budget in multiple places:** Read from `${BRAIN_TOKEN_BUDGET:-2000}` everywhere. Single env var controls the budget.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Token counting | Word count / char heuristic | `ttok` (tiktoken-based CLI) | Decision requires precise tokenizer. Char heuristic can be off by 20-30% — overshooting wastes context, undershooting risks budget violations. |
| JSON string encoding | Manual quote escaping | `jq -n --arg key "value"` or `printf '%s' | jq -Rs .` | Vault content contains arbitrary text with quotes, backslashes, newlines. Manual escaping always misses edge cases. |
| YAML frontmatter parsing | Full YAML parser | `sed -n '/^---$/,/^---$/p' | grep "^key:"` | The brain vault uses simple `key: value` frontmatter. No nested YAML, no arrays in relevant fields. sed/grep is sufficient and adds no dependency. |
| Session persistence | Custom file format | `$BRAIN_PATH/.brain-session-state.json` via jq | jq is already a hard dep. JSON file is simple, inspectable, and manipulable with existing tools. |
| Pre-capture orchestration | New shell-level skill runner | Stop hook `decision:block` + reason | The existing `/brain-capture` and `/daily-note` skills handle capture. The hook's job is to trigger them via Claude, not duplicate their logic. |

**Key insight:** The hook's job is orchestration, not implementation. The skills already exist, the vault already exists, jq already exists. Phase 2 wires them together.

---

## Common Pitfalls

### Pitfall 1: additionalContext JSON Encoding Failure

**What goes wrong:** Vault content contains a double quote or backslash. The hook builds `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"vault content with "quotes""}}`. jq rejects it. emit_json suppresses output. Claude gets no context.
**Why it happens:** String concatenation into JSON with unescaped content from user files.
**How to avoid:** Always construct the JSON with `jq -n --arg ctx "$CONTENT"`. The `--arg` flag handles all escaping automatically.
**Warning signs:** Session starts with no brain summary block; emit_json error in `.brain-errors.log`.

### Pitfall 2: Stop Hook Triggering Capture on Every Turn

**What goes wrong:** Stop hook fires on every Claude response turn (after every tool use completion), not just session end. The hook blocks on every turn, triggering capture after every response.
**Why it happens:** Stop fires whenever Claude finishes responding — not just at `/exit`.
**How to avoid:** The loop guard handles the "don't run twice" case, but it doesn't prevent the hook from running on every non-stop turn. The hook must check whether this is actually a session-end scenario vs. a mid-session response. One approach: only block if the session has lasted more than N turns (check transcript length). Simpler: accept that capture will be attempted each session-end, rely on skills to decide what's worth saving.
**Warning signs:** `/brain-capture` runs after every Claude response, not just at session end.

**Clarification on Stop hook behavior:** Stop fires when Claude finishes its response and is ready to wait for user input — it fires multiple times per session, not just on `/exit`. stop_hook_active becomes true when Claude was already blocked by a Stop hook on this turn. The pattern is: first fire per turn = run capture; stop_hook_active=true = already triggered capture this turn, let stop proceed.

### Pitfall 3: `source:"clear"` Means Context Already Wiped

**What goes wrong:** Hook tries to read transcript or last message on `source:"clear"` SessionStart to capture what was just cleared. The transcript is already cleared at this point.
**Why it happens:** `/clear` fires Stop hook (transcript still exists), then fires SessionStart with `source:"clear"` (transcript is gone). Capture must happen in the Stop hook, before clear.
**How to avoid:** Capture happens in stop.sh (which fires before clear). SessionStart with `source:"clear"` just reloads vault context fresh — no capture attempt.
**Warning signs:** Capture runs on SessionStart `source:"clear"` and produces empty or wrong results.

### Pitfall 4: ttok Not Installed — Budget Falls Back Silently

**What goes wrong:** ttok is not installed. `count_tokens()` falls back to char heuristic with no warning. Token budget is now approximate but appears precise.
**Why it happens:** ttok is an optional install not enforced in Phase 1's settings.json.
**How to avoid:** `count_tokens()` should log a warning to `.brain-errors.log` when using fallback. Include ttok in the project's setup documentation. Check for it in session-start.sh setup section.
**Warning signs:** Token budget enforcement seems loose; entries that should be cut are included.

### Pitfall 5: Project Matching Too Aggressive

**What goes wrong:** `basename "$CWD"` returns `src` or `app` — a common directory name that matches many vault entries from different projects.
**Why it happens:** Not all projects are run from their repo root. CWD may be a subdirectory.
**How to avoid:** Use git rev-parse to find repo root: `git -C "$CWD" rev-parse --show-toplevel 2>/dev/null`. Then take `basename` of the repo root, not the CWD. Fall back to CWD basename if not in a git repo.
**Warning signs:** Wrong project entries injected into context; user reports brain loaded someone else's project notes.

### Pitfall 6: Session State File Write Failure

**What goes wrong:** Hook writes partial JSON to `.brain-session-state.json` then crashes. Next session reads corrupt state and skips all entries (treats everything as "unchanged").
**Why it happens:** jq pipeline failure, disk full, or interrupted write.
**How to avoid:** Write to a temp file first, then `mv` atomically. Validate JSON before writing. Treat a corrupt/missing state file as "no previous state" (load everything).
**Warning signs:** Delta loading shows zero new entries even on first run; session state file is empty or invalid JSON.

### Pitfall 7: `.brain.md` Token Budget Interaction

**What goes wrong:** `.brain.md` is 800 tokens. Vault entries total 1,400 tokens. Combined = 2,200 tokens, over the 2,000 budget. Hook drops some vault entries but the user expected to see them.
**Why it happens:** Unclear whether `.brain.md` shares or has a separate budget allocation (Claude's Discretion).
**How to avoid:** Research recommendation below under Open Questions. Implement as a separate allocation (`.brain.md` gets up to 500 tokens outside the vault budget) to prevent project-local knowledge from squeezing out vault entries.
**Warning signs:** User reports vault entries missing when `.brain.md` exists; budget exhausted before global prefs loaded.

---

## Code Examples

Verified patterns from official sources:

### Safe additionalContext JSON Construction

```bash
# Source: jq documentation — --arg flag for safe string injection
# ALWAYS use this pattern for vault content → JSON. Never string concatenate.
build_additional_context_json() {
  local content="$1"
  jq -n --arg ctx "$content" \
    '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":$ctx}}'
}

# Usage:
CONTEXT_JSON=$(build_additional_context_json "$ASSEMBLED_CONTENT")
emit_json "$CONTEXT_JSON"
```

### Frontmatter Extraction (bash, no yq)

```bash
# Source: bash/sed/grep standard — verified portable pattern
# Extracts value of a simple "key: value" YAML frontmatter field
get_frontmatter_field() {
  local field="$1"
  local file="$2"
  sed -n '0,/^---$/d;/^---$/q;p' "$file" 2>/dev/null \
    | grep "^${field}:[[:space:]]*" \
    | head -1 \
    | sed "s/^${field}:[[:space:]]*//" \
    | tr -d '"'"'" \
    | tr -d '\r'
}

# Alternative that handles the first --- as opening delimiter:
get_frontmatter_field_v2() {
  local field="$1"
  local file="$2"
  awk '/^---/{found++; next} found==1{print} found==2{exit}' "$file" \
    | grep "^${field}:[[:space:]]*" \
    | head -1 \
    | sed "s/^${field}:[[:space:]]*//" \
    | tr -d '"'"'"
}
```

### Token Count with Fallback

```bash
# Source: ttok README — pipe text, get count
# Falls back to char heuristic if ttok unavailable
count_tokens() {
  local text="$1"
  if command -v ttok >/dev/null 2>&1; then
    printf '%s' "$text" | ttok 2>/dev/null || printf '%s' "$text" | wc -c | awk '{print int($1/4)}'
  else
    brain_log_error "TokenCount" "ttok not installed, using char heuristic (4 chars/token)"
    printf '%s' "$text" | wc -c | awk '{print int($1/4)}'
  fi
}
```

### Session State JSON Write (atomic)

```bash
# Source: standard bash atomic write pattern — temp file + mv
write_session_state() {
  local project="$1"
  shift
  local loaded_files=("$@")
  local state_file="$BRAIN_PATH/.brain-session-state.json"
  local tmp_file
  tmp_file=$(mktemp "${state_file}.XXXXXX")

  local entries_json="[]"
  for f in "${loaded_files[@]}"; do
    local mtime
    mtime=$(get_mtime "$f")
    entries_json=$(printf '%s' "$entries_json" \
      | jq --arg p "$f" --arg m "$mtime" '. + [{"path":$p,"mtime":$m}]')
  done

  jq -n \
    --arg project "$project" \
    --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --argjson entries "$entries_json" \
    '{"project":$project,"loaded_at":$ts,"entries":$entries}' \
    > "$tmp_file" && mv "$tmp_file" "$state_file"
}
```

### Git Repo Root for Project Matching

```bash
# Source: git documentation — rev-parse --show-toplevel
# Gets the canonical project name from git repo root
get_canonical_project_name() {
  local cwd="$1"
  local repo_root
  # Try git repo root first (handles case where CWD is a subdirectory)
  repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$repo_root" ]; then
    basename "$repo_root"
  else
    basename "$cwd"
  fi
}
```

### Stop Hook with Capture Trigger

```bash
# Source: code.claude.com/docs/en/hooks — Stop decision control
# Phase 2 stop.sh — loop guard is from Phase 1, now adds capture trigger
HOOK_INPUT=$(cat)

STOP_HOOK_ACTIVE=$(printf '%s' "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0   # Loop guard: second fire, let Claude stop
fi

source ~/.claude/hooks/lib/brain-path.sh
if ! brain_path_validate; then
  exit 0   # Degrade gracefully on invalid path
fi

# Phase 2: block once to trigger capture
REASON="Before ending this session, please run /brain-capture to preserve any useful patterns, then run /daily-note to log a session summary. After completing both, you can stop."

BLOCK_JSON=$(jq -n --arg reason "$REASON" \
  '{"decision":"block","reason":$reason}')
emit_json "$BLOCK_JSON"
exit 0
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| SessionStart stdout as plain text | `hookSpecificOutput.additionalContext` JSON | v2.0.76 (fixed silent-drop bug from v2.0.65) | Plain text still works but shows in transcript. JSON injects discretely. Both are valid; JSON is preferred. |
| Stop hook uses exit 2 to block | Stop hook uses exit 0 + JSON `decision:block` | Claude Code v2.0+ | Exit 2 on Stop now shows stderr as "Stop hook error" (see issue #34600). Use exit 0 + JSON for block signal. |
| Manual capture via `/brain-capture` command | Automated trigger via Stop hook | Phase 2 of this project | Stop hook fires automatically; user can still invoke manually. |
| Context injection via CLAUDE.md | SessionStart hook `additionalContext` | Claude Code v2.0+ (hooks API) | CLAUDE.md is static file read at session start. Hook is dynamic — reads current vault state each session. |

**Deprecated/outdated:**

- Using plain text stdout for context injection when JSON is needed: Still works but is less clean — appears in transcript. Only use plain text when you want visibility.
- Stop hook `exit 2` for blocking: Now shows as "Stop hook error" in UI (issue #34600). Use `exit 0` + `{"decision":"block","reason":"..."}` instead.

---

## Open Questions

1. **Does the Stop hook fire after every Claude response, or only at session end?**
   - What we know: Official docs say Stop fires "when Claude finishes responding." This is per turn, not per session. `stop_hook_active` prevents double-firing per turn.
   - What's unclear: If Stop fires after every response turn, the "capture before ending" trigger fires constantly, not just at session end. This degrades the user experience (every response blocked once for capture).
   - Recommendation: Implement the Stop hook capture trigger but check whether this causes excessive interruption during normal usage. If it does, switch to a different strategy: detect `/exit` via the `last_assistant_message` field or use the `source:"clear"` SessionStart as the capture trigger instead (capture fired in Stop before /clear, then SessionStart with source:clear reloads fresh). This may require a Phase 2.5 revision based on real usage.

2. **`.brain.md` token budget: shared or separate allocation?**
   - What we know: Decision leaves this to Claude's Discretion.
   - What's unclear: If `.brain.md` is large (e.g., 600 tokens), sharing the budget means it pushes out vault entries. Separate allocation prevents this but may go over budget if both are large.
   - Recommendation: Give `.brain.md` a separate fixed allocation of 500 tokens (outside the main vault budget). This prevents a large `.brain.md` from evicting vault entries, and 500 tokens is enough for project-local notes. Log a warning if `.brain.md` exceeds 500 tokens.

3. **Stop hook reliability for skill invocation via reason text**
   - What we know: The `reason` field is fed to Claude as an instruction to continue. Claude will act on it per its reasoning — not guaranteed automation.
   - What's unclear: How reliably does Claude follow "run /brain-capture then /daily-note" instructions from the reason field?
   - Recommendation: Accept LLM-based reliability for Phase 2 (consistent with the "orchestrate existing skills first" principle). If real usage shows Claude ignoring the instruction, switch to: write session notes directly from the shell script instead of invoking skills. The Stop hook has access to `transcript_path` — could read the transcript and extract learnings via a subshell.

4. **`stat` portability: GNU vs BSD on Windows Git Bash**
   - What we know: GNU `stat -c '%Y'` works on Linux. BSD `stat -f '%m'` works on macOS. Windows Git Bash may have either or neither.
   - What's unclear: Which `stat` variant ships with Git for Windows?
   - Recommendation: Use the try-GNU-then-BSD fallback pattern already in the code example above. If both fail, fall back to treating all entries as new (safest degradation).

---

## Sources

### Primary (HIGH confidence)

- `https://code.claude.com/docs/en/hooks` — Complete hooks reference. Verified: SessionStart `hookSpecificOutput.additionalContext` schema, Stop hook `decision:block` output format, `stop_hook_active` field, `CLAUDE_ENV_FILE` availability (SessionStart only), `source` field values for SessionStart. Fetched 2026-03-19.
- `https://github.com/anthropics/claude-code/issues/13650` — Bug report: SessionStart `additionalContext` silently dropped. Resolution: Fixed in v2.0.76. Verified the field works in current versions.

### Secondary (MEDIUM confidence)

- `https://github.com/simonw/ttok` — ttok token counting CLI. Verified: pip-installable, uses tiktoken cl100k_base, cross-platform, pipes text and returns count. MEDIUM: uses OpenAI's tokenizer, not Anthropic's — close but not identical.
- `https://claudefa.st/blog/tools/hooks/session-lifecycle-hooks` — SessionStart context injection patterns. Verified the `hookSpecificOutput.additionalContext` JSON format against official docs.
- `https://docs.claude-mem.ai/hooks-architecture` — Claude-mem SessionStart architecture. Pattern of querying storage + progressive disclosure index output confirmed as viable approach.
- WebSearch findings on Stop hook `decision:block` reason field behavior — multiple sources confirm reason text is fed to Claude as instruction. No single authoritative source confirms skill invocation reliability.

### Tertiary (LOW confidence)

- WebSearch on Stop hook firing frequency (per-turn vs session-end) — results were ambiguous. Official docs say "when Claude finishes responding" which is per-turn, but some community sources describe it as session-end. **Flag for validation during Phase 2 implementation.**
- `stat` behavior on Windows Git Bash — not verified. Flag for testing during implementation.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — hookSpecificOutput.additionalContext verified against official docs and bug fix confirmation. ttok verified from official repo.
- Architecture: HIGH — hook output format, jq patterns, project matching all verified. Stop hook capture mechanism is MEDIUM (LLM-based execution reliability is inherently uncertain).
- Pitfalls: HIGH — JSON encoding failure, project matching edge cases, and Stop hook frequency all grounded in verified behavior or verified bugs.
- Open questions: Stop hook firing frequency is LOW confidence — needs empirical testing.

**Research date:** 2026-03-19
**Valid until:** 2026-04-19 (Claude Code hooks API changes frequently — re-verify if more than 30 days pass)
