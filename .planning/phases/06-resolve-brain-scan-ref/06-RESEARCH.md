# Phase 6: Resolve /brain-scan Reference - Research

**Researched:** 2026-03-21
**Domain:** Documentation cleanup / markdown text editing
**Confidence:** HIGH

## Summary

Phase 6 is a single-file text edit with no library dependencies, no shell scripting, and no deployment changes. The entire scope is: remove or correct specific references to `/brain-scan` inside `agents/brain-mode.md` so that brain-mode.md no longer lists `/brain-scan` as a brain-mode artifact it owns.

The problem is clear. The v1.0 milestone audit flagged `/brain-scan` as "referenced in brain-mode.md but no artifact exists anywhere" (severity: Medium). The audit's framing was slightly imprecise — a `/brain-scan` skill does exist at `.claude/skills/brain-scan/SKILL.md` — but the distinction matters: `/brain-scan` is a general-purpose vault skill that operates on `$BRAIN_PATH`, not a brain-mode-specific hook. It was pre-existing toolkit infrastructure, not a brain-mode deliverable. brain-mode.md treats it as one of its own slash commands in its "Available Skills" list, which is misleading.

The success criterion is narrow and unambiguous: "brain-mode.md does not reference /brain-scan as a brain-mode artifact." The fix is purely editorial — edit the text of brain-mode.md. No scripts, no deployments, no tests, no packages.

**Primary recommendation:** Remove the `/brain-scan` entry from the "Available Skills" list in `agents/brain-mode.md` and update the two prose references that suggest the user run `/brain-scan` to reword them appropriately (either remove them, or clarify that `/brain-scan` is a general toolkit skill available outside brain-mode sessions).

## Standard Stack

No libraries, packages, or tooling are required for this phase. The work is:

- Read `agents/brain-mode.md` with the Read tool
- Edit `agents/brain-mode.md` with the Edit tool
- Verify the edit with Grep

No `npm install`, no scripts, no deployment.

## Architecture Patterns

### Current State of brain-mode.md

Three locations in `agents/brain-mode.md` reference `/brain-scan`:

**Location 1 — Prose reference (line 54):**
```
When the user asks about past work, consult the vault context injected at session start.
If the relevant entry isn't there, suggest running `/brain-scan` to catalog the current project.
```

**Location 2 — Prose reference (lines 65-68):**
```
If vault context loaded successfully but shows 0 project entries and 0 pitfalls, mention once:
> "Your vault is empty. Run `/brain-scan` to catalog this project and start building context."
```

**Location 3 — Available Skills list (line 78):**
```
- `/brain-scan` — Catalog the current project into the vault
```

### What `/brain-scan` Actually Is

`/brain-scan` exists at `.claude/skills/brain-scan/SKILL.md`. It is a general-purpose vault skill that:
- Scans a project directory for `CLAUDE.md` and `MEMORY.md` files
- Generates project summaries following `brain-scan-templates.md`
- Updates `projects/`, `archive/`, and portfolio files in `$BRAIN_PATH`

It is NOT a brain-mode-specific hook. It predates brain-mode. It operates on `$BRAIN_PATH` (the vault), not on Claude Code hook lifecycle events. It is available to any Claude Code session where the skill is installed — brain-mode does not own or invoke it.

### Fix Pattern: Distinguish Toolkit Skills from Brain-Mode Artifacts

brain-mode.md's "Available Skills" section documents slash commands that brain-mode sessions can invoke. The correct way to handle `/brain-scan` depends on whether it is installed in the user's `~/.claude/` environment (which setup.sh does not currently deploy it to).

There are two valid resolutions:

**Option A — Remove the reference entirely:**
Drop `/brain-scan` from the Available Skills list. Remove or reword the two prose suggestions. This is cleanest if `/brain-scan` is not guaranteed to be available in brain-mode sessions.

**Option B — Clarify the reference:**
Keep the prose suggestions (they're useful guidance) but reword them to say "use `/brain-scan` from your toolkit if you have it installed" rather than implying it's a brain-mode command. Remove it from the Available Skills list since that list implies brain-mode ownership.

The success criterion ("brain-mode.md does not reference /brain-scan as a brain-mode artifact") is satisfied by either option. Option A is simpler and produces a cleaner document. Option B preserves useful user guidance.

**Recommendation: Option A.** Remove all three references. The vault-empty state guidance is still covered by session-start context injection (which surfaces 0 entries). The prose suggestions add marginal value and the Available Skills list should be authoritative — if the skill isn't deployed by setup.sh, it shouldn't be listed.

### Anti-Patterns to Avoid

- **Over-engineering the fix:** Do not deploy `/brain-scan` via setup.sh as a workaround — that's a different phase with different scope. This phase is editorial only.
- **Removing too much:** Only remove the three `/brain-scan` references. Do not restructure or rewrite the Available Skills section or other prose.
- **Introducing new claims:** Do not add `/brain-scan` to a "toolkit-only skills" section or similar. The success criterion is removal, not replacement.

## Don't Hand-Roll

No custom tooling needed. The Edit tool handles targeted text replacement in markdown.

## Common Pitfalls

### Pitfall 1: Confusing the audit finding with the actual state
**What goes wrong:** The audit said "/brain-scan referenced in brain-mode.md but no artifact exists anywhere" — but `.claude/skills/brain-scan/SKILL.md` does exist. Treating this as "the skill is missing, build it" would be wrong.
**Why it happens:** The audit was written before the full skill tree was checked, or was referring to the fact that setup.sh does not deploy the skill.
**How to avoid:** The ROADMAP.md clarifies the success criterion precisely: "brain-mode.md does not reference /brain-scan as a brain-mode artifact." The fix is editorial, not implementation.
**Warning signs:** If the plan proposes creating new files or updating setup.sh, scope has been exceeded.

### Pitfall 2: Removing the wrong references
**What goes wrong:** Removing `brain-scan-templates.md` references instead of `/brain-scan` command references.
**Why it happens:** `brain-scan` appears in many contexts — `brain-scan-templates.md` is a completely separate, valid artifact that should not be touched.
**How to avoid:** Target only occurrences of `/brain-scan` (the slash command) in `agents/brain-mode.md`. Do not grep-replace `brain-scan` broadly.
**Warning signs:** If the edit touches `brain-scan-templates.md` references or any file other than `agents/brain-mode.md`.

### Pitfall 3: Touching files outside scope
**What goes wrong:** Updating `README.md`, `onboarding-kit/`, or other docs that also reference `/brain-scan`.
**Why it happens:** Grep reveals many files reference `/brain-scan` — it's tempting to clean them all.
**How to avoid:** Scope is strictly `agents/brain-mode.md`. Other files are out of scope for this phase.
**Warning signs:** Any edit to a file other than `agents/brain-mode.md`.

## Code Examples

### Exact text to remove/change

**Current Available Skills list (lines 70-79 of brain-mode.md):**
```
## Available Skills

These slash commands are available in brain-mode sessions:

- `/brain-capture` — Extract patterns, prompts, and lessons from the current conversation
- `/daily-note` — Log a journal entry to `daily_notes/`
- `/brain-audit` — Run a vault health check (stale entries, missing indexes, broken links)
- `/brain-add-pattern` -- Add an error pattern and its solution to the pattern store for automatic future recognition
- `/brain-scan` — Catalog the current project into the vault
- `/brain-setup` — First-time onboarding wizard: configure BRAIN_PATH and create the vault directory
```

**After fix (remove the `/brain-scan` line):**
```
## Available Skills

These slash commands are available in brain-mode sessions:

- `/brain-capture` — Extract patterns, prompts, and lessons from the current conversation
- `/daily-note` — Log a journal entry to `daily_notes/`
- `/brain-audit` — Run a vault health check (stale entries, missing indexes, broken links)
- `/brain-add-pattern` -- Add an error pattern and its solution to the pattern store for automatic future recognition
- `/brain-setup` — First-time onboarding wizard: configure BRAIN_PATH and create the vault directory
```

**Current prose (line 54):**
```
If the relevant entry isn't there, suggest running `/brain-scan` to catalog the current project.
```
**After fix:** Remove the sentence. The clause before it stands alone.

**Current prose (lines 65-68):**
```
> "Your vault is empty. Run `/brain-scan` to catalog this project and start building context."
```
**After fix:** Change the prompt to not reference `/brain-scan`:
```
> "Your vault is empty. Use `/brain-capture` after your first session to start building context."
```
This preserves the "vault is empty" guidance while pointing to a command that IS in the Available Skills list.

## State of the Art

This phase involves no technology choices. It is markdown text editing.

| Old State | New State | Impact |
|-----------|-----------|--------|
| brain-mode.md lists `/brain-scan` as an owned brain-mode skill | brain-mode.md lists only skills that brain-mode owns and that are deployed by setup.sh | Milestone audit integration gap closed; Available Skills list is accurate |

## Open Questions

No unresolved questions. The scope, the target file, the three exact locations, and the fix strategy are all fully determined from the audit and codebase inspection.

## Sources

### Primary (HIGH confidence)
- Direct file read of `agents/brain-mode.md` — confirmed three `/brain-scan` references at lines 54, 66, and 78
- Direct file read of `.claude/skills/brain-scan/SKILL.md` — confirmed the skill exists as a general-purpose vault tool, not a brain-mode artifact
- Direct file read of `.planning/v1.0-MILESTONE-AUDIT.md` — confirmed gap description and severity (Medium)
- Direct file read of `.planning/ROADMAP.md` — confirmed Phase 6 success criterion verbatim

### Secondary (MEDIUM confidence)
- Grep across all repo files for `brain-scan` pattern — confirmed scope: only `agents/brain-mode.md` is in scope; all other references are in files outside this phase's boundary

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no external dependencies; pure text editing
- Architecture: HIGH — three exact locations identified in the target file
- Pitfalls: HIGH — scope is narrow enough that pitfalls are enumerable and verified from the file

**Research date:** 2026-03-21
**Valid until:** Stable indefinitely — this is a static file with no external dependencies
