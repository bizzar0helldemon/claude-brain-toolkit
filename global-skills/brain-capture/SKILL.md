---
name: brain-capture
description: Scan the current conversation for effective prompts and interaction patterns, then save them to the Prompt & Pattern Library in the Claude Brain.
argument-hint: <optional focus hint>
---

# Brain Capture — Prompt & Pattern Extraction

You are extracting effective prompts and interaction patterns from the current conversation and saving them to the Prompt & Pattern Library in the Claude Brain.

## Paths

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}`
- **Library root:** `{{SET_YOUR_BRAIN_PATH}}/prompts/`
- **Index:** `{{SET_YOUR_BRAIN_PATH}}/prompts/_INDEX.md`
- **Template reference:** `{{SET_YOUR_BRAIN_PATH}}/brain-scan-templates.md` (see "Prompt Pattern Template")

## Domains

Available domains (subdirectories under `prompts/`):
- `coding` — programming, debugging, architecture, code review
- `writing` — editorial, copywriting, content creation
- `music` — production, lyrics, arrangement, mixing
- `consulting` — client training, workshops, workflow design, AI strategy
- `creative` — visual art, comics, video, mixed media
- `hardware` — IoT, embedded systems, electronics
- `business` — operations, planning, proposals
- `general` — cross-domain patterns that don't fit elsewhere
- `meta` — patterns about working with AI itself (conversation recovery, prompt iteration, etc.)

If a pattern doesn't fit any domain, create a new subdirectory and add it.

## Process

### Phase 0: Load Existing Library

1. Read `{{SET_YOUR_BRAIN_PATH}}/prompts/_INDEX.md`
2. Note all existing entries to avoid duplicates
3. If a similar pattern already exists, you'll flag it during Phase 1

### Phase 1: Conversation Scan

If the user provided $ARGUMENTS (e.g., `/brain-capture that debug approach`), focus your scan on that specific topic. Otherwise, scan the full conversation.

**If the conversation has no identifiable patterns** (fresh conversation, purely administrative), tell the user:
> "I don't see any clear prompt patterns in this conversation yet. Try running `/brain-capture` after a session where you've been working on a substantive task, or give me a hint about what to look for."

**Look for:**
- Prompts that produced notably good results
- Prompts that produced notably bad results (anti-patterns)
- Patterns that emerged through iteration (the Description → Discernment loop)
- Techniques that could be reused in future conversations
- Recurring task types that would benefit from a template

**Present candidates as a numbered list:**
```
I found these patterns worth capturing:

1. **[Pattern name]** — [Brief description of what happened and why it's notable]
2. **[Pattern name]** — [Brief description]
3. **[Anti-pattern name]** — [What went wrong and why it's worth documenting]

Which would you like to capture? (numbers, 'all', or describe something I missed)
```

If a candidate matches an existing library entry, note it:
> "Note: #2 looks similar to [[Existing Pattern]] — want to update that entry instead?"

### Phase 2: Guided Interview

For each selected candidate, walk through these questions. **Suggest answers based on the conversation — don't make the user do all the work.** Let them confirm or adjust.

1. **Title** — Suggest a concise, descriptive title
2. **Domain** — Suggest based on context, confirm with user
3. **Interaction mode** — automation, augmentation, or agency
4. **AI fluency dimensions** — which of the 4 D's does this relate to:
   - **Delegation** — deciding what to hand to AI
   - **Description** — how the prompt communicates the task
   - **Discernment** — evaluating and refining the output
   - **Diligence** — responsibility, verification, ethics
5. **The Prompt** — Distill the actual prompt template with `{{placeholders}}` for variable parts. Strip conversation-specific details, keep the reusable structure.
6. **When to Use** — What situation or trigger makes this pattern applicable
7. **Why It Works** — What technique makes it effective (chain-of-thought? role definition? constraints? examples?)
8. **Variations** — Alternative phrasings or adaptations
9. **What Doesn't Work** — Anti-patterns from the conversation or the user's experience
10. **Effectiveness** — high (proven, used multiple times), medium (worked but needs more testing), experimental (promising first use)
11. **Related** — Any existing brain entries to cross-link (projects, frameworks, other patterns)

**Keep the interview conversational, not form-like.** You can combine related questions. If the user seems done, wrap up gracefully.

### Phase 3: Save

For each completed entry:

1. **Check if domain directory exists** — create it if not:
   ```bash
   mkdir -p "{{SET_YOUR_BRAIN_PATH}}/prompts/[domain]"
   ```

2. **Write the pattern file** using the Prompt Pattern Template from `brain-scan-templates.md`:
   - File path: `{{SET_YOUR_BRAIN_PATH}}/prompts/[domain]/[slug].md`
   - File name: kebab-case from the title
   - All frontmatter fields populated
   - `created` and `last-used` set to today's date
   - Use `[[wiki links]]` for all cross-references

3. **Update _INDEX.md:**
   - Read the current index
   - Add a new row to the table: `| [[Pattern Title]] | domain | mode | dimensions | effectiveness | one-line summary |`
   - Update the footer counts (total, by domain, by effectiveness)

4. **Confirm the save:**
   ```
   ## Saved

   **File:** `prompts/[domain]/[slug].md`
   **Index updated:** yes

   [Show a brief preview of the entry]
   ```

### Phase 4: Session Summary

After all selected patterns are saved, summarize:

```
## Capture Complete

**Patterns saved:**
- [[Pattern 1]] → `prompts/domain/slug.md`
- [[Pattern 2]] → `prompts/domain/slug.md`

**Library total:** [N] patterns across [M] domains
```

## Design Principles

- **Suggest, don't interrogate.** Use the conversation context to pre-fill answers. The user confirms or adjusts.
- **Extract the reusable core.** Strip conversation-specific details from prompts. Keep the structure that makes them work.
- **Ground in the 4 D's.** Every pattern should connect back to the AI Fluency Framework vocabulary.
- **Don't duplicate.** Check the existing library before saving. Offer to update existing entries.
- **Keep it real.** Only capture patterns that actually demonstrated value (or failure). Don't fabricate entries.

## Updating Existing Entries

If the user wants to update an existing pattern (flagged during Phase 1 or requested directly):
1. Read the existing file
2. Show the user what's there
3. Walk through what changed (new variations, updated effectiveness, new anti-patterns)
4. Edit the file in place
5. Update `last-used` date
6. Update `_INDEX.md` if effectiveness or summary changed

---

**Usage:** `/brain-capture [optional hint]`

Examples:
- `/brain-capture` — scan full conversation for patterns
- `/brain-capture that debug approach` — focus on a specific technique
- `/brain-capture the prompting style we used for the client brief` — capture a specific pattern
