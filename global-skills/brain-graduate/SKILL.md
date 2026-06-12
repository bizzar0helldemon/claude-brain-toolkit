---
name: brain-graduate
description: Graduate learnings from the current session or project research into the brain vault's knowledge store — with reliability scoring and deduplication. Use --auto for passive post-work extraction (formerly /vault-documenter).
argument-hint: [--auto] [focus area]
---

# Brain Graduate — Knowledge Graduation

Promote valuable learnings from conversations, research, and project work into the brain vault's persistent knowledge store. Learnings accumulate over time and decay based on reliability scoring, so the brain stays current.

This skill has two modes:

- **Manual mode** (default) — the user invokes it deliberately; full enrichment walkthrough with user-confirmed reliability scoring
- **Auto mode** (`--auto`) — proactive extraction after significant work (commits, debugging sessions, session end); candidates are presented for one-tap confirmation and saved at `experimental` reliability. This replaces the old `/vault-documenter` skill.

**Usage**: `/brain-graduate [--auto] [focus area]`

**Examples**:
- `/brain-graduate` — scan conversation for graduatable learnings (manual mode)
- `/brain-graduate debugging` — focus on debugging-related learnings
- `/brain-graduate that API workaround` — graduate a specific discovery
- `/brain-graduate --auto` — passive scan after completed work; minimal questions, experimental reliability

## Paths

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}`
- **Learnings dir:** `{{SET_YOUR_BRAIN_PATH}}/learnings/`
- **Learnings index:** `{{SET_YOUR_BRAIN_PATH}}/learnings/_INDEX.md`
- **Daily notes:** `{{SET_YOUR_BRAIN_PATH}}/daily_notes/`

## What Makes a Good Learning

Not everything is worth graduating. Good learnings are:

- **Surprising** — you wouldn't have guessed this before the session
- **Reusable** — applies beyond this one project or conversation
- **Hard-won** — discovered through trial and error, not obvious from docs
- **Correctional** — fixed a misconception or common mistake

Bad candidates:
- Facts easily found in documentation
- Project-specific details (those belong in project notes)
- Temporary workarounds that will be obsolete soon

## Steps

### Step 1: Scan for Learnings

**If the user provided `$ARGUMENTS`**, focus the scan on that topic.
**Otherwise**, scan the full conversation for learning candidates.

**Sources to check:**

1. **Conversation** — corrections, surprises, "aha" moments, things that didn't work
2. **Project research** — if `.planning/research/` exists, scan for insights worth keeping
3. **Error patterns** — if `{{SET_YOUR_BRAIN_PATH}}/pattern-store.json` exists, check for high-encounter patterns that encode real knowledge

**Look for these learning types:**

| Type | Description | Example |
|------|-------------|---------|
| `correction` | Fixed a wrong assumption | "Python's `is` compares identity, not equality" |
| `discovery` | Found something non-obvious | "The API rate-limits per-key, not per-IP" |
| `technique` | A reusable approach that worked | "Use git worktrees for parallel ticket work" |
| `pitfall` | A trap to avoid | "Don't mock the database in integration tests" |
| `architecture` | A design insight | "Event sourcing fits this domain because..." |
| `performance` | A measured before/after improvement | "Switching to bulk insert reduced import time from 12s to 0.8s" |

**Signal strength guide** (especially important in `--auto` mode):

- **Strong signals (high confidence):** user correcting Claude ("no", "actually", "that's wrong"); Claude correcting itself; explicit surprise ("interesting", "didn't know that"); error → fix cycles; before/after performance measurements
- **Moderate signals:** non-obvious configuration that took multiple attempts; workarounds for framework/library limitations; patterns that worked first-try in a complex domain
- **Weak signals (skip unless user confirms):** standard coding patterns; well-documented API usage; simple bug fixes with obvious causes

**Present candidates:**
```
I found these learnings worth graduating:

1. **[Title]** (type: correction)
   {Brief description of what was learned}

2. **[Title]** (type: discovery)
   {Brief description}

Which would you like to graduate? (numbers, 'all', or describe something I missed)
```

### Step 2: Enrich Each Learning

**In `--auto` mode, skip the walkthrough:** infer all fields from conversation context, set `reliability: experimental` and `source: auto`, and show a compact summary for one-tap confirmation. Auto-extracted learnings need human validation (a later manual `/brain-graduate` re-review or natural re-encounter) to promote to `medium` or `high`. Never write without user confirmation, even in auto mode.

**In manual mode**, for each selected learning, walk through:

1. **Title** — concise, searchable name
2. **Type** — correction, discovery, technique, pitfall, or architecture
3. **Domain** — what area does this apply to? (e.g., python, git, api-design, testing)
4. **The learning** — clear statement of what's true (not what happened)
5. **Context** — how it was discovered (brief)
6. **Reliability** — how confident are you?
   - `high` — verified multiple times, well-understood
   - `medium` — worked once, seems right, needs more testing
   - `experimental` — promising but unverified
7. **Related** — any brain entries to cross-link
8. **Tags** — kebab-case tags for searchability

**Suggest answers based on the conversation. Let the user confirm or adjust.**

### Step 3: Check for Duplicates

Before saving, check existing learnings:

1. Read `{{SET_YOUR_BRAIN_PATH}}/learnings/_INDEX.md` (if it exists)
2. Use Grep to search existing learnings for similar titles or content
3. If a similar learning exists:
   > "This looks similar to [[Existing Learning]]. Want to update that entry instead of creating a new one?"

If updating, read the existing file and merge the new information.

### Step 4: Save

**4a. Create learnings directory if needed:**
```bash
mkdir -p "{{SET_YOUR_BRAIN_PATH}}/learnings"
```

**4b. Write the learning file:**

File: `{{SET_YOUR_BRAIN_PATH}}/learnings/{slug}.md`

```markdown
---
title: "{title}"
type: learning
learning_type: "{correction|discovery|technique|pitfall|architecture|performance}"
domain: "{domain}"
reliability: "{high|medium|experimental}"
source: "{conversation|research|error-pattern|auto}"
graduated: "{YYYY-MM-DD}"
last_validated: "{YYYY-MM-DD}"
tags: [{tags}]
---

# {title}

## What I Learned

{Clear statement of the learning — what is true, what to do or avoid}

## Context

{How this was discovered — brief, enough to understand the circumstances}

## Why It Matters

{When this knowledge is useful — what situation triggers it}

## Related

{Cross-links to other brain entries: [[projects]], [[patterns]], [[learnings]]}
```

**4c. Update or create the index:**

File: `{{SET_YOUR_BRAIN_PATH}}/learnings/_INDEX.md`

```markdown
---
title: "Learnings Index"
type: index
---

# Learnings

| Title | Type | Domain | Reliability | Graduated |
|-------|------|--------|-------------|-----------|
| [[Learning Title]] | correction | python | high | 2026-03-31 |
```

Add new row. If the index doesn't exist, create it with the header.

**4d. Append to daily note:**

```markdown
- {HH:MM} — Graduated learning: [[{title}]] (type: {type}, reliability: {reliability})
```

### Step 5: Summary

```
Graduated:

  [[{title}]] → learnings/{slug}.md (reliability: {reliability})
  [[{title}]] → learnings/{slug}.md (reliability: {reliability})

Total learnings: {N} across {M} domains
```

## Knowledge Health

Over time, learnings can become stale. The `last_validated` field tracks when a learning was last confirmed to still be true.

**Reliability decay heuristic:**
- `high` reliability learnings stay relevant for ~1 year
- `medium` reliability learnings stay relevant for ~6 months
- `experimental` learnings stay relevant for ~3 months

When reading learnings in future sessions, check the `last_validated` date. If it's past the decay window, the learning should be re-validated before acting on it.

To prune stale learnings, you can run:
> "Check my learnings for stale entries"

This will scan `learnings/` for entries past their decay window and suggest updates or removal.

## Proactive Triggers (`--auto` mode)

Hooks and other skills may suggest `--auto` mode at these moments:

- **After significant git commits** — the `post-tool-use.sh` hook detects commits; learnings that emerged in the work leading to the commit are prime candidates
- **At session end** — when the stop hook finds capturable content from debugging or research-heavy sessions
- **After `/brain-evolve`** — when stale or contradictory learnings are discovered, refresh the knowledge base with current understanding

## Error Handling

| Error | Action |
|-------|--------|
| No learnings found in conversation | Tell user, suggest running after a substantive session. In `--auto` mode: "No extractable learnings detected. This is normal for routine sessions." |
| BRAIN_PATH not set | Warn, suggest `/brain-setup` |
| learnings/ doesn't exist | Create it |
| Duplicate detected | Offer to merge into existing entry |
| User declines all candidates | "Got it — nothing captured." Exit gracefully. |

## Design Principles

- **Quality over quantity.** One well-articulated learning is better than five vague ones.
- **State what's true, not what happened.** Learnings should be reusable, not narrative.
- **Suggest, don't interrogate.** Pre-fill from conversation context.
- **Track reliability.** Not all learnings are equal — experimental discoveries shouldn't carry the same weight as battle-tested techniques.
- **Stay additive.** Never delete learnings automatically. Flag stale ones for human review.
