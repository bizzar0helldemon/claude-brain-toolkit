---
name: brain-setup
description: First-time onboarding wizard for Claude Brain. Guides the user through creating a vault directory and configuring BRAIN_PATH. Run this when BRAIN_PATH is unset or the vault directory is missing.
---

# Brain Setup — Onboarding Wizard

You are guiding the user through first-time Claude Brain setup. Determine which case applies, then follow the corresponding flow.

## Case A: BRAIN_PATH Unset

**Triggered when:** session context contains `"error":"BRAIN_PATH is not set"`, or when the user runs `/brain-setup` with no BRAIN_PATH in the environment.

### Flow

1. Ask the user where they want their brain vault. Suggest examples:
   - `~/Documents/claude-brain`
   - `~/brain`
   - `~/Desktop/claude-brain`

   Explain briefly: "This is a directory on your machine where Claude Brain stores your notes, project catalog, session logs, and pattern library."

2. When the user provides a path, execute these steps:

**a. Expand and create the directory:**
```bash
BRAIN_PATH_VALUE=$(eval echo "<user-provided-path>")
mkdir -p "$BRAIN_PATH_VALUE"
```

**b. Write BRAIN_PATH to settings.json:**
```bash
SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
  printf '{}\n' > "$SETTINGS"
fi
jq --arg p "$BRAIN_PATH_VALUE" '.env.BRAIN_PATH = $p' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

If `jq` is not available, use the Write/Edit tool to open `~/.claude/settings.json` directly and add `"BRAIN_PATH": "<path>"` under the `"env"` key.

**c. Write BRAIN_PATH to shell profile:**
```bash
if [ -f "$HOME/.zshrc" ]; then
  PROFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
  PROFILE="$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
  PROFILE="$HOME/.bashrc"
else
  PROFILE="$HOME/.bashrc"
fi

if ! grep -q 'BRAIN_PATH' "$PROFILE" 2>/dev/null; then
  printf '\n# Claude Brain vault path\nexport BRAIN_PATH="%s"\n' "$BRAIN_PATH_VALUE" >> "$PROFILE"
fi
```

> **Note: On Windows with Git Bash**, shell profile files may not be loaded by hooks (non-interactive subshells bypass `.bashrc`/`.zshrc`). The `settings.json` env block is the primary reliable channel for delivering `BRAIN_PATH` to hooks on Windows. The shell profile export is a convenience for interactive terminal use — add it, but don't depend on it alone.

**d. Scaffold the vault from the skeleton.** `setup.sh` staged canonical templates and index files at `~/.claude/brain-skeleton/`. Copy them into the new vault so skills like `brain-scan`, `brain-inbox`, and `brain-intake` have their templates (`brain-scan-templates.md`, the `_INDEX.md` files, structural dirs). Non-destructive — never overwrite files the user already has:

```bash
SKEL="$HOME/.claude/brain-skeleton"
if [ -d "$SKEL" ]; then
  cp -rn "$SKEL"/. "$BRAIN_PATH_VALUE"/   # -n = no-clobber; .gitkeep files keep empty dirs
fi
```

If the skeleton directory is absent (older install), continue — the next step still seeds `IDENTITY.md` directly.

**e. Seed the identity profile.** Every brain has an `IDENTITY.md` — the document that tells Claude who the user is (not just their code). Create it now if absent so the user has something to fill via `/brain-intake`:

```bash
if [ ! -f "$BRAIN_PATH_VALUE/IDENTITY.md" ]; then
  if [ -f "$BRAIN_PATH_VALUE/IDENTITY.template.md" ]; then
    cp "$BRAIN_PATH_VALUE/IDENTITY.template.md" "$BRAIN_PATH_VALUE/IDENTITY.md"
  else
    cat > "$BRAIN_PATH_VALUE/IDENTITY.md" <<'IDENTITY_EOF'
---
title: "Identity Profile"
type: identity
tags: [identity, personal, profile]
---

# Identity Profile

> Who you are as a person, not just your code. Fill this in through `/brain-intake` sessions or by editing directly.

## Life Story

> [NEEDS INTAKE] Background, formative experiences, what shaped you.

## Career History

> [NEEDS INTAKE] Professional path, roles, what you've built.

## Creative Voice

> [NEEDS INTAKE] What you make, why you make it, your aesthetic.

## Values & Worldview

> [NEEDS INTAKE] What you believe and how you see the world.

## Communication Preferences

> [NEEDS INTAKE] Tone, length, challenge level, humor, pet peeves.
IDENTITY_EOF
  fi
fi
```

3. Show confirmation:
   > "Vault created at `<path>`. BRAIN_PATH written to `settings.json` and `<profile>`. Seeded an empty `IDENTITY.md`."

4. Instruct the user to restart Claude Code, then point them at intake:
   > "Please restart Claude Code (`/exit` then `claude`) so the new BRAIN_PATH takes effect. After restarting, run **`/brain-intake`** to tell the brain who you are — or **`/brain-onboard`** for the full guided walkthrough (identity → discover existing content → process inbox → catalog projects)."

---

## Case B: BRAIN_PATH Set but Directory Missing

**Triggered when:** session context contains `"offer_create": true`.

### Flow

1. Tell the user:
   > "Your BRAIN_PATH is set to `$BRAIN_PATH` but that directory doesn't exist."

2. Offer two choices:
   - **Create it at the current path** — run `mkdir -p "$BRAIN_PATH"`, then scaffold from the skeleton and seed the identity profile (run the Case A step 2d scaffold block and step 2e `IDENTITY.md` seeding block, using `$BRAIN_PATH` in place of `$BRAIN_PATH_VALUE`). Confirm: "Directory created, scaffolded from skeleton, and `IDENTITY.md` seeded. No restart needed — BRAIN_PATH is already configured. Run `/brain-intake` to tell the brain who you are, or `/brain-onboard` for the full guided walkthrough."
   - **Update BRAIN_PATH to a new location** — follow Case A flow from step 1.
