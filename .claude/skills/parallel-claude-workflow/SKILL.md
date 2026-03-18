---
name: parallel-claude-workflow
description: >
  Use this skill whenever a Claude Code session is starting and a parallel workflow context is needed — 
  meaning any time the user mentions working across multiple terminals, coordinating with a collaborator, 
  running two Claude Code instances, async handoffs, or branching strategy for multi-operator work. 
  Also trigger when the user says things like "spin up another agent", "work in parallel", "my partner 
  is going to work on this", "I need a handoff note", or "what branch should I be on". This skill 
  establishes task isolation, branch discipline, and handoff hygiene so parallel sessions don't collide.
---

# Parallel Claude Code Workflow Skill

This skill governs how to behave when operating as one of multiple Claude Code instances on a project, 
or when helping a human set up a parallel work session.

---

## On Session Start — Always Do This

When this skill is triggered, immediately establish:

1. **What branch am I on?** Ask if not told. Never assume `main` or `dev` is the working branch.
2. **What is my task scope?** Get explicit file/feature boundaries before touching anything.
3. **Is another instance or operator working simultaneously?** If yes, confirm there is no file overlap.
4. **Where is the most recent handoff note?** Read it before proceeding if one exists.

If any of these are unknown, ask the human before writing a single line of code.

---

## Task Scope Rules (Non-Negotiable)

- Work only within your assigned scope. Do not refactor, reorganize, or "improve" files outside your task.
- If you discover a bug or issue outside your scope, **document it in your session summary** — do not fix it unilaterally.
- If your task requires a file another agent or operator is likely touching, **stop and flag it to the human**.

---

## Branch Rules

- Never commit to `main` or `dev` directly.
- Always work on a `[operator]/[task-name]` branch.
- If you are not on the correct branch, tell the human immediately — do not `git checkout` yourself without confirmation.
- Commit frequently with descriptive messages. Format: `[branch-name]: what was done`

---

## End of Session — Always Do This

Before the human closes the terminal, produce a **session summary** in this format:

```
## Session Summary — [date]
**Branch:** [current branch]
**Task:** [what you were working on]

### Files changed:
- [file path] — [what changed and why]

### Current state:
[Complete / WIP / Blocked]

### Known issues or edge cases:
[anything the next session needs to know]

### Next steps:
[what should happen next]

### Safe to merge to dev?
[Yes / No / Needs review]
```

This summary becomes the handoff note. The human will save it to the Obsidian vault.

---

## Multi-Instance Awareness

You do not have visibility into what other Claude Code instances are doing. 
This is by design. The human operator is the coordination layer.

**Your job is to:**
- Stay in your lane (branch + scope)
- Produce clean, well-documented work
- Surface blockers immediately rather than improvising around them
- Leave the codebase in a better or equal state to how you found it

**Not your job:**
- Merging branches
- Coordinating with other agents
- Making architectural decisions outside your task scope
- Pushing to `dev` or `main`

---

## Handoff Note Location

Handoff notes live in the brain repo at:
```
[brain-repo]/handoffs/[YYYY-MM-DD]-[operator]-[task].md
```

If you're producing a handoff note, format it exactly as specified in `PARALLEL_WORKFLOW.md` 
and remind the human to save it there.

---

## Reference

Full protocol details, git workflow steps, and conflict prevention checklist:
→ `PARALLEL_WORKFLOW.md` in the brain repo root
