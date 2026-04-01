---
name: vault-documenter
description: Auto-extract learnings from completed work — scans conversation for corrections, discoveries, techniques, and pitfalls without manual /brain-capture.
argument-hint: [focus area]
---

# Vault Documenter — Passive Learning Extraction

Automatically scans completed work for learnings and writes them to the vault. Unlike `/brain-capture` (which extracts prompt patterns) or `/brain-graduate` (which requires manual invocation), the vault documenter runs proactively after significant work and focuses on **knowledge that would otherwise be lost** when the session ends.

**Usage**: `/vault-documenter [focus area]`

**Examples**:
- `/vault-documenter` — scan full conversation for extractable learnings
- `/vault-documenter that auth fix` — focus extraction on a specific topic

## Paths

- **Brain root:** `$BRAIN_PATH`
- **Learnings dir:** `$BRAIN_PATH/learnings/`
- **Learnings index:** `$BRAIN_PATH/learnings/_INDEX.md`
- **Daily notes:** `$BRAIN_PATH/daily_notes/`

## What It Extracts

The documenter looks for five categories of implicit knowledge:

| Category | Signal | Example |
|----------|--------|---------|
| **Corrections** | User said "no, actually..." or Claude corrected its own assumption | "Python's `is` compares identity, `==` compares equality" |
| **Discoveries** | Something non-obvious was found during debugging/research | "The API rate-limits per-key, not per-IP" |
| **Techniques** | A reusable approach that worked well | "Use git worktrees for parallel ticket work" |
| **Pitfalls** | A trap was encountered and worked around | "Don't mock the database in integration tests" |
| **Performance** | A before/after improvement was measured | "Switching to bulk insert reduced import time from 12s to 0.8s" |

### What NOT to Extract

- Facts easily found in documentation
- Project-specific implementation details (those belong in project notes)
- Temporary workarounds with known expiry
- Things the user explicitly said they don't want captured

## Steps

### Step 1: Scan Conversation

Analyze the conversation for extractable learnings. Look for these signals:

**Strong signals (high confidence):**
- User correcting Claude: "no", "actually", "that's wrong"
- Claude correcting itself: "I was wrong about...", "actually..."
- Explicit surprise: "interesting", "didn't know that", "huh"
- Error → fix cycles: a command failed, was diagnosed, and fixed
- Performance comparisons: before/after measurements

**Moderate signals (medium confidence):**
- Non-obvious configuration that took multiple attempts
- Workarounds for framework/library limitations
- Patterns that worked on the first try in a complex domain

**Weak signals (skip unless user confirms):**
- Standard coding patterns
- Well-documented API usage
- Simple bug fixes with obvious causes

### Step 2: Present Candidates

```
Vault Documenter — found {N} learnings worth capturing:

1. **{Title}** (type: {correction|discovery|technique|pitfall|performance})
   {One-line summary}

2. **{Title}** (type: {type})
   {One-line summary}

Capture all, or select specific numbers? (You can also skip with 'none')
```

**Wait for user confirmation.** The documenter suggests but never writes without consent. This is the key difference from a fully automatic system — the user stays in control of what enters their vault.

### Step 3: Write Learnings

For each confirmed learning, write using the `brain-graduate` format:

**File:** `$BRAIN_PATH/learnings/{slug}.md`

```markdown
---
title: "{title}"
type: learning
learning_type: "{correction|discovery|technique|pitfall|performance}"
domain: "{domain}"
reliability: "experimental"
source: "vault-documenter"
graduated: "{YYYY-MM-DD}"
last_validated: "{YYYY-MM-DD}"
tags: [{tags}]
---

# {title}

## What I Learned

{Clear statement of the learning}

## Context

{How this was discovered — brief}

## Why It Matters

{When this knowledge is useful}

## Related

{Cross-links to other brain entries}
```

**Key:** All auto-extracted learnings start at `reliability: experimental`. They need human validation (via `/brain-graduate` re-review or natural re-encounter) to promote to `medium` or `high`.

### Step 4: Update Index

Add each new learning to `$BRAIN_PATH/learnings/_INDEX.md`:

```markdown
| [[{Title}]] | {type} | {domain} | experimental | {YYYY-MM-DD} |
```

### Step 5: Daily Note Entry

Append to `$BRAIN_PATH/daily_notes/{YYYY-MM-DD}.md`:

```markdown
- {HH:MM} — Vault documenter: captured {N} learnings — {titles}
```

### Step 6: Deduplication

Before writing any learning:

1. Read `$BRAIN_PATH/learnings/_INDEX.md`
2. Grep existing learnings for similar titles or content
3. If duplicate found: offer to update the existing entry instead
4. If near-duplicate: show both and let user decide

## Trigger Points (Proactive Mode)

The vault documenter can be triggered proactively by hooks at these moments:

### After Significant Git Commits

The existing `post-tool-use.sh` hook detects git commits. After the commit capture prompt, the documenter can scan for learnings that emerged during the work leading to that commit.

**Integration:** Add a secondary suggestion in the post-tool-use hook:
> "A git commit was detected. Run `/brain-capture` to capture patterns, or `/vault-documenter` to extract learnings from this work session."

### At Session End

The stop hook (`stop.sh`) checks for capturable content. Extend to suggest vault-documenter when significant debugging or research occurred:
> "This session included {N} error→fix cycles. Run `/vault-documenter` to capture what you learned."

### After Brain-Evolve

When `/brain-evolve` discovers stale or contradictory learnings, suggest running vault-documenter to refresh the knowledge base with current understanding.

## Error Handling

| Error | Action |
|-------|--------|
| No learnings found | "No extractable learnings detected. This is normal for routine sessions." |
| `BRAIN_PATH` not set | Warn, suggest `/brain-setup` |
| `learnings/` doesn't exist | Create it |
| Duplicate detected | Offer to merge |
| User declines all candidates | "Got it — nothing captured." Exit gracefully. |

## Relationship to Other Skills

| Skill | Vault Documenter's Role |
|-------|------------------------|
| `brain-capture` | Captures prompt patterns and interaction techniques. Vault documenter captures knowledge learnings. Different extraction targets. |
| `brain-graduate` | Promotes learnings with reliability scoring. Vault documenter creates `experimental` learnings that brain-graduate can later promote. |
| `brain-evolve` | May trigger vault-documenter when it finds stale learnings. |
| `brain-investigate` | Investigations produce findings. Vault documenter extracts the reusable knowledge from those findings. |

## Design Principles

- **Suggest, don't auto-write.** Always present candidates for user confirmation.
- **Experimental by default.** Auto-extracted learnings start at lowest reliability.
- **Complement, don't replace.** Works alongside brain-capture and brain-graduate, not instead of.
- **Signal over noise.** Better to miss a learning than to create a low-quality one.
- **Reuse formats.** Uses brain-graduate's file format and index conventions — no new schemas.
