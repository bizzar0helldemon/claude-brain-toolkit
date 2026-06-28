---
name: brain-onboard
description: Guided first-time onboarding for a new brain. Walks a person through telling the brain who they are, then discovering and cataloging their existing work — chaining intake, discover, inbox, and scan with check-ins between stages.
argument-hint: "[--quick to run identity only]"
---

# Brain Onboard — Guided Walkthrough

You are walking a person through getting their brain "caught up" with who they are and what they've already made. This is the single front door for onboarding — it orchestrates the individual ingestion skills in sequence, checking in between each stage so the person stays in control and never feels marched through a form.

This skill **delegates** to four other skills. Run each by following its `SKILL.md` instructions, then return here to offer the next stage.

## Vault Location

- **Brain root:** `{{SET_YOUR_BRAIN_PATH}}` (read from the `$BRAIN_PATH` environment variable)
- **Identity profile:** `{{SET_YOUR_BRAIN_PATH}}/IDENTITY.md`

If `$BRAIN_PATH` is unset or its directory is missing, stop and tell the person to run `/brain-setup` first — there's no vault to onboard into yet.

## Arguments

Parse `$ARGUMENTS`:
- **`--quick`** — run only Stage 1 (identity) and stop. For someone who just wants to introduce themselves and catalog projects later.
- No arguments = full guided walkthrough (default).

## The Walkthrough

Open warmly and set expectations. Something like:

> "Let's get your brain caught up with who you are and what you've made. We'll go in stages — I'll check in between each one, and you can stop anytime. Here's the path:
> 1. **Tell me who you are** — a quick conversational interview
> 2. **Discover your existing work** — scan a drive for writing/scripts/audio you've already made
> 3. **Process your inbox** — file anything you've dropped into the vault
> 4. **Catalog your projects** — add your dev projects to the brain
>
> Ready to start with #1?"

Wait for a yes before starting. Let them skip any stage.

### Stage 1 — Identity (`brain-intake`)

The most important stage. Run the **`brain-intake`** skill (follow its `SKILL.md`). Start with the **Life story** and **Communication preferences** topics at minimum — those shape every future session.

When intake wraps, confirm what landed in `IDENTITY.md` and the `CLAUDE.md` Identity Snapshot, then check in:

> "That's the core of who you are captured. Want to keep going and discover work you've already made, or stop here for now? (You can always resume with `/brain-onboard`.)"

**If `--quick`, stop here.** Otherwise continue only on a yes.

### Stage 2 — Discover existing content (`brain-discover`)

Ask where their existing creative work lives (a Documents folder, an archive drive, a Desktop). Then run the **`brain-discover`** skill against that path (follow its `SKILL.md`) — it finds writing, scripts, lyrics, and audio not yet in the brain and lets them choose what to ingest.

Check in:

> "Found and filed [N] things. Want to process anything you've dropped into the vault's inbox next?"

### Stage 3 — Process the inbox (`brain-inbox`)

Run the **`brain-inbox`** skill (follow its `SKILL.md`) to route any loose files in `inbox/` and the vault root to their proper homes.

Check in:

> "Inbox is clear. Last stage: want to catalog your dev projects so the brain knows what you're building?"

### Stage 4 — Catalog projects (`brain-scan`)

For each project directory they name, run the **`brain-scan`** skill (follow its `SKILL.md`). Offer to do them one at a time or point at a directory of repos.

## Closing

When they stop (at any stage), summarize the whole walkthrough:

```
## Onboarding Summary

**Completed stages:** [list]
**Identity:** [sections of IDENTITY.md now populated]
**Discovered:** [N creative items ingested]
**Inbox:** [N files routed]
**Projects cataloged:** [list]

**Picked up where you left off?** Resume anytime with `/brain-onboard`.
**Next:** [suggest the most valuable not-yet-done stage, if any]
```

## Design Principles

- **One stage at a time, always a check-in.** Never chain straight through — confirm between each.
- **Identity first, identity matters most.** Even if they do nothing else, Stage 1 is the win.
- **Resumable.** Someone can run `/brain-onboard` repeatedly; skip stages already done (check whether `IDENTITY.md` is populated, whether projects exist in `projects/_INDEX.md`).
- **Respect energy.** If they seem done, wrap up gracefully with the summary. Don't push to the next stage.
- **Delegate, don't reimplement.** Each stage runs the real skill (`brain-intake`, `brain-discover`, `brain-inbox`, `brain-scan`) — this skill is the connective tissue, not a copy of their logic.

---

**Usage:** `/brain-onboard [--quick]`

Examples:
- `/brain-onboard` — full guided walkthrough (identity → discover → inbox → projects)
- `/brain-onboard --quick` — just the identity interview, catalog the rest later
