---
name: brain-relocate
description: Move your vault to a new location — updates BRAIN_PATH in settings.json and shell profile
---

## Purpose

Relocate your brain vault to a new path. Updates BRAIN_PATH in both `~/.claude/settings.json` (used by hooks) and your shell profile (used by terminal), then verifies the new path is functional. No manual config surgery needed.

## Steps

### 1. Determine current state

Read the current BRAIN_PATH from the environment and from settings.json:

```bash
echo "ENV: BRAIN_PATH=$BRAIN_PATH"
jq -r '.env.BRAIN_PATH // "not set"' ~/.claude/settings.json
```

Tell the user their current vault path. If BRAIN_PATH is not set in either location, tell the user to run `/brain-setup` instead and stop — relocation requires an existing configuration.

### 2. Get the new path

If `$ARGUMENTS` is provided (user typed `/brain-relocate /new/path`), use it as the new path.

Otherwise ask: "Where is the new vault location?"

### 3. Validate the new path

Expand the path (handle `~` and `$HOME`):

```bash
NEW_PATH=$(eval echo "<user-provided-path>")
```

Check whether the directory exists:

```bash
[ -d "$NEW_PATH" ]
```

If it does not exist, ask whether to create it or if they meant a different path. If creating:

```bash
mkdir -p "$NEW_PATH"
```

### 4. Optionally copy vault contents

Only offer this if the OLD path exists AND the NEW path is empty (no files):

```bash
OLD_PATH="$BRAIN_PATH"
[ -d "$OLD_PATH" ] && [ -z "$(ls -A "$NEW_PATH" 2>/dev/null)" ]
```

If the user wants to copy:

```bash
cp -r "$OLD_PATH"/. "$NEW_PATH"/
```

This copies hidden files too. After copying, check for broken symlinks (informational, not blocking):

```bash
find "$NEW_PATH" -type l ! -exec test -e {} \; -print
```

If the user does not want to copy, that's fine — they may have already moved the files manually or are starting fresh.

**Important:** Never use `mv` to physically move the vault. Use `cp -r` for safety — the user can delete the old copy themselves after confirming everything works.

### 5. Update settings.json (jq atomic write)

```bash
SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
  printf '{"env":{}}\n' > "$SETTINGS"
fi
jq --arg p "$NEW_PATH" '.env.BRAIN_PATH = $p' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

### 6. Update shell profile (portable sed, NO sed -i)

Detect the active shell profile — check in order: `~/.zshrc`, `~/.bash_profile`, `~/.bashrc`. Use the first one that exists.

If the profile already contains `export BRAIN_PATH=`, replace it:

```bash
PROFILE="<detected profile>"
sed 's|^export BRAIN_PATH=.*|export BRAIN_PATH="'"$NEW_PATH"'"|' "$PROFILE" > "$PROFILE.tmp" && mv "$PROFILE.tmp" "$PROFILE"
```

If no match exists, append:

```bash
printf '\n# Claude Brain vault path\nexport BRAIN_PATH="%s"\n' "$NEW_PATH" >> "$PROFILE"
```

If a line contains `BRAIN_PATH=` but without the `export` keyword, warn the user about the non-standard line and recommend they remove it manually.

**Important:** Never use `sed -i` (GNU vs BSD incompatibility). Always use temp file + mv.

### 7. Post-relocate verification

Read back from settings.json and confirm it matches:

```bash
VERIFY_PATH=$(jq -r '.env.BRAIN_PATH' ~/.claude/settings.json)
echo "settings.json BRAIN_PATH: $VERIFY_PATH"
```

Check the directory exists and is readable:

```bash
[ -d "$NEW_PATH" ] && echo "Directory exists and is accessible"
```

Check for vault structure (warn but don't fail if empty/new vault):

```bash
if [ -d "$NEW_PATH/brain-mode" ] || [ -f "$NEW_PATH/.brain-state" ]; then
  echo "Vault structure detected"
else
  echo "Note: No existing vault structure found — this is fine for a fresh vault"
fi
```

### 8. Confirm and instruct restart

Report success with a checklist:

- settings.json updated with new BRAIN_PATH
- Shell profile (`<which file>`) updated with new BRAIN_PATH
- Vault directory verified at new path

Tell the user which profile file was updated so they know where to look.

**MUST tell the user:** "Restart any open Claude Code sessions for the new vault path to take effect in hooks."

## Notes

- Always double-quote `"$NEW_PATH"` and `"$OLD_PATH"` in every command — paths may contain spaces.
- This command updates the pointers, not the vault itself. The user is responsible for ensuring their files are at the new path (either via the copy option or by moving them beforehand).
- If something goes wrong mid-relocation, the user can always run this command again with the correct path — every step is idempotent.
