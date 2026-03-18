---
title: Parallel Claude Code Workflow
type: framework
tags: [framework, claude-code, parallel, git, collaboration, workflow]
related: []
---

# Parallel Claude Code Workflow Protocol

A generic, project-agnostic protocol for running parallel Claude Code sessions — whether solo with two instances or with a human collaborator. Designed to live in the brain repo and be referenced by any project.

---

## Core Principles

1. **Branch isolation is mandatory.** No two agents or humans ever work on the same branch simultaneously.
2. **The Obsidian vault is the coordination layer.** Handoff notes are written before every push.
3. **The human is always the orchestrator.** Claude Code instances do not coordinate with each other — you decide what each one does and when to merge.
4. **Main branch is always stable.** Nothing goes to `main` that hasn't been reviewed by the human-in-the-loop.

---

## Branch Naming Convention

```
main              ← stable, production-ready only
dev               ← integration branch; merge tested feature branches here
[operator]/[task] ← working branches, one per task per operator
```

**Examples:**
```
stephen/inventory-ui
stephen/auth-refactor
partner/onboarding-flow
partner/email-templates
```

Branches are cheap. Make a new one for every discrete task. Never reuse a working branch for a second task — close it, merge or discard, start fresh.

---

## Session Types

### Type A — Solo, Two Claude Code Instances

Use when you want to parallelize your own workload across two independent tasks.

**Setup:**
1. Open Terminal 1 → `cd [project] && git checkout -b stephen/task-a && claude`
2. Open Terminal 2 → `cd [project] && git checkout -b stephen/task-b && claude`
3. Give each instance its task. They run independently.
4. You review both outputs before merging either to `dev`.

**Rules:**
- Never give both instances overlapping files or concerns.
- If one instance needs something the other is building, stop and sequence them instead of parallelizing.
- Write a handoff note after each session before switching context.

---

### Type B — Two Humans, Each with Their Own Claude Code

Use when collaborating with a business partner or contributor, synchronously or asynchronously.

**Setup:**
- Each operator works exclusively on their own branch namespace (`stephen/` vs `partner/`).
- Each operator is responsible for their own Claude Code sessions and handoff notes.
- Neither operator merges to `dev` without the other's awareness (use a handoff note or a quick message).
- `main` merges require both operators to have reviewed the `dev` state.

**Rules:**
- Pull from `dev` before starting any new branch to stay current.
- Never push directly to `dev` or `main` — always go through a working branch first.
- If a conflict occurs on `dev`, the operator who pushed second resolves it.

---

### Type C — Async Work (Different Schedules or Time Zones)

Use when operators are not working simultaneously and coordination happens through notes rather than real-time communication.

**The golden rule: leave the repo in a state you'd be comfortable handing to a stranger.**

**Before ending a session:**
1. Commit everything, even if incomplete (use `WIP:` prefix in commit message).
2. Write a handoff note (see template below).
3. Push your branch.
4. Update the shared Obsidian vault with your handoff note.

**Before starting a session:**
1. Pull latest from `dev`.
2. Read the most recent handoff note(s) in the Obsidian vault.
3. Note any blockers or dependencies before starting Claude Code.

---

## Git Workflow (Step by Step)

### Starting a New Task

```bash
git checkout dev
git pull origin dev
git checkout -b [operator]/[task-name]
# now launch claude
claude
```

### Finishing a Task

```bash
git add .
git commit -m "[operator]/[task-name]: brief description of what was done"
git push origin [operator]/[task-name]
# write handoff note
# notify collaborator if async
```

### Merging to Dev

```bash
git checkout dev
git pull origin dev
git merge [operator]/[task-name]
# resolve any conflicts
git push origin dev
```

### Merging Dev to Main (both operators agree)

```bash
git checkout main
git pull origin main
git merge dev
git push origin main
git tag v[version] -m "release note"
```

---

## Handoff Note Template

File location: `[Brain Repo]/handoffs/[YYYY-MM-DD]-[operator]-[task].md`

```markdown
## Handoff Note
**Date:** YYYY-MM-DD
**Operator:** [Stephen / Partner]
**Branch:** [operator]/[task-name]
**Project:** [project name]
**Session type:** [Solo-A / Two-Human-B / Async-C]

### What was done
[Brief summary of what Claude Code worked on this session]

### Files changed
- `path/to/file.js` — [what changed]
- `path/to/other.md` — [what changed]

### Current state
[ ] Complete — ready to merge to dev
[ ] WIP — needs more work before merge
[ ] Blocked — waiting on: [describe blocker]

### Known issues / edge cases
[Anything the next operator should know before touching this work]

### Next steps
[What should happen next on this branch or task]

### Safe to merge to dev?
[ ] Yes  [ ] No  [ ] Needs review first
```

---

## Conflict Prevention Checklist

Before starting a Claude Code session, run through this mentally:

- [ ] Am I on a clean working branch (not `dev` or `main`)?
- [ ] Have I pulled latest from `dev`?
- [ ] Have I read the most recent handoff note?
- [ ] Is my task scope clearly isolated from what any other branch is touching?
- [ ] Do I know which files I expect to change?

If you can't answer yes to all five, pause and resolve before starting.

---

## What Claude Code Sessions Should Know

When spinning up a Claude Code instance for a parallel session, include this context in your first prompt or via `CLAUDE.md`:

```
You are working on branch: [operator]/[task-name]
Your task is scoped to: [specific files or features]
Do not modify: [any files outside your scope]
When finished, summarize all changed files for the handoff note.
Do not merge or switch branches — the human operator handles all git merges.
```

This keeps the agent task-scoped and prevents it from wandering into other areas of the codebase.

---

## Quick Reference

| Scenario | Branch strategy | Coordination method |
|---|---|---|
| Solo, two tasks | `stephen/task-a` + `stephen/task-b` | You switch between terminals |
| Two humans, same time | `stephen/x` + `partner/y` | Handoff notes + Obsidian |
| Two humans, async | One works at a time per branch | Handoff notes are mandatory |
| Emergency hotfix | `stephen/hotfix-[desc]` off `main` | Skip `dev`, merge direct to `main` after review |

---

## Init Script

Run `parallel-workflow-init.sh` from any git repo to set up the branching structure:

```bash
bash parallel-workflow-init.sh
bash parallel-workflow-init.sh --operator stephen --partner partner
bash parallel-workflow-init.sh --brain /path/to/brain/repo
```

Script location: `frameworks/parallel-claude-workflow-init.sh`
