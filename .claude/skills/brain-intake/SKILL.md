---
name: brain-intake
description: Run guided conversational interviews to capture life experiences, creative identity, interests, and other personal knowledge into the brain.
argument-hint: <topic-area>
---

# Brain Intake — Guided Interview

You are running a guided conversational interview to capture personal knowledge into the Claude Brain.

## Your Task

The user will optionally provide a topic area (as $ARGUMENTS). You must conduct a warm, conversational interview that feels like talking — not filling out a form.

## Topic Areas

If no topic is provided, offer these options:

1. **Life story** — childhood, background, formative experiences
2. **Career history** — professional path, jobs, turning points
3. **Hobbies & interests** — groups, activities, passions, communities
4. **Creative identity** — what drives their creative work, influences, voice
5. **Music** — what they listen to, create, production approach
6. **Values & worldview** — what matters, perspective on AI/tech/creativity
7. **Communication preferences** — how they want Claude to work with them
8. **Custom topic** — anything else they want captured

## ODT File Support

If the user provides a path to an `.odt` file (as $ARGUMENTS or during conversation), convert it to markdown before processing:

```bash
pandoc "path/to/file.odt" -t markdown
```

**Prerequisite:** Install pandoc (`winget install JohnMacFarlane.Pandoc` on Windows, `brew install pandoc` on macOS, `apt install pandoc` on Linux).

After conversion:
1. Read the converted markdown content
2. Use it as source material for the interview — ask the user about what's in the document
3. Weave the content into the appropriate brain files (creative writing, identity details, etc.)
4. The `.odt` file is never modified — only read

This allows intake of OpenOffice text documents that Claude can't read natively.

## Interview Process

### Step 1: Open the Conversation

Start with a natural, open-ended question related to the topic. Examples:
- "So tell me about your creative work — how'd that get started?"
- "What was your career path like? Where'd it all begin?"
- "What kind of music were you into growing up, and how did that evolve?"

**Do NOT** start with "Let me ask you some questions about X."

### Step 2: Follow the Thread

- Ask follow-up questions based on what they say — follow interesting threads
- Use their language back to them — mirror their tone and energy
- If they mention a person, ask about them
- If they mention an event, ask what happened
- If they mention a feeling or opinion, explore why
- Keep it to 3-5 exchanges before moving to capture (don't exhaust them)

### Step 3: Capture Direct Quotes

Throughout the conversation, note phrases where the user's voice comes through strongly. These go in the "Quotes & Voice Samples" section of the session file. Look for:
- How they describe things (metaphors, humor, word choice)
- Strong opinions stated memorably
- Self-descriptions that reveal identity

### Step 4: Save the Session

Create a session file at:
```
intake/sessions/YYYY-MM-DD-[topic-slug].md
```

Use the **Intake Session Template** from `brain-scan-templates.md`.

### Step 5: Integrate Into Brain

Process the captured information into the appropriate structured files:

| Information Type | Destination |
|-----------------|-------------|
| Background/life story | `IDENTITY.md` → Life Story section |
| Career history | `IDENTITY.md` → Career History section |
| Creative voice/style | `IDENTITY.md` → Creative Voice section |
| Values/worldview | `IDENTITY.md` → Values section |
| Communication prefs | `IDENTITY.md` → Communication Preferences AND `CLAUDE.md` → Working With This Person |
| Hobbies & interests | `creative/[relevant-category]/[topic].md` |
| Creative projects | `creative/[category]/[project-or-topic].md` |
| Specific scripts/works | `creative/[category]/scripts/[script-slug].md` |
| Event records | `creative/[category]/events/YYYY-MM-DD-event-name.md` |
| People mentioned | Create `[[wiki links]]` — note who they are in relevant files |
| Core identity info | `CLAUDE.md` → Identity Snapshot (update the placeholder) |

### Step 6: Add Wiki Links

Every person, project, group, or organization mentioned must become a `[[wiki link]]` in all files where they appear.

### Step 7: Report What Was Captured

End the session with a brief summary:
```
## Session Complete

**Topic:** [topic]
**Session file:** intake/sessions/YYYY-MM-DD-topic.md
**Files updated:**
- [list of files that were created or modified]
**Key things learned:**
- [2-3 bullet summary of the most important new information]
```

## Design Principles

- **Feel like a conversation, not a form.** No numbered question lists.
- **Capture direct quotes** — the user's actual words reveal their voice.
- **Follow interesting threads** — if something surprising comes up, explore it.
- **Don't guess or fabricate** — only write what the user actually said.
- **Each session should feel complete** — even if short, it captures something real.
- **Respect energy** — if the user seems done, wrap up gracefully. Don't push.

## Multiple Sessions

The brain is built up over many sessions. It's fine to capture a little at a time. Each session adds to the picture. Update the session index in `intake/_INDEX.md` after each session.

---

**Usage:** `/brain-intake [topic]`

Examples:
- `/brain-intake hobbies` — interview about hobbies and interests
- `/brain-intake career` — interview about professional history
- `/brain-intake` — choose from topic menu
