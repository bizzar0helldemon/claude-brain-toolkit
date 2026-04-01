---
name: brain-evolve
description: Self-improvement cycle — audit vault and toolkit with parallel agents, score findings on 5 axes, review proposals inline.
argument-hint: [--dry-run | --vault-only | --toolkit-only]
---

# Brain Evolve — Self-Improvement Cycle

Run a structured introspection cycle over your brain vault and toolkit. Three auditor agents examine the system in parallel, findings are scored on 5 axes, and you review proposals inline.

**Usage**: `/brain-evolve [flags]`

**Examples**:
- `/brain-evolve` — full cycle (all 3 auditors)
- `/brain-evolve --dry-run` — scan and report findings without writing proposals
- `/brain-evolve --vault-only` — only audit the vault, skip toolkit
- `/brain-evolve --toolkit-only` — only audit the toolkit, skip vault

## Paths

- **Brain root:** `$BRAIN_PATH`
- **Proposals:** `$BRAIN_PATH/evolution/proposals/`
- **Synthesis:** `$BRAIN_PATH/evolution/synthesis/`
- **Scratch:** `$BRAIN_PATH/evolution/scratch/` (temporary, cleaned after synthesis)
- **Daily notes:** `$BRAIN_PATH/daily_notes/`

---

## Phase 1: Preflight

1. **Validate environment:**
   - Check `$BRAIN_PATH` is set and the directory exists
   - If not: warn and abort — "BRAIN_PATH is not set. Run `/brain-setup` first."

2. **Check for pending proposals:**
   - Glob `$BRAIN_PATH/evolution/proposals/EVO-*.md`
   - Count files where frontmatter `status: proposed`
   - If any pending: report count — "You have {N} pending proposals from a prior cycle. Review them first or continue to generate new ones?"

3. **Parse arguments:**
   - `--dry-run` — set DRY_RUN=true (run auditors, show findings, skip proposal/synthesis writes)
   - `--vault-only` — only launch vault-auditor
   - `--toolkit-only` — only launch toolkit-auditor
   - No flags — launch all 3 auditors

4. **Create directories:**
   ```bash
   mkdir -p "$BRAIN_PATH/evolution/proposals"
   mkdir -p "$BRAIN_PATH/evolution/synthesis"
   mkdir -p "$BRAIN_PATH/evolution/scratch"
   ```

5. **Display launch summary:**
   ```
   🧠 Brain Evolve — starting cycle

   Mode: {full | vault-only | toolkit-only | dry-run}
   Auditors: {vault-auditor, toolkit-auditor, rethink-auditor}
   Vault: $BRAIN_PATH
   ```

---

## Phase 2: Internal Synthesis

Launch auditor agents **in parallel** using the Agent tool. Use `model: sonnet` for speed. Each agent writes its findings to `$BRAIN_PATH/evolution/scratch/`.

### Auditor Roster

| Agent | Focus | Examines |
|-------|-------|----------|
| `vault-auditor` | Vault health & freshness | `$BRAIN_PATH/` — all subdirectories |
| `toolkit-auditor` | Toolkit quality & consistency | Toolkit repo files: hooks, skills, agents, settings |
| `rethink-auditor` | Simplification & pruning | Both vault and toolkit — looks for things to REMOVE or MERGE |

### Auditor Prompt Template

For each auditor, construct the Agent prompt:

```
You are a [{agent_name}] performing an internal audit of the Brain Mode system.

Your focus: [{focus_description}]

Analyze files using Read, Grep, and Glob tools. Produce a structured findings report:

## Summary
One paragraph executive summary.

## Findings
For each issue (up to 10 max):
### {finding_title}
- **severity**: critical | high | medium | low
- **category**: {category}
- **location**: {file_path}
- **description**: What is wrong and why it matters.
- **proposed_fix**: Specific actionable change (1-3 sentences).
- **effort**: low (<1h) | medium (1-4h) | high (>4h)

## Metrics
Quantitative measurements where possible.

Write your report to: $BRAIN_PATH/evolution/scratch/synth-{agent_name}-{date}.md

IMPORTANT: Stay within 6000 tokens. Be concise. Return findings as markdown.
```

### Vault Auditor — Specific Checks

- **Stale learnings**: Read `$BRAIN_PATH/learnings/` files. Check `last_validated` date against decay windows:
  - `high` reliability → stale after 1 year
  - `medium` reliability → stale after 6 months
  - `experimental` reliability → stale after 3 months
- **Orphaned entries**: Files in `learnings/`, `prompts/`, `projects/` not referenced in their `_INDEX.md`
- **Index drift**: Entries listed in `_INDEX.md` but missing on disk
- **Empty files**: Files with no content beyond frontmatter
- **Frontmatter gaps**: Missing required fields (title, type, tags)
- **Pattern store bloat**: If `$BRAIN_PATH/pattern-store.json` exists, check for patterns with 0 encounters
- **Stale handoffs**: Files in `handoffs/` older than 30 days

Categories: `vault-health`, `freshness`, `index-integrity`, `frontmatter`

### Toolkit Auditor — Specific Checks

- **Hook/file alignment**: Compare hooks registered in `settings.json` with actual files in `hooks/`
- **Placeholder contamination**: Search deployed skill files (under `~/.claude/`) for `{{SET_YOUR_BRAIN_PATH}}` — these should have been replaced during setup. NOTE: Placeholders in the source repo (`claude-brain-toolkit/`) are expected and should NOT be flagged.
- **Agent definition accuracy**: Check that skills listed in `agents/brain-mode.md` match actual skill directories in `global-skills/`
- **Error log patterns**: If `$BRAIN_PATH/.brain-errors.log` exists, summarize recurring errors
- **Settings consistency**: Verify `settings.json` env vars, agent name, and hook paths are valid

Categories: `hook-integrity`, `config`, `placeholder`, `skill-registration`

### Rethink Auditor — Specific Checks (6 Rs Framework)

The Rethink auditor challenges whether existing things should REMAIN. Unlike other auditors that find things to fix or add, this one finds things to simplify, merge, or remove.

**Investigation framework (adapted from Ars Contexta 6 Rs):**

1. **Review** — Read all skill SKILL.md files. For each:
   - Is this skill still used? (Check for invocation evidence in handoffs, daily notes)
   - Does it overlap significantly with another skill?
   - Was it added reactively and is now over-protective?

2. **Re-evaluate** — Read learnings and patterns:
   - Are graduated learnings still accurate?
   - Do any learnings contradict each other?
   - Are there patterns that have never matched (0 encounters)?

3. **Reduce** — Look for:
   - Skills with overlapping functionality that could be merged
   - Hook logic that could be simplified
   - Vault sections that duplicate each other

4. **Remove** — Check for:
   - Empty vault directories
   - Stale handoffs older than 30 days
   - Learnings that have fully decayed without revalidation
   - Unused index entries

5. **Rethink** — Identify:
   - Complexity that exists for historical reasons
   - Over-engineering in hook or skill design
   - Rules/patterns that constrain without measurable benefit

6. **Reshape** — Propose:
   - Merge 2 skills into 1
   - Delete unused vault sections
   - Simplify hook chains
   - Relax overly strict validation

**Key constraints:**
- Focus on REMOVALS and SIMPLIFICATIONS, not additions
- Every proposal must include evidence (usage data, file dates, overlap analysis)
- Do not propose removing safety-critical hooks or capture mechanisms
- Findings should be actionable, not philosophical

Categories: `simplification`, `removal`, `merge`, `complexity`

### After All Auditors Complete

1. **Read all scratch files** from `$BRAIN_PATH/evolution/scratch/`
2. **Synthesize** into `$BRAIN_PATH/evolution/synthesis/SYNTH-{YYYY-MM-DD}.md`:

```markdown
---
date: {YYYY-MM-DD}
type: synthesis
sources: [vault-auditor, toolkit-auditor, rethink-auditor]
total_findings: {N}
critical_findings: {N}
high_findings: {N}
tags: [evolution, synthesis]
---

# Brain Evolution Synthesis: {YYYY-MM-DD}

## Executive Summary
{2-3 sentence summary of the most important findings}

## Critical / High Findings

### {finding_title}
- **Severity**: {severity}
- **Auditor**: {agent_name}
- **Location**: {location}
- **Description**: {description}
- **Fix**: {proposed_fix}
- **Effort**: {effort}

## Medium / Low Findings
- [{severity}] {finding_title} — {location} — {proposed_fix}

## Metrics Summary

| Auditor | Findings | Critical | High | Medium | Low |
|---------|----------|----------|------|--------|-----|
| vault-auditor | {N} | {N} | {N} | {N} | {N} |
| toolkit-auditor | {N} | {N} | {N} | {N} | {N} |
| rethink-auditor | {N} | {N} | {N} | {N} | {N} |
| **Total** | {N} | {N} | {N} | {N} | {N} |
```

3. **Clean up scratch**: Remove `$BRAIN_PATH/evolution/scratch/synth-*.md` files after synthesis is written.

4. **If `--dry-run`**: Display the synthesis summary and stop. Do not proceed to scoring or proposals.

---

## Phase 3: Evaluation Scoring

Score each critical or high finding on 5 axes. Medium/low findings are noted but not scored into proposals.

### 5-Axis Scoring Model

| Axis | Scale | What It Measures |
|------|-------|-----------------|
| **Impact** | 1–5 | How much does this improve the system? |
| **Effort** | 1–5 | How hard to implement? (1=easy, 5=very hard) |
| **Risk** | 1–5 | What could go wrong? (1=safe, 5=dangerous) |
| **Urgency** | 1–5 | How soon should this be done? |
| **Alignment** | 1–5 | How well does it fit brain-mode's direction? |

**Total** = Impact + (6 − Effort) + (6 − Risk) + Urgency + Alignment

Effort and Risk are **inverted**: lower effort → higher score, lower risk → higher score.

**Maximum**: 25 | **Auto-reject threshold**: 10

### Scoring Rubric

**Impact**:
- 5 = Directly removes friction from daily workflow or closes a data integrity gap
- 4 = Significant improvement to a frequently-used feature
- 3 = Moderate improvement to an occasionally-used feature
- 2 = Minor improvement, limited reach
- 1 = Cosmetic or negligible

**Effort** (inverted in total):
- 1 = <1 hour
- 2 = <4 hours
- 3 = 1-2 days
- 4 = 2-5 days
- 5 = >1 week

**Risk** (inverted in total):
- 1 = Read-only, no side effects
- 2 = Documentation or config only
- 3 = Isolated change, easy rollback
- 4 = Could break a secondary feature
- 5 = Could break core vault or hook pipeline

**Urgency**:
- 5 = Data integrity issue or broken feature
- 4 = Active friction affecting daily work
- 3 = Known issue, tolerable for now
- 2 = Nice-to-have improvement
- 1 = Future-state aspiration

**Alignment**:
- 5 = Directly serves brain-mode goals (knowledge compounding, capture quality, vault health)
- 4 = Supports goals indirectly
- 3 = Neutral fit
- 2 = Slight direction mismatch
- 1 = Conflicts with brain-mode direction

### Scoring Step

For each critical/high finding from the synthesis:

1. Assign scores on all 5 axes with brief rationale
2. Compute total
3. If total < 10: mark as auto-rejected, do not create proposal
4. If total ≥ 10: write proposal file

### Proposal File Format

File: `$BRAIN_PATH/evolution/proposals/EVO-{YYYY-MM-DD}-{N}.md`

```markdown
---
id: "EVO-{YYYY-MM-DD}-{N}"
category: "{vault-health|freshness|index-integrity|hook-integrity|config|simplification|removal|merge}"
source_auditor: "{vault-auditor|toolkit-auditor|rethink-auditor}"
status: proposed
score_impact: {N}
score_effort: {N}
score_risk: {N}
score_urgency: {N}
score_alignment: {N}
score_total: {N}
created: "{YYYY-MM-DD}"
tags: [evolution, proposal]
---

# {finding_title}

## What Was Found
{description}

## Why It Matters
{impact explanation}

## Suggested Fix
{actionable proposal}

## Location
{file path or vault area}

## Scoring

| Axis | Score | Rationale |
|------|-------|-----------|
| Impact | {N}/5 | {rationale} |
| Effort | {N}/5 | {rationale} |
| Risk | {N}/5 | {rationale} |
| Urgency | {N}/5 | {rationale} |
| Alignment | {N}/5 | {rationale} |
| **Total** | **{N}/25** | |
```

---

## Phase 4: Summary & Inline Review

### 4a. Present Results

Display a ranked summary of all proposals:

```
🧠 Brain Evolve — cycle complete

Auditors: {N} ran | Findings: {N} total | Proposals: {N} scored | Auto-rejected: {N}

## Proposals (ranked by score)

1. [EVO-2026-04-01-1] (21/25) — {title}
   Category: {category} | Auditor: {source_auditor} | Effort: {effort}

2. [EVO-2026-04-01-2] (18/25) — {title}
   Category: {category} | Auditor: {source_auditor} | Effort: {effort}

3. [EVO-2026-04-01-3] (14/25) — {title}
   Category: {category} | Auditor: {source_auditor} | Effort: {effort}
```

### 4b. Inline Review

For each proposal (highest score first), present:

```
### EVO-2026-04-01-1 — {title} (21/25)

{What was found — 2-3 sentences}

Suggested fix: {fix summary}

→ Approve / Reject / Defer?
```

Wait for the user's response on each proposal before proceeding to the next.

- **Approve**: Set `status: approved` in frontmatter. Note for implementation.
- **Reject**: Set `status: rejected` in frontmatter. Add `reject_reason` from user.
- **Defer**: Leave `status: proposed`. Will appear in next cycle's preflight count.

### 4c. Write Daily Note Entry

Append to `$BRAIN_PATH/daily_notes/{YYYY-MM-DD}.md`:

```markdown
## Brain Evolution Cycle

- Auditors: {N} | Findings: {N} total
- Proposals scored: {N} | Auto-rejected: {N}
- Approved: {N} | Rejected: {N} | Deferred: {N}
- Top proposal: [[EVO-{date}-{N}]] ({score}/25) — {title}
```

### 4d. Final Summary

```
🧠 Evolution cycle complete.

  Approved: {N} proposals
  Rejected: {N} proposals
  Deferred: {N} proposals

Approved proposals are ready for implementation.
```

---

## Error Handling

| Error | Action |
|-------|--------|
| `BRAIN_PATH` not set | Abort with setup instructions |
| An auditor agent fails | Log error, continue with remaining auditors |
| Synthesis write fails | Write to scratch dir as fallback, warn user |
| No critical/high findings | Report "vault and toolkit look healthy", skip scoring |
| Scoring produces 0 proposals (all auto-rejected) | Report "all findings scored below threshold", show medium/low summary |

**Never block the pipeline** — partial results are better than no results.

---

## Relationship to Other Skills

| Skill | Relationship |
|-------|-------------|
| `brain-audit` | Deep vault health check (fix now). `brain-evolve` vault-auditor is a lighter survey (plan improvements). Complementary. |
| `brain-graduate` | May be invoked after evolution discovers stale learnings needing revalidation. |
| `brain-capture` | Not related — captures from conversations, not self-reflection. |
| `brain-investigate` | Not related — for debugging, not systematic improvement. |

## Design Principles

- **Systematic, not reactive.** Evolution looks at the whole system, not just the current problem.
- **Score before acting.** Every proposal earns its place through 5-axis evaluation.
- **Human in the loop.** Nothing is implemented without explicit approval.
- **Simplification bias.** The rethink auditor is the most important — removing complexity is harder and more valuable than adding features.
- **Partial success is fine.** If one auditor fails, the others still produce value.
