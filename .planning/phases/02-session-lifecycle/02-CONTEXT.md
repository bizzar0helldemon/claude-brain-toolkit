# Phase 2: Session Lifecycle - Context

**Gathered:** 2026-03-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Automatic vault context injection at session start, pre-clear knowledge capture, and token budget management. This phase makes brain mode an active participant — loading relevant knowledge when sessions begin and preserving learnings before context is cleared. Entry points (`claude --agent brain-mode`) and first-run onboarding are separate phases.

</domain>

<decisions>
## Implementation Decisions

### Context Selection
- Load **project-specific entries + global user preferences** at session start
- Project matching via **frontmatter `project:` field** — matched against current directory name or git remote
- Also check for a **`.brain.md` file in the project root** as an additional context source (project-local knowledge)
- Prioritize entries by **most recent first** within the token budget
- **Always inject something** every session — even if just global prefs, so the user knows brain is active
- For **first-time projects** (no vault entries, no .brain.md): load global prefs and **proactively offer to scan** the project for brain cataloging
- **Track which vault entries were loaded** — next session can show only new/changed entries instead of repeating

### Context Source Merge Strategy
- Claude's Discretion: how `.brain.md` and vault entries are merged/prioritized

### Pre-clear Capture
- Trigger **both `/brain-capture` and `/daily-note` skills** on pre-clear — these existing skills handle the actual capture logic
- Capture fires on **both `/clear` and session end** (Stop hook) — never lose a session
- Show a **brief notification** after capture (e.g., "Brain captured: 3 learnings, daily note updated") — no confirmation dialog needed
- **Always capture**, even for trivial sessions — let the skills decide what's worth saving

### Token Budget
- Default **2,000 token ceiling**, but **configurable** via env var or config (e.g., `BRAIN_TOKEN_BUDGET=3000`)
- When content exceeds budget: **drop lowest priority entries** (load in priority order, stop when budget reached — no summarization)
- Use a **precise tokenizer** for accurate budget enforcement (not word count heuristic)
- Claude's Discretion: whether `.brain.md` shares the vault token budget or gets a separate allocation

### Surface Format
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

</decisions>

<specifics>
## Specific Ideas

- The summary block format shown above is the approved style — functional, indented, with counts and recency indicators
- Existing `/brain-capture` and `/daily-note` skills handle capture logic — this phase orchestrates when they fire, not what they do
- Entry tracking enables "what's new since last session" awareness

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-session-lifecycle*
*Context gathered: 2026-03-19*
