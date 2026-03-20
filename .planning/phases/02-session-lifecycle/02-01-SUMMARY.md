---
phase: "02"
plan: "01"
subsystem: session-lifecycle
tags: [brain-context, vault-query, token-budget, session-state, hooks]
dependency_graph:
  requires: [01-01, 01-02]
  provides: [vault-context-injection, session-state, token-budget-enforcement]
  affects: [02-02, 02-03]
tech_stack:
  added: []
  patterns:
    - "_BRAIN_CONTEXT_STATE_FILE temp-file pattern for propagating subshell state to parent"
    - "jq --arg for all JSON construction with user content (never string concatenation)"
    - "Atomic write via temp + mv for session state file"
    - "ttok with char/4 fallback for token counting"
key_files:
  created:
    - hooks/lib/brain-context.sh
  modified:
    - hooks/session-start.sh
decisions:
  - "Used _BRAIN_CONTEXT_STATE_FILE temp-file pattern instead of named pipes: bash $() subshell cannot propagate array/variable mutations to parent — temp file is the portable bash solution"
  - "Pitfall count in summary includes only project-specific pitfall entries, not global ones"
  - "Global entries and project entries are both subject to token budget (not reserved allocations)"
metrics:
  duration: "~15 minutes"
  completed: "2026-03-20"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 2 Plan 01: Brain Context Library + Session Hook Summary

Vault query library and full SessionStart hook implementation: project-matched entries loaded within a configurable token budget, .brain.md gets a separate 500-token slot, session state persisted for delta-loading, and a summary block injected as first-message context.

## What Was Built

### hooks/lib/brain-context.sh

Sourced library providing all vault context assembly functions. Depends on `brain-path.sh` (sourced first). Implements 12 functions:

| Function | Purpose |
|----------|---------|
| `get_frontmatter_field` | Extract YAML frontmatter field from .md file (awk-based, handles `---` delimiters) |
| `get_mtime` | File mtime as Unix timestamp (GNU stat → BSD stat → date -r fallback) |
| `get_project_name` | Git repo root basename + remote name as candidates; falls back to cwd basename |
| `count_tokens` | ttok if available, char/4 heuristic fallback; warns once per session |
| `entry_matches_project` | Check frontmatter `project:` field against space-separated candidates |
| `collect_vault_entries` | Walk $BRAIN_PATH for .md files; sort project entries by mtime desc, globals follow |
| `load_brain_md` | Load .brain.md from project root; cap at 500 tokens, truncate if exceeded |
| `build_brain_context` | Main entry point: assemble vault context within BRAIN_TOKEN_BUDGET (default 2000) |
| `build_summary_block` | Emit brain emoji summary line with counts, recency, global prefs status |
| `write_session_state` | Atomic write of .brain-session-state.json (temp + mv) |
| `is_entry_new_or_changed` | Compare mtime against session state for delta-loading |
| `_is_global_entry` / `_is_pitfall_entry` | Internal classifiers for entry type detection |

### hooks/session-start.sh

Replaced Phase 1 scaffold with full context injection:
1. Parses `source` and `cwd` from HOOK_INPUT
2. Creates `_BRAIN_CONTEXT_STATE_FILE` temp file before calling `build_brain_context` in subshell
3. Sources state file back to restore `_PROJECT_COUNT`, `_PITFALL_COUNT`, `_GLOBAL_ACTIVE`, `_NEWEST_MTIME`, `_LOADED_FILES`
4. Builds `hookSpecificOutput.additionalContext` JSON via `jq -n --arg`
5. Writes session state after successful emit
6. Signals `BRAIN_LOADED=1` to downstream hooks via `$CLAUDE_ENV_FILE`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed subshell state propagation for module-level tracking variables**

- **Found during:** Task 2 verification
- **Issue:** `build_brain_context` is called via `$(...)` (command substitution) in `session-start.sh`. Bash `$()` creates a subshell, so mutations to `_PROJECT_COUNT`, `_LOADED_FILES`, etc. inside the function are lost when the subshell exits. Module-level tracking state was always zero/empty in the parent shell.
- **Fix:** Added `_BRAIN_CONTEXT_STATE_FILE` pattern. Before calling `build_brain_context`, caller creates a temp file via `mktemp` and exports it as `_BRAIN_CONTEXT_STATE_FILE`. The function writes shell variable assignments to that file at the end. Caller sources the file, then removes it. This propagates all tracking state portably across the subshell boundary.
- **Files modified:** `hooks/lib/brain-context.sh` (build_brain_context), `hooks/session-start.sh`
- **Commit:** cfc1a17 (included in Task 2 commit)

## Verification Results

All 7 overall verification checks passed:

1. `bash -n hooks/lib/brain-context.sh` — no syntax errors
2. `bash -n hooks/session-start.sh` — no syntax errors
3. Output is valid JSON with `hookSpecificOutput.additionalContext` key
4. Token budget (BRAIN_TOKEN_BUDGET=100) drops entries correctly — 0 of 5 loaded with 100-token budget
5. Summary block contains brain emoji and "Brain loaded" text
6. `.brain-session-state.json` is created after write_session_state call
7. Project matching uses git repo root basename (even when cwd is a subdirectory)

## Task Commits

| Task | Name | Commit |
|------|------|--------|
| 1 | Create brain-context.sh vault query and budget library | d18d369 |
| 2 | Update session-start.sh with full vault context injection | cfc1a17 |

## Self-Check: PASSED

| Item | Status |
|------|--------|
| hooks/lib/brain-context.sh | FOUND (643 lines, min 150) |
| hooks/session-start.sh | FOUND (79 lines, min 30) |
| .planning/phases/02-session-lifecycle/02-01-SUMMARY.md | FOUND |
| Commit d18d369 (Task 1) | FOUND |
| Commit cfc1a17 (Task 2) | FOUND |
