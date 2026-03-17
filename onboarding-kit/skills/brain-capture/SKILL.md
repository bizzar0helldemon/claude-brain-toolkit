---
name: brain-capture
description: Scan the current conversation for effective prompts and interaction patterns, then save them to the Prompt & Pattern Library in the Claude Brain.
argument-hint: <optional focus hint>
---

# Brain Capture — Prompt & Pattern Extraction

You are extracting effective prompts and interaction patterns from the current conversation and saving them to the Prompt & Pattern Library in the Claude Brain.

## Paths

- **Brain root:** `{{BRAIN_PATH}}`
- **Library root:** `{{BRAIN_PATH}}/prompts/`
- **Index:** `{{BRAIN_PATH}}/prompts/_INDEX.md`
- **Template reference:** `{{BRAIN_PATH}}/brain-scan-templates.md` (see "Prompt Pattern Template")

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

1. Read `{{BRAIN_PATH}}/prompts/_INDEX.md`
2. Note all existing entries to avoid duplicates
3. If a similar pattern already exists, you'll flag it during Phase 1

### Phase 1: Conversation Scan

If the user provided $ARGUMENTS (e.g., `/brain-capture that debug approach`), focus your scan on that specific topic. Otherwise, scan the full conversation.

**If the conversation has no identifiable patterns** (fresh conversation, purely administrative), tell the user:
> "I don't see any clear prompt patterns in this conversation yet. Try running `/brain-capture` after a session where you've been working on a substantive task, or give me a hint about what to look for."

**Look for:**
- Prompts that produced notably good results
- Prompts that produced notably bad results (anti-patterns)
- Patterns that emerged through iteration
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

### Phase 2: Guided Interview

For each selected candidate, walk through these questions. **Suggest answers based on the conversation — don't make the user do all the work.** Let them confirm or adjust.

1. **Title** — Suggest a concise, descriptive title
2. **Domain** — Suggest based on context, confirm with user
3. **The Prompt** — Distill the actual prompt template with `{{placeholders}}` for variable parts
4. **When to Use** — What situation or trigger makes this pattern applicable
5. **Why It Works** — What technique makes it effective
6. **Variations** — Alternative phrasings or adaptations
7. **What Doesn't Work** — Anti-patterns from the conversation
8. **Effectiveness** — high, medium, or experimental

### Phase 3: Save

For each completed entry:

1. **Check if domain directory exists** — create it if not
2. **Write the pattern file** to `{{BRAIN_PATH}}/prompts/[domain]/[slug].md`
3. **Update _INDEX.md** with the new entry
4. **Confirm the save** with a brief preview

### Phase 4: Session Summary

Print what was saved and the library totals.

## Design Principles

- **Suggest, don't interrogate.** Use the conversation context to pre-fill answers.
- **Extract the reusable core.** Strip conversation-specific details from prompts.
- **Don't duplicate.** Check the existing library before saving.
- **Keep it real.** Only capture patterns that actually demonstrated value or failure.

---

**Usage:** `/brain-capture [optional hint]`
