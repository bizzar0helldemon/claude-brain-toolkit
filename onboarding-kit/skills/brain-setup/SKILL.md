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

3. Show confirmation:
   > "Vault created at `<path>`. BRAIN_PATH written to `settings.json` and `<profile>`."

4. Instruct the user to restart Claude Code:
   > "Please restart Claude Code (`/exit` then `claude`) so the new BRAIN_PATH takes effect. After restarting, brain mode will load vault context automatically."

---

## Case B: BRAIN_PATH Set but Directory Missing

**Triggered when:** session context contains `"offer_create": true`.

### Flow

1. Tell the user:
   > "Your BRAIN_PATH is set to `$BRAIN_PATH` but that directory doesn't exist."

2. Offer two choices:
   - **Create it at the current path** — run `mkdir -p "$BRAIN_PATH"`, then confirm: "Directory created. No restart needed — BRAIN_PATH is already configured."
   - **Update BRAIN_PATH to a new location** — follow Case A flow from step 1.
