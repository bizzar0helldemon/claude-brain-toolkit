# Phase 10: Vault Relocation - Research

**Researched:** 2026-03-21
**Domain:** Vault path management, settings.json mutation, shell profile editing, Claude Code slash commands/skills
**Confidence:** HIGH

## Summary

Phase 10 delivers a `/brain-relocate` slash command that updates BRAIN_PATH in both `~/.claude/settings.json` and the user's shell profile when they move their vault to a new location. This is a LOW-complexity feature that closes the loop on the "vault has moved" error path already surfaced by `brain_path_validate` in `lib/brain-path.sh`. The implementation requires one new markdown file (the slash command definition), one deployment update to `setup.sh`, and one minor update to `brain-mode.md` to list the new command.

The existing codebase already contains all the patterns needed. The `brain-setup` skill (Phase 3) established the exact patterns for writing BRAIN_PATH to both settings.json and shell profiles. The `brain-add-pattern` slash command established the format for Claude-orchestrated slash commands. The `jq` atomic write pattern (temp file + mv) is used throughout the hooks library. Vault relocation reuses all of these -- the only new element is the sed-based replacement of an existing `export BRAIN_PATH=` line in the shell profile (brain-setup only appends; relocate must replace).

The critical constraint is the dual-channel update requirement: settings.json `env.BRAIN_PATH` is what hooks actually read (non-interactive subshells don't load shell profiles), while the shell profile export is for interactive terminal convenience. Both MUST be updated, and the user MUST be told to restart Claude Code sessions for the change to take effect. This is extensively documented in prior research (Phase 3 RESEARCH.md, v1.2 PITFALLS.md).

**Primary recommendation:** Implement as a slash command at `commands/brain-relocate.md`, following the exact format of `commands/brain-add-pattern.md`. The command is Claude-orchestrated (uses Bash, Read, Write tools), not a standalone shell script. No new shell library functions needed.

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Slash command (`.md`) | -- | `/brain-relocate` definition | Established pattern: `commands/brain-add-pattern.md` |
| `jq` | 1.6+ | Atomic settings.json mutation | Already a hard dependency; used throughout codebase |
| `sed` (POSIX) | -- | Shell profile line replacement | Portable across macOS, Linux, Git Bash; no GNU `-i` flag needed |
| `cp -r` | -- | Vault directory copy (if user wants to copy, not just re-point) | Standard POSIX; safer than `mv` for data preservation |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| `brain_path_validate` | existing | Post-relocate verification | After updating BRAIN_PATH, source brain-path.sh and call validate to confirm new path works |
| `find -type l` | POSIX | Broken symlink detection | Post-copy verification when vault is physically moved |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Slash command (`.md` in `commands/`) | Skill (`.md` in `global-skills/`) | Both work. Slash command is simpler (single file, no SKILL.md wrapper), matches `brain-add-pattern` precedent, and is appropriate for a single-purpose utility |
| `sed` for profile replacement | Direct file read + write via Claude tools | `sed` with temp+mv is atomic and handles edge cases; Claude Read/Write works too but is less reliable for line-level replacement in shell profiles |
| `cp -r` then verify then optionally remove old | `mv` directly | `cp` is safer -- if copy fails, old vault is intact. `mv` across filesystems silently falls back to cp+rm anyway |

## Architecture Patterns

### File Locations

```
# New files (source repo)
commands/brain-relocate.md              # Slash command definition

# New files (deployed to ~/.claude/)
~/.claude/commands/brain/brain-relocate.md   # Deployed copy

# Modified files
onboarding-kit/setup.sh                # Add brain-relocate to deployment
agents/brain-mode.md                    # Add /brain-relocate to Available Skills
```

### Slash Command Format

The command follows the exact format established by `brain-add-pattern.md`:

```markdown
---
name: brain-relocate
description: Move your brain vault to a new location. Updates BRAIN_PATH in settings.json and shell profile.
---

[Step-by-step instructions for Claude to follow]
```

Key: This is a Claude-orchestrated command. Claude reads the instructions and executes the steps using Bash, Read, Write, and Edit tools. There is no standalone shell script -- Claude IS the orchestrator.

### Pattern 1: Dual-Channel BRAIN_PATH Update

**What:** BRAIN_PATH must be updated in TWO places for relocation to be complete.
**When to use:** Every time BRAIN_PATH changes.

**settings.json update (jq atomic write):**
```bash
SETTINGS="$HOME/.claude/settings.json"
NEW_PATH="/new/vault/path"
jq --arg p "$NEW_PATH" '.env.BRAIN_PATH = $p' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
```

**Shell profile update (sed replacement with fallback to append):**
```bash
# Detect profile
if [ -f "$HOME/.zshrc" ]; then
  PROFILE="$HOME/.zshrc"
elif [ -f "$HOME/.bash_profile" ]; then
  PROFILE="$HOME/.bash_profile"
elif [ -f "$HOME/.bashrc" ]; then
  PROFILE="$HOME/.bashrc"
else
  PROFILE="$HOME/.bashrc"
fi

# Replace existing BRAIN_PATH line, or append if not found
if grep -q 'export BRAIN_PATH=' "$PROFILE" 2>/dev/null; then
  # Use temp+mv pattern (portable, no GNU sed -i)
  sed 's|^export BRAIN_PATH=.*|export BRAIN_PATH="'"$NEW_PATH"'"|' "$PROFILE" > "$PROFILE.tmp" && mv "$PROFILE.tmp" "$PROFILE"
else
  printf '\n# Claude Brain vault path\nexport BRAIN_PATH="%s"\n' "$NEW_PATH" >> "$PROFILE"
fi
```

### Pattern 2: Post-Relocate Verification

**What:** After updating both config targets, verify the new path is functional before declaring success.
**Steps:**
1. Read back `env.BRAIN_PATH` from settings.json -- confirm it matches the new path
2. Check that the new directory exists and is readable
3. Check that key vault files exist at the new path (e.g., `brain-mode/` directory)
4. Optionally: write and read back a test file to confirm write access

```bash
# Verification
VERIFY_PATH=$(jq -r '.env.BRAIN_PATH' "$HOME/.claude/settings.json")
if [ "$VERIFY_PATH" != "$NEW_PATH" ]; then
  echo "ERROR: settings.json update failed. Expected: $NEW_PATH, Got: $VERIFY_PATH"
  exit 1
fi

if [ ! -d "$NEW_PATH" ]; then
  echo "ERROR: New vault directory does not exist: $NEW_PATH"
  exit 1
fi
```

### Pattern 3: Two Relocation Modes

The command should support two distinct scenarios:

**Mode A: Vault already moved (re-point only)**
User has already moved/copied their vault files to a new location. They just need BRAIN_PATH updated. This is the common case (user reorganized their filesystem, changed drives, etc.).

Flow: Validate new path exists -> update settings.json -> update shell profile -> verify -> done.

**Mode B: Move vault to new location (copy + re-point)**
User wants to move the vault. The command copies files, updates config, then optionally removes the old location.

Flow: Validate new path parent exists -> `mkdir -p` new path -> `cp -r` old to new -> verify copy -> update settings.json -> update shell profile -> verify -> optionally remove old path.

### Anti-Patterns to Avoid

- **Updating only one config target:** NEVER update just the shell profile or just settings.json. Both must be updated or the relocation is incomplete.
- **Using `mv` without a copy-first safety net:** `mv` across filesystems is destructive if interrupted. Always `cp -r` first, verify, then optionally remove the old location.
- **Using `sed -i` directly:** GNU and BSD `sed -i` have different syntax (`sed -i ''` vs `sed -i`). Use the portable temp+mv pattern instead.
- **Assuming the change takes effect immediately:** The `env` block in settings.json is read at Claude Code session startup. Running sessions still use the old path until restarted.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON settings mutation | Custom JSON string manipulation | `jq --arg p "$path" '.env.BRAIN_PATH = $p'` with temp+mv | jq handles nested key creation, escaping, preserves all other settings |
| Shell profile detection | Custom platform detection logic | The exact if/elif chain from brain-setup SKILL.md | Already proven, handles all common cases |
| Vault integrity check | Custom file-by-file verification | `[ -d "$NEW_PATH" ] && [ -d "$NEW_PATH/brain-mode" ]` | The vault structure is simple; checking the root dir + brain-mode subdir is sufficient |
| Path expansion | Custom tilde/variable expansion | `eval echo "$USER_PATH"` (same as brain-setup) | Handles `~`, `$HOME`, and other shell expansions |

**Key insight:** Every operation needed for vault relocation already has an established pattern in the codebase. The relocate command is essentially a recombination of brain-setup's config-writing patterns with a sed-based replacement instead of an append.

## Common Pitfalls

### Pitfall 1: Settings.json Not Updated -- Hooks Still Use Old Path
**What goes wrong:** Shell profile is updated but settings.json `env.BRAIN_PATH` is not. Hooks continue writing to the old vault because they read from the env block, not the shell profile.
**Why it happens:** The dual-channel requirement is non-obvious. Most users expect `export BRAIN_PATH` in their shell profile to be sufficient.
**How to avoid:** The slash command updates BOTH targets as mandatory steps. Verification reads back from settings.json to confirm.
**Warning signs:** After relocation, `echo $BRAIN_PATH` shows new path in terminal, but hook output still references old path.

### Pitfall 2: Running Sessions Not Restarted
**What goes wrong:** User relocates vault, but open Claude Code sessions still use the old BRAIN_PATH from when they launched.
**Why it happens:** `env` block values are loaded at session startup, not dynamically refreshed.
**How to avoid:** The command MUST end with an explicit restart instruction: "Restart any open Claude Code sessions for the new vault path to take effect."
**Warning signs:** New captures go to old location until user restarts.

### Pitfall 3: GNU vs BSD sed -i Incompatibility
**What goes wrong:** `sed -i` fails or behaves differently on macOS (BSD) vs Linux (GNU) vs Git Bash (GNU).
**Why it happens:** BSD `sed -i` requires a backup extension argument (`sed -i '' ...`); GNU `sed -i` does not.
**How to avoid:** Never use `sed -i`. Use the portable temp+mv pattern: `sed '...' file > file.tmp && mv file.tmp file`.
**Warning signs:** `sed: 1: "...": extra characters at the end of i command` on macOS.

### Pitfall 4: Spaces in Vault Path
**What goes wrong:** A vault path containing spaces (e.g., `~/My Documents/brain`) breaks unquoted variable expansions in shell commands.
**Why it happens:** Standard shell word-splitting on unquoted variables.
**How to avoid:** Always double-quote `$NEW_PATH` and `$OLD_PATH` in every command. The sed replacement pattern must also handle spaces in the path value.
**Warning signs:** `No such file or directory` errors that reference only part of the path.

### Pitfall 5: Broken Symlinks After Physical Vault Copy
**What goes wrong:** Vault contains symlinks (e.g., Obsidian cross-links). After `cp -r` to a new location, symlinks pointing outside the vault become dangling.
**Why it happens:** `cp -r` copies symlinks as-is; their targets don't move with them.
**How to avoid:** After copy, run a broken symlink check: `find "$NEW_PATH" -type l ! -exec test -e {} \; -print`. Warn the user if any are found. This is an informational warning, not a blocker.
**Warning signs:** `ls -la` in the new vault shows entries with `->` pointing to paths under the old vault root.

### Pitfall 6: settings.json Doesn't Exist or Has No env Block
**What goes wrong:** `jq` command fails because settings.json is missing or malformed.
**Why it happens:** Edge case -- user may have deleted or corrupted settings.json.
**How to avoid:** Create settings.json with `{"env":{}}` if it doesn't exist. The jq `.env.BRAIN_PATH = $p` command creates nested structure automatically, so a missing `env` block is handled.
**Warning signs:** `jq: error: Cannot index null with string "env"` -- this actually won't happen with the `.env.BRAIN_PATH = $p` syntax, which auto-creates intermediate objects.

### Pitfall 7: BRAIN_PATH Line Has Unexpected Format in Shell Profile
**What goes wrong:** The sed replacement pattern `^export BRAIN_PATH=.*` doesn't match because the line uses a different format (e.g., `BRAIN_PATH=` without `export`, or uses single quotes, or has leading whitespace).
**Why it happens:** Users may have manually edited their profile, or a different tool wrote the line.
**How to avoid:** Use a broader grep pattern to detect: `grep -q 'BRAIN_PATH' "$PROFILE"`. Use a broader sed pattern: `sed '/BRAIN_PATH/c\export BRAIN_PATH="'"$NEW_PATH"'"'` to replace any line containing BRAIN_PATH. However, this is aggressive -- the safer approach is to match `export BRAIN_PATH=` and fall back to appending a new line if the pattern isn't found, while warning the user about the existing non-matching line.
**Warning signs:** After relocation, `grep BRAIN_PATH ~/.zshrc` shows two lines with different paths.

## Code Examples

### Complete Slash Command Structure

The `/brain-relocate` command should follow this flow:

```markdown
---
name: brain-relocate
description: Relocate your brain vault to a new path. Updates BRAIN_PATH in settings.json and shell profile.
---

## Purpose

Update BRAIN_PATH when your vault has moved to a new location. This updates both
~/.claude/settings.json (used by hooks) and your shell profile (used by terminal sessions).

## Steps

### 1. Determine current state

Read the current BRAIN_PATH:
- From environment: echo "$BRAIN_PATH"
- From settings.json: jq -r '.env.BRAIN_PATH' ~/.claude/settings.json

Tell the user: "Your current vault path is: [path]"

### 2. Get the new path

Ask the user: "Where is the new vault location?"

If the user provides $ARGUMENTS, use that as the new path.

### 3. Validate the new path

Expand the path (handle ~ and $HOME):
  NEW_PATH=$(eval echo "<user-provided-path>")

Check if the directory exists:
  [ -d "$NEW_PATH" ]

If it doesn't exist, ask: "That directory doesn't exist. Would you like me to create it,
or did you mean a different path?"

### 4. Optionally copy vault contents

If the old BRAIN_PATH exists and the new path is empty, ask:
"Would you like me to copy your vault from [old] to [new]?"

If yes:
  cp -r "$OLD_PATH"/* "$NEW_PATH"/ 2>/dev/null
  cp -r "$OLD_PATH"/.* "$NEW_PATH"/ 2>/dev/null  # hidden files too

### 5. Update settings.json

  SETTINGS="$HOME/.claude/settings.json"
  jq --arg p "$NEW_PATH" '.env.BRAIN_PATH = $p' "$SETTINGS" > "$SETTINGS.tmp" \
    && mv "$SETTINGS.tmp" "$SETTINGS"

### 6. Update shell profile

[detect profile, sed replace or append -- see Pattern 1 above]

### 7. Verify

Read back from settings.json:
  jq -r '.env.BRAIN_PATH' ~/.claude/settings.json

Confirm it matches the new path. Check key vault files exist at the new path.

### 8. Confirm and instruct restart

Tell the user:
  "Vault relocated successfully.
   - settings.json: updated
   - Shell profile ([profile]): updated
   - Vault at new path: verified

   Please restart Claude Code for the change to take effect in hooks."
```

### settings.json Atomic Update (Verified Pattern)

```bash
# Source: onboarding-kit/setup.sh, brain-setup SKILL.md
# Preserves all existing settings keys; creates env block if needed
SETTINGS="$HOME/.claude/settings.json"
NEW_PATH="/path/to/new/vault"

if [ ! -f "$SETTINGS" ]; then
  printf '{"env":{}}\n' > "$SETTINGS"
fi

jq --arg p "$NEW_PATH" '.env.BRAIN_PATH = $p' "$SETTINGS" > "$SETTINGS.tmp" \
  && mv "$SETTINGS.tmp" "$SETTINGS"
```

### Shell Profile sed Replacement (Portable Pattern)

```bash
# Source: v1.2 Architecture research
# Portable: no sed -i, uses temp+mv
PROFILE="$HOME/.zshrc"  # or detected profile
NEW_PATH="/path/to/new/vault"

if grep -q 'export BRAIN_PATH=' "$PROFILE" 2>/dev/null; then
  sed 's|^export BRAIN_PATH=.*|export BRAIN_PATH="'"$NEW_PATH"'"|' "$PROFILE" > "$PROFILE.tmp" \
    && mv "$PROFILE.tmp" "$PROFILE"
else
  printf '\n# Claude Brain vault path\nexport BRAIN_PATH="%s"\n' "$NEW_PATH" >> "$PROFILE"
fi
```

### Post-Relocate Verification

```bash
# Verify settings.json was updated
VERIFY_PATH=$(jq -r '.env.BRAIN_PATH' "$HOME/.claude/settings.json")
if [ "$VERIFY_PATH" = "$NEW_PATH" ]; then
  echo "settings.json: OK"
else
  echo "settings.json: FAILED (expected $NEW_PATH, got $VERIFY_PATH)"
fi

# Verify vault is accessible
if [ -d "$NEW_PATH" ]; then
  echo "Directory exists: OK"
else
  echo "Directory exists: FAILED"
fi

# Verify key vault structure
if [ -d "$NEW_PATH/brain-mode" ] || [ -f "$NEW_PATH/.brain-state" ]; then
  echo "Vault structure: OK"
else
  echo "Vault structure: WARNING (empty or new vault)"
fi
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual editing of settings.json + shell profile | `/brain-relocate` command automates both | Phase 10 (this phase) | Users no longer need to know about the dual-channel requirement |
| `brain_path_validate` error message tells user to update manually | `/brain-relocate` is the action to take | Phase 10 | Closes the error-to-action loop |

**Existing infrastructure this builds on:**
- `brain-setup` SKILL.md -- established all config-writing patterns (Phase 3)
- `brain-add-pattern` command -- established slash command format (Phase 9)
- `brain_path_validate` in `lib/brain-path.sh` -- already surfaces the "vault moved" error case
- `jq` atomic write pattern -- used throughout hooks library

## Deployment Checklist

Files to create:
1. `commands/brain-relocate.md` -- the slash command definition (source repo)

Files to modify:
2. `onboarding-kit/setup.sh` -- add deployment line for brain-relocate.md to `~/.claude/commands/brain/`
3. `agents/brain-mode.md` -- add `/brain-relocate` to the Available Skills/Commands section

Deployment target:
- `~/.claude/commands/brain/brain-relocate.md` -- deployed by setup.sh

## Open Questions

1. **Should the command offer to physically move vault files, or just re-point BRAIN_PATH?**
   - What we know: Architecture research says support both modes (re-point only vs copy+re-point). The FEATURES.md says "move the vault directory" as step 1.
   - What's unclear: Whether physical file copying should be the default or an opt-in step.
   - Recommendation: Default to re-point only (Mode A). Offer to copy files only if the old path exists and the new path is empty. This is the safer default -- most users who run `/brain-relocate` have already moved their files.

2. **Should the command handle the case where BRAIN_PATH is currently unset?**
   - What we know: If BRAIN_PATH is unset, `/brain-setup` is the appropriate command.
   - What's unclear: Whether `/brain-relocate` should redirect to `/brain-setup` or handle this case itself.
   - Recommendation: If BRAIN_PATH is unset, tell the user: "BRAIN_PATH is not currently set. Use `/brain-setup` for first-time vault configuration." Keep the commands focused on their distinct use cases.

3. **Windows path handling: forward slashes vs backslashes?**
   - What we know: Git Bash on Windows handles forward slashes fine. The existing setup.sh and hooks all use forward slashes. settings.json stores paths with forward slashes.
   - What's unclear: Whether a user might provide a Windows-native path with backslashes.
   - Recommendation: Accept the path as-is. If the user provides backslashes, the command should still work since Git Bash and jq handle both. No normalization needed -- this is a Claude-orchestrated command, so Claude can handle path format issues conversationally.

## Sources

### Primary (HIGH confidence)
- `onboarding-kit/setup.sh` -- existing BRAIN_PATH setup patterns, settings.json merge, deployment flow
- `onboarding-kit/skills/brain-setup/SKILL.md` -- established dual-channel update pattern, shell profile detection, jq atomic write
- `commands/brain-add-pattern.md` -- established slash command format for Claude-orchestrated commands
- `hooks/lib/brain-path.sh` -- `brain_path_validate` function, existing error messages for vault-moved case
- `settings.json` -- current structure showing `env.BRAIN_PATH` location
- `.planning/research/ARCHITECTURE.md` -- v1.2 architecture decisions for ONBR-03
- `.planning/research/PITFALLS.md` -- vault relocate pitfalls (Pitfall 2 and Pitfall 5)
- `.planning/research/FEATURES.md` -- ONBR-03 feature specification
- `.planning/phases/03-onboarding-entry-point/03-RESEARCH.md` -- dual-channel persistence pattern

### Secondary (MEDIUM confidence)
- `.planning/research/STACK.md` -- confirmed jq and sed as standard tools for this operation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already in use, patterns established in codebase
- Architecture: HIGH -- slash command format proven, dual-channel update documented extensively
- Pitfalls: HIGH -- vault relocate pitfalls explicitly researched in v1.2 PITFALLS.md
- Code examples: HIGH -- all patterns derived from existing codebase, not hypothetical

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (30 days -- stable domain, no external dependencies changing)
