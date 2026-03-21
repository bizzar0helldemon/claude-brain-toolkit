---
phase: 02-session-lifecycle
verified: 2026-03-21T05:00:00Z
status: gaps_found
score: 4/7 must-haves verified
re_verification: false
gaps:
  - truth: "Opening a project in brain mode surfaces that project's recent pitfalls and last-known state without the user asking"
    status: failed
    reason: "Hook scripts are not deployed to ~/.claude/hooks/ -- session-start.sh, stop.sh, and pre-compact.sh exist only in the repo but settings.json references ~/.claude/hooks/session-start.sh etc., which do not exist on the filesystem."
    artifacts:
      - path: "hooks/session-start.sh"
        issue: "Correct implementation in repo but NOT at the path registered in settings.json (~/.claude/hooks/session-start.sh)"
      - path: "hooks/lib/brain-context.sh"
        issue: "Correct implementation in repo but NOT deployed to ~/.claude/hooks/lib/brain-context.sh (sourced by session-start.sh at that path)"
    missing:
      - "Copy hooks/session-start.sh to ~/.claude/hooks/session-start.sh"
      - "Copy hooks/stop.sh to ~/.claude/hooks/stop.sh"
      - "Copy hooks/pre-compact.sh to ~/.claude/hooks/pre-compact.sh"
      - "Copy hooks/lib/brain-context.sh to ~/.claude/hooks/lib/brain-context.sh"
      - "Add brain hooks to ~/.claude/settings.json (currently only has gsd-check-update.js)"
  - truth: "Invoking /clear triggers an automatic brain-capture and daily-note entry before the context is wiped"
    status: failed
    reason: "Same root cause as truth 1 -- stop.sh is not deployed to ~/.claude/hooks/stop.sh, so the decision:block capture trigger cannot fire on /clear or session end."
    artifacts:
      - path: "hooks/stop.sh"
        issue: "Correct implementation in repo but NOT at ~/.claude/hooks/stop.sh"
    missing:
      - "Deploy stop.sh (same deployment step as gap 1)"
  - truth: "SessionStart vault injection stays under 2,000 tokens (verifiable via claude --verbose)"
    status: failed
    reason: "Token budget enforcement logic is correct and verified by testing, but cannot be confirmed in production because hooks are not deployed."
    artifacts:
      - path: "hooks/lib/brain-context.sh"
        issue: "BRAIN_TOKEN_BUDGET enforcement tested and working, but not reachable via Claude Code configured hooks"
    missing:
      - "Deploy hooks (see gap 1) to make this verifiable via claude --verbose"
human_verification:
  - test: "After deploying hooks, start a new Claude session in the repo and ask Claude what brain context was loaded"
    expected: "Brain summary block showing project note counts, pitfall count, and Global preferences active"
    why_human: "Requires live Claude Code session with deployed hooks"
  - test: "After deploying hooks, run /clear in a Claude session with brain mode active"
    expected: "Claude runs /brain-capture then /daily-note before clearing, then confirms what was captured"
    why_human: "decision:block behavior requires live Claude Code session to verify"
  - test: "After deploying hooks, run claude --verbose in a brain mode session and check the additionalContext token count"
    expected: "Injected vault context is under 2000 tokens"
    why_human: "Requires --verbose flag output from a live session"
---

# Phase 2: Session Lifecycle Verification Report

**Phase Goal:** Every session automatically loads relevant vault context, and knowledge is captured before context is cleared
**Verified:** 2026-03-21T05:00:00Z
**Status:** gaps_found
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Opening a project surfaces recent pitfalls and last-known state without asking | FAILED | Hooks not deployed to ~/.claude/hooks/ -- settings.json paths broken |
| 2 | /clear triggers brain-capture + daily-note before context wipes | FAILED | stop.sh not at ~/.claude/hooks/stop.sh -- cannot fire |
| 3 | SessionStart vault injection stays under 2,000 tokens | FAILED (unverifiable in production) | Logic correct in testing, but hook not reachable via Claude Code |
| 4 | session-start hook injects vault context via hookSpecificOutput.additionalContext | VERIFIED | Functional test: valid JSON with additionalContext containing brain summary block and vault entries |
| 5 | Project-specific entries matched by frontmatter project: field against git root basename | VERIFIED | pitfall1.md with project: claude-brain-toolkit loaded; non-git dir produced 0 matches |
| 6 | Token budget enforced -- entries dropped at limit, never summarized | VERIFIED | BRAIN_TOKEN_BUDGET=5 drops all entries; default 2000 loads entries within budget |
| 7 | Session state persisted to .brain-session-state.json for delta-loading | VERIFIED | State file created with correct JSON structure (project, loaded_at, entries array) |

**Score:** 4/7 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `hooks/lib/brain-context.sh` | Vault query, token budgeting, project matching, session state, summary block | VERIFIED | 643 lines (min 150), all 12 functions present, syntax clean, functional tests pass |
| `hooks/session-start.sh` | Full SessionStart hook with vault context injection | ORPHANED | 79 lines (min 30), correct implementation but sources ~/.claude/hooks/lib/brain-context.sh which does not exist |
| `hooks/stop.sh` | Pre-stop capture trigger via decision:block | ORPHANED | 24 lines (min 15), decision:block with /brain-capture + /daily-note reason, loop guard intact but not deployed |
| `hooks/pre-compact.sh` | Pre-compact capture trigger | ORPHANED | 14 lines (plan min 15, 1 line short, all 14 are functional), additionalContext with /brain-capture instruction |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `hooks/session-start.sh` | `hooks/lib/brain-context.sh` | source | BROKEN | Sources ~/.claude/hooks/lib/brain-context.sh -- file missing at that path |
| `hooks/session-start.sh` | `hookSpecificOutput.additionalContext` | jq -n --arg | VERIFIED | Tested: valid JSON with additionalContext containing summary block |
| `hooks/lib/brain-context.sh` | `.brain-session-state.json` | write_session_state / atomic mv | VERIFIED | State file created with correct JSON structure |
| `hooks/lib/brain-context.sh` | ttok or char/4 fallback | count_tokens | VERIFIED | Falls back to char/4 with one-time warning; budget enforced |
| `hooks/stop.sh` | decision:block with reason | jq -n --arg reason | VERIFIED | {"decision":"block"} on first fire, silent exit on second fire |
| `hooks/stop.sh` | /brain-capture and /daily-note skills | reason text instruction | VERIFIED | Reason text includes both skills in sequence with confirmation request |
| `hooks/pre-compact.sh` | /brain-capture skill | additionalContext instruction | VERIFIED | additionalContext contains /brain-capture instruction |
| repo `settings.json` | `~/.claude/hooks/session-start.sh` | Claude Code hook registration | BROKEN | Registered path does not exist on filesystem |
| repo `settings.json` | `~/.claude/settings.json` (active config) | user active settings | NOT WIRED | Active ~/.claude/settings.json only has gsd-check-update.js -- no brain hooks |

### Requirements Coverage

| Requirement | Status | Blocking Issue |
|-------------|--------|----------------|
| LIFE-01: SessionStart loads vault context for current project | BLOCKED | Hooks not deployed to registered paths |
| LIFE-02: Pre-clear auto-capture triggers /brain-capture then /daily-note | BLOCKED | stop.sh not at registered path |
| LIFE-03: Token budget limits vault content injection | BLOCKED (logic verified) | Hook not reachable via Claude Code |

Note: All three LIFE requirements remain marked Pending in REQUIREMENTS.md -- consistent with not yet being operational.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `hooks/session-start.sh` | 11 | sources ~/.claude/hooks/lib/brain-context.sh -- file missing at that path | Blocker | script exits with No such file or directory |
| `hooks/stop.sh` | 12 | sources ~/.claude/hooks/lib/brain-path.sh -- path exists but stop.sh itself not deployed | Blocker | stop.sh is unreachable in production |
| `hooks/pre-compact.sh` | 3 | Same sourcing pattern as stop.sh | Blocker | pre-compact.sh not at ~/.claude/hooks/pre-compact.sh |
| `settings.json` | 10 | References ~/.claude/hooks/session-start.sh which does not exist | Blocker | Hook silently fails when Claude Code tries to invoke it |
| `~/.claude/settings.json` | -- | Brain hooks not present in user active settings | Blocker | Hooks would not be invoked even if files were deployed |

### Human Verification Required

#### 1. Vault Context Injection End-to-End

**Test:** After deploying hooks, start a new Claude session in the claude-brain-toolkit repo and ask "what brain context was loaded?"
**Expected:** Brain summary block showing project note counts, pitfall count, and "Global preferences active", plus vault entries in context
**Why human:** Requires live Claude Code session with deployed hooks

#### 2. /clear Capture Trigger

**Test:** After deploying hooks, run /clear in a Claude session with brain mode active
**Expected:** Claude runs /brain-capture then /daily-note before clearing context, then confirms what was captured
**Why human:** decision:block behavior requires live Claude Code session to verify

#### 3. Token Budget via --verbose

**Test:** After deploying hooks, run claude --verbose in a brain mode session and observe the additionalContext token count
**Expected:** Injected vault context stays under 2000 tokens
**Why human:** Requires --verbose flag output from a live session

### Gaps Summary

All three ROADMAP success criteria failed due to a single root cause: **hook scripts are built in the repo but were never deployed to the paths registered in settings.json.**

Missing files at registered paths:
- `~/.claude/hooks/session-start.sh` -- registered in repo settings.json, does not exist
- `~/.claude/hooks/stop.sh` -- registered in repo settings.json, does not exist
- `~/.claude/hooks/pre-compact.sh` -- registered in repo settings.json, does not exist
- `~/.claude/hooks/lib/brain-context.sh` -- sourced by session-start.sh, does not exist

Additionally, the active user settings at `~/.claude/settings.json` do not include any brain hooks (only gsd-check-update.js is registered). Even if the files were deployed, they would not be invoked without updating this file.

The underlying implementation is correct -- all four scripts pass syntax checks and functional tests when library paths are available. Token budget enforcement, project matching, session state persistence, summary block generation, decision:block capture pattern, and loop guard all work as designed.

Phase 1 deployed brain-path.sh to ~/.claude/hooks/lib/ (file mtime 21:30, commit at 21:24 on 2026-03-19). Phase 2 did not perform the equivalent deployment of brain-context.sh or the hook shell scripts. The Phase 2 human-verify summary records "APPROVED" without documenting what was actually tested -- the verification steps described a live Claude session flow that would have required deployed hooks to work.

The fix is a deployment step only: copy four files to their registered paths and add the brain hooks to ~/.claude/settings.json. No code changes are needed.

---

_Verified: 2026-03-21T05:00:00Z_
_Verifier: Claude (gsd-verifier)_
