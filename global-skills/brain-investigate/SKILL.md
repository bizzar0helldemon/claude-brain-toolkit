---
name: brain-investigate
description: Structured debugging with hypothesis-driven investigation, 3-level diagnostic, and persistent investigation notes in the brain vault.
argument-hint: <bug description or error message>
---

# Brain Investigate — Structured Debugging

A systematic debugging workflow that uses hypothesis-driven investigation with a 3-level diagnostic framework. Investigation notes persist in the brain vault so findings survive context resets and can inform future debugging.

**Usage**: `/brain-investigate <description of the problem>`

**Examples**:
- `/brain-investigate auth tokens expire after 5 minutes instead of 1 hour`
- `/brain-investigate tests pass locally but fail in CI`
- `/brain-investigate the API returns 500 on POST /users but GET works fine`

## Paths

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}`
- **Investigations dir:** `{{SET_YOUR_BRAIN_PATH}}/investigations/`
- **Learnings dir:** `{{SET_YOUR_BRAIN_PATH}}/learnings/`
- **Daily notes:** `{{SET_YOUR_BRAIN_PATH}}/daily_notes/`

## The 3-Level Diagnostic

Every hypothesis is tested through three levels. Stop at the first level that fails — that's where the bug is.

| Level | Question | What it catches |
|-------|----------|-----------------|
| **EXISTS** | Does the component/function/config exist? | Missing files, deleted functions, typos in imports, missing env vars |
| **SUBSTANTIVE** | Is it correct? Does it do what we think? | Wrong logic, bad config values, incorrect types, stale data |
| **WIRED** | Is it connected? Is it actually called/used? | Dead code, broken import chains, middleware not registered, event not subscribed |

Most bugs live at the WIRED level — the code exists and looks correct, but it's not hooked up properly.

## Steps

### Step 1: Define the Problem

From the user's `$ARGUMENTS`, establish:

1. **Symptom** — what's happening (the observable behavior)
2. **Expected** — what should happen instead
3. **Scope** — which part of the system is affected
4. **Reproducibility** — always, sometimes, first-time-only?

Present your understanding:
```
Investigation: {slug}

Symptom: {what's happening}
Expected: {what should happen}
Scope: {affected area}

Does this capture the problem accurately?
```

Wait for confirmation before proceeding.

### Step 2: Create Investigation Note

Write to: `{{SET_YOUR_BRAIN_PATH}}/investigations/INV-{YYYY-MM-DD}-{slug}.md`

```markdown
---
title: "INV-{YYYY-MM-DD}-{slug}"
type: investigation
status: active
date: "{YYYY-MM-DD}"
project: "{repo-name}"
tags: [investigation, debugging]
---

# {Problem title}

## Symptom

{What's happening}

## Expected

{What should happen}

## Hypotheses

{Will be filled in as investigation progresses}

## Root Cause

{Will be filled in when found}

## Fix

{Will be filled in when resolved}

## Learnings

{Will be extracted after resolution}
```

Create `investigations/` directory if it doesn't exist.

### Step 3: Form Hypotheses

Based on the symptom, form 2-3 initial hypotheses. For each:

```
Hypothesis 1: {what might be causing this}
  Likelihood: {high|medium|low}
  Test: {what to check}
  Diagnostic level: {EXISTS|SUBSTANTIVE|WIRED}
```

Present all hypotheses and ask:
```
I have these hypotheses. Want to start investigating, adjust them, or add your own?
```

### Step 4: Investigate (Hypothesis Loop)

For each hypothesis, starting with the highest likelihood:

**4a. Test at the appropriate diagnostic level:**

**EXISTS check:**
- Does the file exist? (`Glob` for the file)
- Does the function exist? (`Grep` for the definition)
- Does the config exist? (`Read` the config file)
- Does the env var exist? (`echo $VAR`)

**SUBSTANTIVE check** (only if EXISTS passes):
- Is the logic correct? (Read the code, trace the logic)
- Are the values right? (Check config values, defaults, types)
- Is the data fresh? (Check timestamps, cache TTLs)

**WIRED check** (only if SUBSTANTIVE passes):
- Is it imported/required? (`Grep` for import statements)
- Is it called? (`Grep` for call sites)
- Is the middleware registered? (Check app setup)
- Is the event listener subscribed? (Check event wiring)
- Is the route mounted? (Check router setup)

**4b. Record evidence:**

After each test, record findings:
```
Hypothesis 1: {description}
  EXISTS: ✅ {function exists at path:line}
  SUBSTANTIVE: ✅ {logic looks correct}
  WIRED: ❌ {function is defined but never called — import exists in old file, not in refactored version}

  → FINDING: {concrete finding}
```

**4c. Update investigation note** with findings after each hypothesis test.

**4d. Evaluate:**
- If root cause found → proceed to Step 5
- If hypothesis disproven → move to next hypothesis
- If all hypotheses exhausted → form new hypotheses based on what you've learned

**Max 5 hypotheses** before checking in with the user:
```
I've tested 5 hypotheses without finding the root cause. Here's what I've ruled out:
{summary}

Want to continue with new hypotheses, or should we pair on this?
```

### Step 5: Root Cause Found

Present the root cause clearly:

```
Root Cause Found:

  {Clear explanation of what's wrong}

  Evidence:
  - {finding 1}
  - {finding 2}

  Diagnostic level: {EXISTS|SUBSTANTIVE|WIRED}

  Proposed fix:
  {What to change and where}

Apply this fix?
```

Wait for confirmation before making changes.

### Step 6: Apply Fix

After user confirms:
1. Apply the fix using Edit/Write tools
2. Run tests if available (`npm test`, `pytest`, etc.)
3. Verify the symptom is resolved

### Step 7: Update Investigation Note

Update `{{SET_YOUR_BRAIN_PATH}}/investigations/INV-{YYYY-MM-DD}-{slug}.md`:

- Set `status: resolved` in frontmatter
- Fill in the **Root Cause** section
- Fill in the **Fix** section with what was changed
- Fill in the **Hypotheses** section with all tested hypotheses and their results

### Step 8: Extract Learnings

After resolution, check if this investigation produced a reusable learning:

```
This investigation found: {root cause summary}

Is this worth graduating to a learning? This would help in future debugging sessions.
  1. Yes — graduate to learnings/
  2. No — investigation note is enough
```

If yes, create a learning following the same format as `/brain-graduate`:
- Type: usually `pitfall` or `discovery`
- Include: what went wrong, how to detect it, how to prevent it

### Step 9: Log and Summarize

**Append to daily note:**
```markdown
- {HH:MM} — Investigation resolved: {slug} — root cause: {one-line summary}
```

**Final summary:**
```
Investigation Complete: {slug}

  Root cause: {one-line summary}
  Fix: {what was changed}
  Diagnostic level: {level where bug was found}
  Hypotheses tested: {N} ({N} disproven, 1 confirmed)
  Note: investigations/INV-{YYYY-MM-DD}-{slug}.md
  Learning: {graduated / not graduated}
```

## Resuming an Investigation

If you need to resume an interrupted investigation:
> "Resume investigation INV-2026-03-31-auth-expiry"

Claude will read the investigation note and pick up from where hypotheses were last tested.

## Error Handling

| Error | Action |
|-------|--------|
| Problem is vague | Ask clarifying questions before forming hypotheses |
| Can't reproduce | Document reproduction attempts, ask user for more context |
| Fix doesn't resolve symptom | Reopen investigation, form new hypotheses |
| BRAIN_PATH not set | Continue without vault notes, warn user |
| investigations/ doesn't exist | Create it |

## Design Principles

- **Hypotheses before code.** Don't start changing things until you have a theory.
- **3-level diagnostic.** Always check EXISTS → SUBSTANTIVE → WIRED in order. Most people skip to SUBSTANTIVE and miss the simpler problems.
- **Record everything.** Negative results are valuable — knowing what it ISN'T narrows the search.
- **Max 5 before check-in.** Don't go down rabbit holes. If 5 hypotheses fail, regroup with the user.
- **Extract learnings.** The most valuable output of debugging isn't the fix — it's the knowledge of *why* it broke.
