---
name: brain-synthesize
description: Create or update living knowledge pages that synthesize learnings across sessions and projects. Turns event logs into compounding knowledge — concept pages, entity pages, and cross-project synthesis.
argument-hint: "[topic]" or "all" to auto-detect synthesis candidates
---

# Brain Synthesize — Compounding Knowledge Pages

You are creating or updating **synthesis pages** in the Brain vault. These are living documents that accumulate knowledge about a concept, tool, pattern, or entity across all sessions and projects — unlike daily notes which record events, synthesis pages record **what we know**.

## Philosophy

> "The wiki is a persistent, compounding artifact. The cross-references are already there.
> The contradictions have already been flagged. The synthesis already reflects everything
> you've read." — Karpathy, LLM Wiki

Daily notes and captures record *what happened*. Synthesis pages record *what we know*.
The difference:

| Daily Note | Synthesis Page |
|------------|---------------|
| "2026-04-07: Replaced Playwright with curl_cffi for eBay scraping" | "eBay Scraping: curl_cffi with TLS fingerprinting is the only reliable method. Playwright gets detected. Rate limit is IP-based, ~50 req before block..." |
| Event log — one date, one session | Living document — updated across sessions |
| Append-only | Revised and refined |

## Vault Location

- **Brain root:** `$BRAIN_PATH` (read from environment)
- **Synthesis directory:** `$BRAIN_PATH/synthesis/`
- **Synthesis index:** `$BRAIN_PATH/synthesis/_INDEX.md`

## Process

### Phase 0: Determine Scope

Parse `$ARGUMENTS`:

- **Specific topic** (e.g., `/brain-synthesize eBay scraping`) — create/update one synthesis page
- **"all"** or no arguments — scan vault for synthesis candidates (see Auto-Detection below)

### Phase 1: Gather Source Material

For the target topic, search the vault exhaustively:

1. **Search daily notes** — Grep for the topic across `$BRAIN_PATH/daily_notes/`
2. **Search captures** — Grep across `$BRAIN_PATH/brain-mode/capture-*.md`
3. **Search project files** — Grep across `$BRAIN_PATH/projects/`
4. **Search pattern store** — Check `$BRAIN_PATH/brain-mode/pattern-store.json` for related error patterns
5. **Search existing synthesis** — Check if a synthesis page already exists for this topic
6. **Use brain-search if available** — Run `python3 tools/brain-search.py "topic" --limit 20 --json` for broader matches

Read the full content of every matching file. Build a complete picture of what the vault knows about this topic.

### Phase 2: Analyze & Structure

Organize the gathered knowledge into:

1. **Core knowledge** — What do we definitively know? Facts, proven approaches, confirmed decisions.
2. **Patterns** — Recurring themes across sessions. "Every time we try X, Y happens."
3. **Evolution** — How has understanding changed over time? What did we believe before that we've revised?
4. **Contradictions** — Are there conflicting claims across sessions? Flag them explicitly.
5. **Gaps** — What questions remain unanswered? What should we investigate next?
6. **Cross-references** — What other topics, projects, or concepts connect to this one?

### Phase 3: Write or Update the Synthesis Page

#### If creating a new page:

Create `$BRAIN_PATH/synthesis/[topic-slug].md` using this template:

```markdown
---
title: "[Topic Name]"
type: synthesis
tags: [synthesis, relevant-tag-1, relevant-tag-2]
projects: [Project-1, Project-2]
created: YYYY-MM-DD
last-synthesized: YYYY-MM-DD
sources: N
status: active
---

# [Topic Name]

> **One-line summary:** [The single most important thing to know about this topic]

## What We Know

[Core knowledge — proven facts, confirmed approaches, battle-tested decisions.
Write in present tense. This is the "current truth" section.]

## Key Patterns

- **[Pattern name]** — [Description of the recurring pattern with evidence]
- **[Pattern name]** — [Description]

## Evolution

| Date | What Changed | Source |
|------|-------------|--------|
| YYYY-MM-DD | [What we learned or revised] | [[source-note]] |
| YYYY-MM-DD | [Earlier understanding] | [[source-note]] |

## Contradictions & Open Questions

- [ ] [Unresolved question or contradiction]
- [ ] [Gap in knowledge that should be investigated]

## Related

- [[Related Synthesis Page]]
- [[Related Project]]
- [[Related Pattern from prompts/]]

---
*Last synthesized: YYYY-MM-DD from N sources*
```

#### If updating an existing page:

1. Read the existing synthesis page
2. Compare against new source material
3. **Update "What We Know"** — revise with new information, don't just append
4. **Add to "Evolution"** — new row for what changed
5. **Resolve contradictions** — if new info resolves an open question, check it off and update "What We Know"
6. **Add new contradictions** — if new info conflicts with existing knowledge, flag it
7. **Update metadata** — `last-synthesized`, `sources` count, any new `projects` or `tags`
8. **Preserve the one-line summary** — update it only if understanding has fundamentally shifted

### Phase 4: Update Index

Create or update `$BRAIN_PATH/synthesis/_INDEX.md`:

```markdown
---
title: "Knowledge Synthesis Index"
type: index
tags: [synthesis, index]
---

# Knowledge Synthesis Index

Living knowledge pages that compound across sessions.

| Topic | Projects | Sources | Last Updated | Status |
|-------|----------|---------|-------------|--------|
| [[Topic Name]] | Project-1, Project-2 | N | YYYY-MM-DD | active |
```

### Phase 5: Cross-Link

After writing/updating:
1. Check if any **project files** should link to this synthesis page — offer to add a `## Related Knowledge` section
2. Check if any **other synthesis pages** reference the same concepts — offer to add cross-links
3. Check if this synthesis reveals a **pattern** worth adding to the prompt library — suggest `/brain-capture`

### Phase 6: Report

```markdown
## Synthesis Complete

**Page:** `synthesis/[slug].md`
**Sources analyzed:** N files across M projects
**Status:** [created | updated]

### Key insights synthesized:
- [Most important finding]
- [Second finding]
- [Any contradictions or gaps flagged]
```

## Auto-Detection: Finding Synthesis Candidates

When called with "all" or no arguments, scan the vault for topics that appear across multiple sessions/projects but don't yet have a synthesis page:

1. **Extract frequent concepts** from daily notes and captures:
   - Read the last 10 daily notes
   - Read the last 5 captures
   - Identify topics/tools/patterns mentioned 3+ times across different dates
   
2. **Check against existing synthesis pages** — skip topics already synthesized (unless stale)

3. **Rank candidates** by:
   - Cross-session frequency (appears in many different sessions)
   - Cross-project relevance (spans multiple projects)
   - Recency (recent mentions suggest active relevance)
   - Depth (substantial discussion, not just passing mention)

4. **Present candidates:**
   ```
   I found these synthesis candidates:

   1. **eBay Scraping** — mentioned in 8 daily notes across Trading-Post, appears heavily in captures
   2. **Scanner UX Patterns** — recurring across 5 sessions, multiple UI approaches documented
   3. **Rate Limiting Strategies** — cross-project pattern (eBay, API work)

   Which would you like to synthesize? (numbers, 'all', or name a different topic)
   ```

## Lint: Checking Synthesis Health

When reviewing existing synthesis pages (e.g., during `/brain-audit`), check for:

- **Stale pages** — `last-synthesized` more than 30 days ago + new source material exists
- **Orphan pages** — synthesis page not linked from any project or other synthesis
- **Contradiction backlog** — open questions that have been sitting for >2 weeks
- **Source drift** — synthesis claims something that newer daily notes contradict

## Design Principles

- **Synthesize, don't summarize.** A synthesis page isn't a summary of daily notes — it's a distilled understanding that draws connections the individual notes don't.
- **Write for Future You.** Six months from now, reading this page should give full context without needing to read the source notes.
- **Contradictions are features.** Flagging "we tried X in Project A but Y in Project B, with different results" is more valuable than hiding the inconsistency.
- **Evolve, don't append.** When understanding changes, revise the "What We Know" section. The Evolution table preserves the history. The main text should always reflect current truth.
- **Err toward creating.** If in doubt about whether a topic deserves a synthesis page, create it. Small pages grow. Non-existent pages don't.

---

**Usage:** `/brain-synthesize [topic]`

Examples:
- `/brain-synthesize eBay scraping` — synthesize everything about eBay scraping
- `/brain-synthesize` — auto-detect synthesis candidates from recent vault activity
- `/brain-synthesize all` — same as above
- `/brain-synthesize rate limiting` — cross-project synthesis on rate limiting approaches
