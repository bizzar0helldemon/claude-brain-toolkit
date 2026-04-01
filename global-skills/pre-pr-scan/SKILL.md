---
name: pre-pr-scan
description: Multi-agent quality gate — scan for CI failures, security issues, logic bugs, and commit hygiene before creating a PR.
argument-hint: [--quick | branch-name]
---

# Pre-PR Scan — Quality Gate

Spawn 4 parallel agents to scan your changes before creating a PR. Catches issues that would otherwise fail CI or get flagged in review.

**Usage**: `/pre-pr-scan [flags] [branch]`

**Examples**:
- `/pre-pr-scan` — full scan of current branch vs base
- `/pre-pr-scan --quick` — lightweight scan (skip commit history analysis)
- `/pre-pr-scan feature/auth` — scan a specific branch

## When to Use

- Before `/brain-ship` — catch issues before they hit CI
- After a large feature — comprehensive quality check
- Before requesting review — save reviewer time

## Paths

- **Brain root:** `$BRAIN_PATH`
- **Daily notes:** `$BRAIN_PATH/daily_notes/`

## Steps

### Step 1: Determine Scope

1. Identify the base branch (default: `main` or `master`)
2. Get the diff: `git diff {base}...HEAD`
3. Get changed files: `git diff {base}...HEAD --name-only`
4. Get commit log: `git log {base}..HEAD --oneline`
5. If `--quick` flag: skip Agent 4 (commit history)

Report scope:
```
Pre-PR Scan — preparing

  Branch: {current} → {base}
  Commits: {N}
  Files changed: {N}
  Lines: +{added} -{removed}

  Launching {3|4} scan agents...
```

### Step 2: Launch Scan Agents

Launch agents **in parallel** using the Agent tool with `model: sonnet` for speed.

#### Agent 1: Guidelines & CI Compliance

```
You are a CI compliance scanner. Analyze the following git diff for issues that would
fail CI or violate project guidelines.

Check for:
- CLAUDE.md guideline violations (if CLAUDE.md exists, read it first)
- Linting issues: inconsistent formatting, missing semicolons, wrong indentation
- Import issues: unused imports, missing imports, circular dependencies
- Type errors: obvious type mismatches, missing type annotations where required
- Build issues: syntax errors, unclosed brackets, missing dependencies

Changed files: {file_list}
Diff: {diff_content}

Report each finding as:
### {title}
- **severity**: error | warning
- **confidence**: high | medium | low
- **file**: {path}:{line}
- **description**: {what's wrong}
- **fix**: {how to fix}

If no issues found, report "No CI compliance issues detected."
Stay within 4000 tokens. Be precise — false positives waste developer time.
```

#### Agent 2: Security Scanner

```
You are a security scanner. Analyze the following git diff for security vulnerabilities.

Check for:
- OWASP Top 10: injection (SQL, command, XSS), broken auth, sensitive data exposure
- Secrets in code: API keys, tokens, passwords, private keys (even if they look like test values)
- Dependency issues: known vulnerable package versions (check package.json, requirements.txt, etc.)
- Input validation: user input flowing to dangerous sinks without sanitization
- Path traversal: user-controlled paths in file operations
- Insecure defaults: debug mode, permissive CORS, weak crypto

Changed files: {file_list}
Diff: {diff_content}

Report each finding as:
### {title}
- **severity**: critical | high | medium | low
- **confidence**: high | medium | low
- **file**: {path}:{line}
- **cwe**: {CWE-ID if applicable}
- **description**: {what's vulnerable}
- **fix**: {how to fix}

IMPORTANT: Only flag real issues with clear evidence. Do not flag:
- Test files with fake credentials
- Example/documentation values
- Internal-only debug endpoints behind auth

Stay within 4000 tokens.
```

#### Agent 3: Logic & Error Handling

```
You are a code logic reviewer. Analyze the following git diff for bugs, logic errors,
and missing error handling.

Check for:
- Off-by-one errors, boundary conditions
- Null/undefined dereferences
- Race conditions in async code
- Missing error handling (uncaught exceptions, unhandled promise rejections)
- Resource leaks (unclosed files, connections, streams)
- Logic inversions (wrong boolean, incorrect comparison)
- Edge cases: empty arrays, zero values, very large inputs
- Dead code introduced by the diff

Changed files: {file_list}
Diff: {diff_content}

Report each finding as:
### {title}
- **severity**: error | warning
- **confidence**: high | medium | low
- **file**: {path}:{line}
- **description**: {what could go wrong}
- **fix**: {how to fix}

Focus on the CHANGED lines. Don't flag pre-existing issues unless the diff makes them worse.
Stay within 4000 tokens.
```

#### Agent 4: Commit History (skip if `--quick`)

```
You are a commit history reviewer. Analyze the commit log for this branch.

Commit log:
{git log output with --stat}

Check for:
- Commit message quality: are messages descriptive? Do they follow conventions?
- Scope creep: do any commits touch unrelated files?
- Squash candidates: are there fixup commits that should be squashed?
- WIP commits: any "wip", "tmp", "fix fix" messages that should be cleaned up?
- Large commits: any single commit touching > 20 files (should be split)?

Report each finding as:
### {title}
- **severity**: warning | info
- **confidence**: high | medium
- **commit**: {short hash}
- **description**: {what's wrong}
- **fix**: {how to fix}

Stay within 2000 tokens.
```

### Step 3: Collect & Deduplicate

After all agents complete:

1. Read all agent outputs
2. Deduplicate findings that overlap (e.g., Agent 1 and Agent 2 both flag the same hardcoded key)
3. Sort by severity (critical → error → warning → info), then by confidence (high → medium → low)

### Step 4: Present Results

```
Pre-PR Scan — complete

  Agents: {N} ran | Findings: {N} total
  Critical: {N} | Error: {N} | Warning: {N} | Info: {N}

## Critical / Error Findings

### [Security] SQL injection in user search
- **File:** src/api/users.js:42
- **Confidence:** high
- **Description:** User input interpolated directly into SQL query
- **Fix:** Use parameterized query: `db.query('SELECT * FROM users WHERE name = $1', [name])`

## Warnings

- [CI] Unused import `lodash` in src/utils.js:3 — remove it
- [Logic] Missing null check on `user.profile` in src/api/users.js:67
- [History] Commit abc1234 "wip" should be squashed before merge

## Verdict

{PASS | FAIL | REVIEW NEEDED}

- **PASS**: No critical or error findings. Safe to ship.
- **FAIL**: Critical or high-confidence error findings. Fix before shipping.
- **REVIEW NEEDED**: Only warnings or low-confidence errors. Use judgment.
```

### Step 5: Daily Note Entry

Append to `$BRAIN_PATH/daily_notes/{YYYY-MM-DD}.md`:

```markdown
- {HH:MM} — Pre-PR scan: {N} findings ({verdict}). {top finding summary}
```

## Integration with brain-ship

When `/brain-ship` is invoked, suggest running `/pre-pr-scan` first if it hasn't been run this session. The session guardian metrics file can track whether a scan was performed.

## Error Handling

| Error | Action |
|-------|--------|
| Not in a git repo | Abort with message |
| No commits vs base | Abort — nothing to scan |
| An agent fails | Report partial results from other agents |
| Diff too large (> 5000 lines) | Warn user, scan only changed files (not full diff) |

## Design Principles

- **Parallel agents, distinct concerns.** Each agent has a clear lane — no overlap means no wasted work.
- **Confidence scoring.** Developers hate false positives. Low-confidence findings are deprioritized.
- **Actionable output.** Every finding includes a specific fix suggestion.
- **Fast enough to use.** Target < 60 seconds for a typical PR. Use sonnet for speed.
- **Non-blocking.** This is a quality check, not a gate. The user decides whether to act on findings.
