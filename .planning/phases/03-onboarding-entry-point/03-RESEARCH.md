# Phase 3: Onboarding + Entry Point - Research

**Researched:** 2026-03-21
**Domain:** Claude Code Subagents API, settings.json env block, shell profile detection, BRAIN_PATH persistence, onboarding wizard patterns
**Confidence:** HIGH (core agent/settings mechanics) / MEDIUM (shell profile detection) / LOW (skills preloading live behavior — requires live test)

---

## Summary

Phase 3 delivers two things: (1) a `brain-mode` subagent definition that gives Claude a specialized brain-aware identity when launched with `claude --agent brain-mode`, and (2) an onboarding flow that guides new users from zero to a configured, working vault. The subagent system is now the native, official mechanism for customizing Claude Code's main thread — the `--agent` flag replaces the old `--system-prompt` approach for this use case.

The Claude Code subagent system is fully documented and verified in official docs (code.claude.com). The `agent` field in `settings.json` makes brain mode the default for every session without requiring the user to pass a flag. The `env` block in `settings.json` is the correct dual-channel approach for BRAIN_PATH — it injects the env var into every hook subprocess regardless of shell profile loading, which solves the "subshells don't load profiles" problem already identified in Phase 1/2.

The critical open question is whether the `skills` frontmatter field in the `agents/brain-mode.md` definition actually preloads existing brain-* skills at session start. The official docs confirm `skills` injects full skill content at startup — this is documented behavior. However, the skills must exist in a discoverable location (`~/.claude/skills/`) and must be listed by name in the agent frontmatter. This is a live test dependency: Phase 3 must verify that brain-* skills are present in the install path and appear under their expected names before listing them in `brain-mode.md`.

The onboarding flow has two distinct cases: (a) BRAIN_PATH unset — user needs a wizard to choose a vault path and configure env; (b) BRAIN_PATH set but directory missing — user needs to create the directory or re-point to the correct location. Both cases are already handled by `lib/brain-path.sh`'s dual-channel error output. The onboarding skill only needs to trigger when Claude reads the JSON `degraded: true` signal and direct the user through the fix interactively.

**Primary recommendation:** Build `brain-mode.md` as a global user-level subagent (`~/.claude/agents/brain-mode.md`). Set `agent: brain-mode` in the project's `.claude/settings.json` to make it the default entry point. The onboarding flow is a skill (`/brain-setup`) that the brain-mode agent triggers when `degraded: true` is received from any hook.

---

## Architecture Patterns

### Subagent Definition Location

Brain mode is a personal, cross-project subagent — it should live at `~/.claude/agents/brain-mode.md` (user scope), not `.claude/agents/brain-mode.md` (project scope). This makes it available system-wide and usable from any project directory.

To make brain mode the default for the claude-brain-toolkit project specifically, set:
```json
{
  "agent": "brain-mode"
}
```
in `.claude/settings.json` (project-level settings file). This is committed to the repo. The `--agent brain-mode` CLI flag overrides this for one-off use and persists when resuming the session.

### Subagent Frontmatter Structure

```markdown
---
name: brain-mode
description: Personal knowledge brain mode. Loads vault context, guides onboarding, captures learnings. Use when the user wants to work with their brain vault or when BRAIN_PATH is configured.
tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: inherit
skills:
  - brain-capture
  - daily-note
  - brain-audit
---

[system prompt content here]
```

Key frontmatter decisions:
- `tools: Agent` — required for brain-mode to spawn subagents (the Explore subagent for vault queries, etc.). Without `Agent` in the tools list, the main-thread agent cannot spawn subagents.
- `skills:` — lists skill names to inject at startup. Only skills that exist in `~/.claude/skills/` are resolvable. Names must match the skill's `name` frontmatter field (not the directory name).
- `model: inherit` — uses whatever model the user has active; brain mode should not override this.

### BRAIN_PATH Dual-Channel Persistence

BRAIN_PATH must be set in two places to survive all session types:

```
1. Shell profile (~/.bashrc, ~/.bash_profile, ~/.zshrc — whichever exists)
   → Covers interactive terminal sessions where the profile loads

2. ~/.claude/settings.json env block
   → Covers all Claude Code hook subprocesses (non-interactive subshells that never load profiles)
```

This is a locked decision from Phase 1/2 context. The onboarding wizard must write to BOTH.

**settings.json env block pattern:**
```json
{
  "env": {
    "BRAIN_PATH": "/path/to/vault"
  }
}
```

**Shell profile update pattern (bash):**
```bash
# Detect which profile to write to
if [ -f "$HOME/.zshrc" ]; then
  PROFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
  PROFILE="$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
  PROFILE="$HOME/.bashrc"
else
  # Create .bashrc as the default on systems with no profile
  PROFILE="$HOME/.bashrc"
fi

# Idempotent append: only write if not already present
if ! grep -q "BRAIN_PATH" "$PROFILE" 2>/dev/null; then
  printf '\n# Claude Brain vault location\nexport BRAIN_PATH="%s"\n' "$BRAIN_PATH_VALUE" >> "$PROFILE"
fi
```

**settings.json update pattern (jq-based, preserving existing keys):**
```bash
SETTINGS_FILE="$HOME/.claude/settings.json"
NEW_PATH="$BRAIN_PATH_VALUE"

# Read existing, merge env.BRAIN_PATH, write back
jq --arg p "$NEW_PATH" '.env.BRAIN_PATH = $p' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
```

Note: if `~/.claude/settings.json` doesn't exist or has no `env` block, `jq` will create it. The `.env.BRAIN_PATH = $p` assignment creates nested structure as needed.

### Onboarding Flow Design: Two Cases

The critical design point noted in STATE.md: two distinct cases require different flows.

**Case A: BRAIN_PATH unset (first-time user)**

Trigger: `brain-path.sh` emits `{"error":"BRAIN_PATH is not set","degraded":true}` to stdout.

Flow:
1. Claude reads the JSON and sees `degraded: true`
2. Brain mode system prompt instructs Claude to trigger `/brain-setup` when degraded
3. `/brain-setup` skill walks the user through:
   - Ask: "Where do you want your brain vault? (example: ~/Documents/claude_brain)"
   - User provides path
   - Expand `~` to `$HOME`
   - `mkdir -p "$CHOSEN_PATH"`
   - Write to shell profile (idempotent)
   - Write to `~/.claude/settings.json` env block (idempotent)
   - Show next-steps summary
4. Instruct user to restart Claude Code (env vars loaded at startup, not runtime)

**Case B: BRAIN_PATH set but directory missing**

Trigger: `brain-path.sh` emits `{"error":"BRAIN_PATH directory does not exist","path":"...","degraded":true,"offer_create":true}` to stdout.

Flow:
1. Claude reads JSON and sees `offer_create: true`
2. Brain mode system prompt instructs Claude to offer two choices:
   - "Create the directory at the current path" → `mkdir -p "$BRAIN_PATH"`
   - "Update BRAIN_PATH to a new location" → re-run vault path selection, update both shell profile and settings.json
3. For the "create directory" path: vault directory is created immediately, session continues without restart

**Case C: Vault path set and directory exists but vault is empty**

Not a degraded state — `brain-path.sh` returns success. Brain mode SessionStart hook loads context normally, finds nothing, and shows the "first project" path: inject summary block noting "No vault entries yet" and offer to run `/brain-scan` to catalog the project.

This case is handled by existing Phase 2 logic (the "first-time project" path in brain-context.sh).

### Entry Point: `claude --agent brain-mode`

The `--agent` flag makes the entire main session thread operate under the brain-mode system prompt. From the official docs:

> "Pass `--agent <name>` to start a session where the main thread itself takes on that subagent's system prompt, tool restrictions, and model."

The agent name appears as `@brain-mode` in the startup header.

To default brain mode for all sessions in this repo, add to `.claude/settings.json`:
```json
{
  "agent": "brain-mode"
}
```

For a user who has deployed brain mode, they would add this to their `~/.claude/settings.json` to make it their global default — but this is an advanced step, not part of Phase 3 onboarding.

### Skills Field: Preloading at Startup

From official docs (verified):
> "Use the `skills` field to inject skill content into a subagent's context at startup. This gives the subagent domain knowledge without requiring it to discover and load skills during execution."
> "The full content of each skill is injected into the subagent's context, not just made available for invocation. Subagents don't inherit skills from the parent conversation; you must list them explicitly."

This is the answer to the open question in STATE.md. The `skills` field **does** preload full skill content at session start. However:
- Skills must be listed by their `name` frontmatter field
- Skills must exist in a discoverable location (personal `~/.claude/skills/` or project `.claude/skills/`)
- Brain-* skills (`brain-capture`, `daily-note`, `brain-audit`) must be deployed to `~/.claude/skills/` as part of the install/onboarding process before they can be listed in `brain-mode.md`

The Phase 3 onboarding script (or the existing `onboarding-kit/setup.sh`) must copy global-skills to `~/.claude/skills/` before `brain-mode.md` is usable with `skills:` preloading.

### Recommended Project Structure for Phase 3

```
claude-brain-toolkit/
├── agents/
│   └── brain-mode.md          # Subagent definition (deployed to ~/.claude/agents/)
├── global-skills/
│   ├── brain-audit/SKILL.md   # Deployed to ~/.claude/skills/brain-audit/
│   ├── brain-capture/SKILL.md # Deployed to ~/.claude/skills/brain-capture/
│   └── daily-note/SKILL.md    # Deployed to ~/.claude/skills/daily-note/
├── onboarding-kit/
│   ├── setup.sh               # Existing installer
│   └── skills/
│       └── brain-setup/
│           └── SKILL.md       # NEW: onboarding wizard skill
└── .claude/
    └── settings.json          # Add "agent": "brain-mode" here
```

---

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Claude Code Subagents | v2.1.79+ | `brain-mode` identity, skills preloading, entry point | The only native mechanism for customizing main-thread behavior in Claude Code. `--agent` flag is the correct entry point pattern. |
| `settings.json` `env` block | v2.1.79+ | BRAIN_PATH injection into all hook subprocesses | Required to bridge interactive shell env to non-interactive Claude Code hook subshells. Verified against official docs. |
| `settings.json` `agent` field | v2.1.79+ | Default agent for project sessions | Makes `claude` without flags enter brain mode in the brain-toolkit project. |
| `jq` | 1.6+ | Programmatic `settings.json` mutation in onboarding | Already a hard dependency. Used to add/update `env.BRAIN_PATH` without destroying existing settings keys. |
| Bash skill (`/brain-setup`) | — | Interactive onboarding wizard | Skills are the correct mechanism for user-interactive guided flows in Claude Code. |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `/agents` command | v2.1.79+ | Inspect/reload subagent definitions during development | Use to verify `brain-mode.md` loaded correctly; also useful for users who want to inspect what brain mode does |
| `claude agents` (CLI) | v2.1.79+ | List all configured agents from terminal | Use in verification steps — confirms `brain-mode` appears in the list |
| Shell profile detection | — | Write `export BRAIN_PATH=...` to the right profile | Required for interactive terminal sessions; `~/.zshrc` > `~/.bash_profile` > `~/.bashrc` > create `.bashrc` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `skills` frontmatter preloading | Manual skill invocation in system prompt | `skills` is cleaner (content is always in context); manual invocation requires Claude to decide to run `/brain-capture` etc. during session init |
| Bash `/brain-setup` skill | Python setup script | Both work. Bash is already the hook language; Python adds a dependency. Bash is consistent with existing tooling. |
| Project `.claude/settings.json` `agent` field | Global `~/.claude/settings.json` `agent` field | Project-scoped is committed to repo (good for brain toolkit); global-scoped would make brain mode default everywhere (too aggressive for Phase 3) |

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Main-thread identity/system prompt | Custom `--system-prompt` flag or CLAUDE.md override | `brain-mode.md` subagent + `agent` field in settings.json | Subagents are the first-class mechanism; they support skills preloading, model selection, tool restrictions, and hooks — none of which `--system-prompt` supports |
| Env var injection into hook subprocesses | Custom env injection in each hook script | `settings.json` `env` block | Claude Code already has this mechanism; adding it to each hook script is redundant and error-prone |
| Settings.json mutation | Custom JSON parser/writer | `jq` with atomic `temp file + mv` pattern | jq handles all edge cases (missing keys, type coercion, nested creation). Custom parsers break on edge cases. |
| Skill content preloading | Manual reads of skill files in SessionStart hook | `skills:` frontmatter in agent definition | Official mechanism — Claude handles the injection, correct token allocation, and context scope |

**Key insight:** The subagent system handles all the "special launch mode" problems natively. There is no need to build custom entry-point detection, system prompt injection, or skill preloading — these are all solved by `brain-mode.md` + the `agent` field.

---

## Common Pitfalls

### Pitfall 1: Skills Listed Before They Exist
**What goes wrong:** `brain-mode.md` lists `skills: [brain-capture, daily-note]` but those skills haven't been deployed to `~/.claude/skills/`. The agent silently fails to preload them (no error; skill content simply isn't injected).
**Why it happens:** The `skills` field resolves at session start against installed skills. Missing skills are silently skipped.
**How to avoid:** Onboarding must install skills to `~/.claude/skills/` BEFORE deploying `brain-mode.md`. Verify by running `/agents` and checking brain-mode's loaded skills.
**Warning signs:** Brain mode starts but doesn't know about `/brain-capture` patterns or vault conventions without being told.

### Pitfall 2: BRAIN_PATH Set in Profile but Not in settings.json env
**What goes wrong:** User sets `export BRAIN_PATH=...` in `.zshrc`. Works in interactive terminal. Hooks fail with "BRAIN_PATH is not set" because Claude Code hooks run in non-interactive subshells that don't load `.zshrc`.
**Why it happens:** Already documented as a locked decision. This is the dual-channel requirement.
**How to avoid:** Onboarding wizard writes to BOTH the shell profile AND `~/.claude/settings.json` env block.
**Warning signs:** Brain works when running `claude` from terminal but breaks after computer restart or in new terminal windows.

### Pitfall 3: Restart Not Instructed After settings.json env Update
**What goes wrong:** Onboarding writes `BRAIN_PATH` to `settings.json` env block, but the current Claude Code session doesn't pick it up. User thinks onboarding worked but hooks still report degraded.
**Why it happens:** `settings.json` env vars are loaded at session startup — they don't hot-reload into a running session.
**How to avoid:** The `/brain-setup` skill must end with an explicit instruction: "Restart Claude Code for the env var to take effect."
**Warning signs:** User reports "I ran brain-setup but it still says BRAIN_PATH is not set."

### Pitfall 4: `jq` Not Available When Onboarding Runs settings.json Mutation
**What goes wrong:** The `/brain-setup` skill tries to run `jq` to update settings.json but jq is not on PATH in the hook subprocess environment. The mutation silently fails or generates an error.
**Why it happens:** `jq` is a hard dependency (documented in STATE.md as installed to `~/bin` on Windows — no admin required). But PATH in Claude Code hook subprocesses may not include `~/bin`.
**How to avoid:** Either (a) use `BRAIN_PATH` in `settings.json` that includes `~/bin`, or (b) use a Python-based json mutation as fallback, or (c) have the skill generate the settings.json edit and show it to the user to apply manually as a fallback.
**Warning signs:** Settings.json mutation step completes without error message but BRAIN_PATH doesn't appear in the file.

### Pitfall 5: Deploying brain-mode.md to Wrong Location
**What goes wrong:** `brain-mode.md` placed in `.claude/agents/` (project scope) instead of `~/.claude/agents/` (user scope). Works when running `claude` from the brain-toolkit project directory but not from other project directories.
**Why it happens:** Project agents have a higher priority but narrower scope than user agents.
**How to avoid:** For Phase 3, deploy to `~/.claude/agents/brain-mode.md`. The project `.claude/settings.json` can reference it with `agent: brain-mode`.
**Warning signs:** `claude --agent brain-mode` works only from the brain-toolkit directory.

### Pitfall 6: skills Frontmatter Uses Directory Name Instead of SKILL.md name Field
**What goes wrong:** Skill directory is `brain-audit/` but `SKILL.md` has `name: brain-audit-tool`. The `skills: [brain-audit]` reference doesn't resolve because resolution uses the `name` field, not the directory name.
**Why it happens:** Claude Code resolves skills by their `name` frontmatter field.
**How to avoid:** Verify that the `name:` field in each brain-* SKILL.md matches what will be written in `brain-mode.md`'s `skills:` list.
**Warning signs:** Same as Pitfall 1 — silent failure to preload.

---

## Code Examples

### brain-mode.md Agent Definition (template)

```markdown
---
name: brain-mode
description: Personal knowledge brain. Loads vault context, captures learnings, guides first-time setup. Use for any Claude Code session where the user wants brain features active.
tools: Read, Write, Edit, Bash, Grep, Glob, Agent
model: inherit
---

You are Claude in brain mode — a knowledge-aware assistant that actively manages a personal vault.

## Vault Location

Your brain vault is at the path in BRAIN_PATH. All brain operations read from and write to this directory.

## Session Start Behavior

At the start of each session, the SessionStart hook injects a brain context summary. If you see `"degraded": true` in any hook output, trigger the onboarding skill immediately:

  /brain-setup

## When Vault Is Configured and Loaded

Use the preloaded skills (brain-capture, daily-note, brain-audit) proactively:
- After significant work blocks or commits: offer to run brain-capture
- At session end: trigger daily-note if there are learnings worth capturing
- When the user asks about past work: consult the vault context injected at session start

## When User Is First-Time or Vault Has Moved

If `degraded: true` appears in session context, run /brain-setup immediately. Do not attempt vault operations until setup completes.
```

### settings.json agent Default

```json
{
  "agent": "brain-mode",
  "hooks": {
    "SessionStart": [ ... existing hooks ... ]
  }
}
```

### /brain-setup Skill (SKILL.md)

```markdown
---
name: brain-setup
description: First-time onboarding wizard for Claude Brain. Guides the user through creating a vault directory and configuring BRAIN_PATH. Run this when BRAIN_PATH is unset or the vault directory is missing.
disable-model-invocation: true
---

You are running the Claude Brain setup wizard. Walk the user through the following steps conversationally, one step at a time.

## Step 1: Identify the Case

Check the session context for the degraded signal:
- If `"error":"BRAIN_PATH is not set"` → Run the NEW VAULT flow (Step 2A)
- If `"offer_create":true` → Run the MISSING DIRECTORY flow (Step 2B)

## Step 2A: New Vault Flow (BRAIN_PATH unset)

Ask the user:
  "Where do you want your brain vault? This is where Claude stores notes, pitfalls, and session learnings.
   Examples: ~/Documents/claude_brain  or  ~/brain"

When they provide a path:
1. Expand ~ to $HOME
2. Run: mkdir -p "<their path>"
3. Update ~/.claude/settings.json env block with BRAIN_PATH
4. Update shell profile with export BRAIN_PATH="<their path>"
5. Show confirmation and next steps

## Step 3: Write BRAIN_PATH to settings.json

Run this bash command to update settings.json (uses jq, preserving all existing keys):

  BRAIN_PATH_VALUE="<their chosen path>"
  SETTINGS="$HOME/.claude/settings.json"
  jq --arg p "$BRAIN_PATH_VALUE" '.env.BRAIN_PATH = $p' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"

## Step 4: Write BRAIN_PATH to shell profile

Detect the user's shell profile and append (idempotent):
  - ~/.zshrc if it exists
  - ~/.bash_profile if it exists
  - ~/.bashrc if it exists
  - ~/.bashrc (create it) if none exist

Only append if BRAIN_PATH is not already in the file.

## Step 5: Confirm and instruct restart

Tell the user:
  "Setup complete. BRAIN_PATH is now set to: <path>
   Please restart Claude Code so the new env var takes effect.
   After restarting, run 'claude' from any directory — brain mode will be active."
```

### Programmatic settings.json env update

```bash
# Source: official docs + verified pattern
# Safely adds/updates BRAIN_PATH in ~/.claude/settings.json
# Requires: jq 1.6+, preserves all existing settings keys

SETTINGS="$HOME/.claude/settings.json"
BRAIN_PATH_VALUE="$1"

# Create settings file if it doesn't exist
if [ ! -f "$SETTINGS" ]; then
  printf '{"env":{}}\n' > "$SETTINGS"
fi

# Merge: add or update env.BRAIN_PATH, preserve all other keys
jq --arg p "$BRAIN_PATH_VALUE" '.env.BRAIN_PATH = $p' "$SETTINGS" > "$SETTINGS.tmp" \
  && mv "$SETTINGS.tmp" "$SETTINGS"
```

### Shell profile update (idempotent)

```bash
# Detect which profile exists
if [ -f "$HOME/.zshrc" ]; then
  PROFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
  PROFILE="$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
  PROFILE="$HOME/.bashrc"
else
  PROFILE="$HOME/.bashrc"
fi

# Write only if not already configured
if ! grep -q 'BRAIN_PATH' "$PROFILE" 2>/dev/null; then
  printf '\n# Claude Brain vault path\nexport BRAIN_PATH="%s"\n' "$BRAIN_PATH_VALUE" >> "$PROFILE"
  printf "Written to %s\n" "$PROFILE"
else
  printf "BRAIN_PATH already in %s — skipping\n" "$PROFILE"
fi
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `--system-prompt` flag for custom agent identity | `--agent` flag + agent `.md` file | Subagents feature (v2.x) | Skills preloading, tool restrictions, model selection all supported in agent definition; `--system-prompt` supports none of these |
| `.claude/commands/` for slash commands | `.claude/skills/` (commands merged into skills) | Skills update (2025/2026) | Skills add directory support, frontmatter control, `context: fork`, automatic discovery — use skills going forward |
| `Task` tool for spawning subagents in agent definitions | `Agent` tool | v2.1.63 | `Task(...)` still works as alias but `Agent` is the canonical name. Use `Agent` in tools list and `Agent(subagent-name)` syntax for restrictions. |

**Note on skills vs commands:** The official docs state: "Custom commands have been merged into skills." Files in `.claude/commands/` still work, but `.claude/skills/` is the recommended path going forward. The existing `onboarding-kit/commands/brain/scan.md` still functions but should be migrated to `.claude/skills/` pattern in a future cleanup phase.

---

## Open Questions

1. **Does `skills:` preloading work if skills use `{{BRAIN_PATH}}` placeholder templates?**
   - What we know: The brain-capture and daily-note skills in `global-skills/` contain `{{BRAIN_PATH}}` placeholder text that was meant to be substituted during setup.
   - What's unclear: If those templates are injected verbatim, Claude will see literal `{{BRAIN_PATH}}` in the skill instructions, not the actual path. This may break skill behavior.
   - Recommendation: Before listing skills in brain-mode.md, verify that the installed skills have had their `{{BRAIN_PATH}}` replaced. The onboarding flow must substitute these during install. Alternatively, refactor skills to use `$BRAIN_PATH` env var reference directly (relies on Claude Code's string substitution or Claude reading the env at runtime).

2. **What version of Claude Code is the user running?**
   - What we know: The `agent` field in settings.json and the full subagents frontmatter schema require v2.1.79+ (based on Phase 1 research baseline).
   - What's unclear: The exact minimum version for `skills:` frontmatter in agent definitions.
   - Recommendation: Check Claude Code version in the onboarding skill and warn if below a minimum version.

3. **Does `skills:` in brain-mode.md inject skills even when brain-mode is launched as the main thread (not a spawned subagent)?**
   - What we know: Official docs say skills in subagent `skills:` frontmatter are injected at startup when that subagent is running.
   - What's unclear: When `claude --agent brain-mode` makes brain-mode the main thread, the docs say "the subagent's system prompt replaces the default Claude Code system prompt entirely." It's not explicitly documented whether the `skills:` field still fires when the agent IS the main thread.
   - Recommendation: This requires a live test. Phase 3 must include a verification step: launch `claude --agent brain-mode`, run `/context`, check whether brain-* skill content appears.

4. **Windows Git Bash: no shell profile files exist for this user**
   - What we know: Checked `~/.bashrc`, `~/.bash_profile`, `~/.zshrc`, `~/.profile` — none exist for this machine.
   - What's unclear: Where Git Bash for Windows loads env vars if none of these files exist.
   - Recommendation: The onboarding wizard should create `~/.bashrc` as the fallback if none exist. Also: since this is a Windows machine, the settings.json env block becomes the primary reliable channel, and the shell profile write is secondary/advisory. Document this clearly in the wizard's output.

---

## Sources

### Primary (HIGH confidence)
- `https://code.claude.com/docs/en/sub-agents` — Full subagents API: frontmatter fields, `--agent` flag, `skills:` preloading, `agent` field in settings.json, priority scopes
- `https://code.claude.com/docs/en/settings` — `settings.json` `env` block, `agent` field, all available settings keys
- `https://code.claude.com/docs/en/skills` — Skills frontmatter, discovery locations, `disable-model-invocation`, skills vs commands merge

### Secondary (MEDIUM confidence)
- Phase 1 RESEARCH.md (this codebase) — confirmed `jq` hard dependency, hook script patterns, exit code discipline
- Phase 2 RESEARCH.md (this codebase) — confirmed `additionalContext` mechanism, dual-channel errors in brain-path.sh
- Phase 2 VERIFICATION.md (this codebase) — deployment gap: hooks exist in repo but NOT deployed to `~/.claude/hooks/` — Phase 3 onboarding must address this

### Tertiary (LOW confidence — requires live verification)
- Whether `skills:` field fires when agent runs as main thread (not spawned subagent) — official docs imply yes but don't explicitly confirm
- Whether `{{BRAIN_PATH}}` template literals in skill content break when injected via `skills:` preloading

---

## Metadata

**Confidence breakdown:**
- Subagent mechanics (`--agent`, frontmatter, `skills:` field): HIGH — verified against official docs
- settings.json `env` block and `agent` field: HIGH — verified against official docs
- Onboarding shell patterns (profile detection, jq mutation): MEDIUM — standard bash, but Windows behavior is confirmed limited (no profiles exist)
- skills preloading as main thread: LOW — live test required
- `{{BRAIN_PATH}}` template behavior under skills preloading: LOW — live test required

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (30 days — Claude Code is fast-moving but subagents API is now stable)

---

## Critical Deployment Gap from Phase 2 Verification

Phase 2 verification found that hook scripts exist in the repo (`hooks/session-start.sh`, etc.) but are NOT deployed to `~/.claude/hooks/`. Phase 3 onboarding is the right place to fix this: the `/brain-setup` skill or the `setup.sh` script must copy hooks to `~/.claude/hooks/` and register them in `~/.claude/settings.json`.

This means Phase 3 scope includes:
1. Deploy `brain-mode.md` to `~/.claude/agents/`
2. Deploy brain-* skills to `~/.claude/skills/` (with `{{BRAIN_PATH}}` substituted)
3. Deploy hook scripts to `~/.claude/hooks/`
4. Register hooks in `~/.claude/settings.json`
5. Write BRAIN_PATH to settings.json env block and shell profile
6. Set `agent: brain-mode` in project `.claude/settings.json`

The `/brain-setup` skill orchestrates steps 1–5 for new users. Step 6 is committed to the repo as part of Phase 3 implementation.
