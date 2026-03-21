# Stack Research

**Domain:** Claude Code CLI extension — brain mode v1.2 additions (idle detection, vault relocate, pattern encounter tracking)
**Researched:** 2026-03-21
**Confidence:** MEDIUM-HIGH (Notification hook behavior sourced from official docs + multiple GitHub issues; `messageIdleNotifThresholdMs` LOW confidence — single GitHub comment, not in official docs)

---

> **Scope note:** This is a SUBSEQUENT MILESTONE research file focused exclusively on stack additions and changes needed for v1.2 features. The existing stack (Bash 3.2+/zsh 5.0+, jq 1.7.1, Claude Code hooks, skills, statusline, agents, BRAIN_PATH, pattern-store.json, .brain-state) is already validated. This file does not repeat that baseline — it only documents what changes.

---

## Summary of New Requirements Per Feature

| Feature | What It Needs | Stack Impact |
|---------|--------------|--------------|
| **Idle detection** | A hook event that fires when Claude has been idle for 60 seconds | New hook event type: `Notification` with `matcher: "idle_prompt"` — no new binaries |
| **Vault relocate** | A skill that updates `BRAIN_PATH` in `~/.claude/settings.json` (env block) and shell profile | `jq` for settings.json update (already present); `sed` for shell profile update (already present on all platforms); no new tools |
| **Pattern encounter tracking** | The `update_encounter_count` function and `encounter_count` field in `pattern-store.json` already exist in `hooks/lib/brain-path.sh` | Already implemented in v1.0/v1.1 — this is a skill/display feature, not a new stack dependency |

---

## Recommended Stack

### Core Technologies

No new core technologies are required. v1.2 reuses the full existing stack. The additions below are configuration surface and hook event types — not new binaries or languages.

| Technology | Version | Purpose in v1.2 | Why |
|------------|---------|-----------------|-----|
| Claude Code `Notification` hook event | v2.1.79+ (current) | Idle detection — fires after 60 seconds of user inactivity | The only native mechanism for detecting when the user has stopped interacting with Claude. Fires with `notification_type: "idle_prompt"` payload. No polling, no background process, no external tool. Confirmed available in current version via official docs. |
| `jq` | 1.7.1 (already installed) | Vault relocate — atomic in-place update of `~/.claude/settings.json` `.env.BRAIN_PATH` field | Already the JSON tool used throughout the toolkit. `jq --arg newpath "$NEW_PATH" '.env.BRAIN_PATH = $newpath'` plus temp+mv handles the settings.json update atomically. No new version needed — 1.7.1 already present. |
| `sed` (POSIX) | System (already present) | Vault relocate — update `BRAIN_PATH=...` line in `~/.zshrc` / `~/.bashrc` / `~/.bash_profile` | Already used in `setup.sh` for template substitution. The vault relocate skill uses `sed` to find and replace the existing `export BRAIN_PATH=...` line in the user's detected shell profile. No new installation. |

### Supporting Libraries / Tools

No new libraries. The pattern encounter tracking machinery (`update_encounter_count`, `init_pattern_store`, `encounter_count` field) is fully implemented in `hooks/lib/brain-path.sh` as of v1.0. What v1.2 adds is a skill that reads and displays that data — pure Bash + jq, zero new dependencies.

| Library/Tool | Version | New Use in v1.2 | Notes |
|---------|---------|----------------|-------|
| `jq` | 1.7.1 | Read `encounter_count` per pattern from `pattern-store.json` for display in pattern summary skill | Already used in `post-tool-use-failure.sh`. The skill reads `.patterns[] | {key, encounter_count, last_seen}` — same `jq` already present. |
| `date -u` | System | Timestamp `last_seen` updates in encounter tracking | Already used throughout `brain-path.sh`. No change. |

### Configuration Changes

These are the only new configuration surface items for v1.2:

| File | Change | Why |
|------|--------|-----|
| `~/.claude/settings.json` | Add `Notification` hook entry with `matcher: "idle_prompt"` | Registers the idle detection hook. The `matcher` field filters so only `idle_prompt` notifications trigger the hook script — not `permission_prompt` or `auth_success`. |
| `~/.claude.json` | Optional: add `"messageIdleNotifThresholdMs": 30000` | Controls how long Claude must be idle before `idle_prompt` fires. Default is 60 seconds. LOW confidence — this setting appeared in a GitHub issue comment (March 2026) claiming implementation but is NOT documented in official `~/.claude.json` settings docs. Do not depend on it; treat as undocumented/experimental. |

### New Hook Event: `Notification` with `idle_prompt` matcher

The `Notification` hook is already available in Claude Code v2.1.79. The `idle_prompt` notification type fires after 60 seconds of user inactivity (Claude is waiting for input, no user action for 60s). This is distinct from the `Stop` hook which fires after every response.

**Configuration pattern (settings.json):**

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notification.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**JSON payload received by the hook script:**

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../session.jsonl",
  "cwd": "/Users/...",
  "hook_event_name": "Notification",
  "message": "Claude is waiting for your input",
  "title": "Idle",
  "notification_type": "idle_prompt"
}
```

**Known reliability issue:** The `notification_type` field was confirmed missing from actual payloads in some Claude Code versions (GitHub issue #11964, closed NOT PLANNED January 2026). If the field is absent, match on the `message` field instead: `jq -r '.message // ""' | grep -qi "waiting"`. Use a defensive fallback.

**Notification hook output:** The `Notification` hook CAN return `additionalContext` to inject into Claude's next context window. Use this to surface the idle state suggestion. It cannot block or suppress the notification.

---

## Vault Relocate: Tool Pattern

The `/brain-relocate` skill is pure Claude Code + Bash + jq + sed — no new binaries. The implementation pattern:

```bash
# 1. Validate new path exists or offer to create it
# 2. Update settings.json (jq atomic write):
jq --arg p "$NEW_PATH" '.env.BRAIN_PATH = $p' ~/.claude/settings.json > /tmp/settings.tmp \
  && mv /tmp/settings.tmp ~/.claude/settings.json

# 3. Update shell profile (sed replacement):
#    Detect profile: ~/.zshrc (zsh), ~/.bashrc (bash), ~/.bash_profile (bash login)
#    Replace existing line or append if absent
PROFILE=$(detect_shell_profile)
sed "s|export BRAIN_PATH=.*|export BRAIN_PATH=\"$NEW_PATH\"|" "$PROFILE" > "$PROFILE.tmp" \
  && mv "$PROFILE.tmp" "$PROFILE"
# If no existing line found, append:
grep -q 'BRAIN_PATH' "$PROFILE" || printf 'export BRAIN_PATH="%s"\n' "$NEW_PATH" >> "$PROFILE"
```

**Cross-platform note for Windows/Git Bash:** `sed` is available in Git Bash. Shell profile is typically `~/.bashrc` or `~/.bash_profile` (not `~/.zshrc`). The skill should detect the shell via `$SHELL` and pick the right profile.

---

## Pattern Encounter Tracking: What Already Exists vs. What v1.2 Adds

The data layer is fully built. v1.2 adds the display layer only.

| Component | Status | File |
|-----------|--------|------|
| `encounter_count` field in pattern-store.json schema | Exists (v1.0) | `hooks/lib/brain-path.sh` `init_pattern_store` |
| `update_encounter_count` function (increments on match) | Exists (v1.0) | `hooks/lib/brain-path.sh` |
| `last_seen` ISO timestamp update | Exists (v1.0) | `hooks/lib/brain-path.sh` |
| `/brain-pattern-summary` skill (reads + displays encounter data) | NEW in v1.2 | New skill file |
| Threshold-based mentoring response changes | NEW in v1.2 | Logic added to `post-tool-use-failure.sh` or new lib function |

The new jq query for reading encounter data (no new tools needed):

```bash
jq -r '.patterns[] | select(.encounter_count > 0) | "\(.encounter_count)x \(.key): \(.solution[0:60])..."' "$PATTERN_STORE"
```

---

## Installation

No new tools to install. All v1.2 features use the existing installation footprint.

```bash
# No new prerequisites.
# Existing requirement check in setup.sh covers everything:
#   node, git, jq, claude -- already verified

# New setup.sh step (to be added for v1.2):
# 1. Deploy ~/.claude/hooks/notification.sh (new hook script)
# 2. Merge Notification hook entry into ~/.claude/settings.json
# 3. Deploy /brain-relocate skill
# 4. Deploy /brain-pattern-summary skill (if implementing display layer)
# 5. chmod +x for new hook scripts
```

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Idle detection mechanism | `Notification` hook with `idle_prompt` matcher | Polling loop in a background process | Background daemon adds complexity, survives past session close, and creates resource risk on Windows. The `Notification` hook is purpose-built for this. |
| Idle detection mechanism | `Notification` hook with `idle_prompt` matcher | `Stop` hook with timestamp comparison | `Stop` fires after every response, not after user inactivity. A timestamp diff could approximate inactivity but is unreliable — the user may have simply stopped typing, not walked away. `idle_prompt` fires on genuine 60-second inactivity. |
| Settings.json update for vault relocate | `jq` atomic update (temp+mv) | `sed -i` in-place on JSON | `sed -i` on JSON is fragile — any nested quote, backslash, or path character can corrupt the file. `jq --arg` handles escaping correctly. Use `sed` only for the shell profile (plain text, predictable line format). |
| Settings.json update for vault relocate | `jq` atomic update | Python `json` module | Python is available but adds startup overhead and requires detecting whether `python3` or `python` is the right binary. `jq` is already required and handles this in one line. |
| Pattern encounter display | New `/brain-pattern-summary` skill | Inline output in `post-tool-use-failure.sh` | The failure hook output goes into `additionalContext` for the immediate error — mixing the summary table into error output creates noise. A dedicated skill lets the user invoke it when they want the overview. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `notification_type` field without fallback | GitHub issue #11964 confirmed the field was missing from actual payloads in some versions (closed NOT PLANNED — no fix shipped). The field may be present in current v2.1.79 but reliability is unconfirmed. | Check `notification_type` first; fall back to matching `.message` content if empty. Defensive: `NTYPE=$(... jq -r '.notification_type // ""'); MSG=$(... jq -r '.message // "")`. Match on either. |
| `messageIdleNotifThresholdMs` as a reliable setting | Not in official `~/.claude.json` documentation. Appeared in one GitHub issue comment (March 2026) claiming implementation. Cannot be verified. | Default to the documented 60-second idle timeout. Do not add this to setup.sh or onboarding. If users want a shorter idle window, document it as an experimental undocumented option. |
| Blocking output from the `Notification` hook | Notification hooks cannot block notifications. If a `decision: block` JSON is returned, it is ignored — Claude does not re-enter a turn. | Use `additionalContext` to inject a suggestion into Claude's next response. The hook is observational, not blocking, for the Notification event. |
| `sed -i` for JSON file editing | `sed -i` flag differs between macOS (`-i ''`) and GNU/Linux (`-i`), and Git Bash on Windows behaves like GNU. More importantly, `sed` on JSON risks corrupting nested structures. | Use `jq` for all JSON edits (settings.json, pattern-store.json). Reserve `sed` for plain-text line substitution in shell profiles only. |
| Writing vault relocate state to a temp `.brain-relocate` file | No intermediate state needed — the update is atomic (temp+mv for settings.json, sed-to-temp+mv for shell profile). A state file adds recovery complexity with no benefit at this scale. | Perform updates in sequence, validate each, and surface any error message to the user directly from the skill. |
| Adding a `Stop` hook for idle detection | `Stop` fires after every response — it is not an idle detector. Building time-since-last-interaction logic on top of `Stop` is unreliable and creates false positives. | Use `Notification` / `idle_prompt`. |

---

## Stack Patterns by Variant

**If `notification_type` field is absent from the payload:**
The `Notification` hook script should check `message` content for idle-related text as a fallback. Extract both fields and gate on either:
```bash
NTYPE=$(printf '%s' "$HOOK_INPUT" | jq -r '.notification_type // ""')
MSG=$(printf '%s' "$HOOK_INPUT" | jq -r '.message // ""')
IS_IDLE=false
if [ "$NTYPE" = "idle_prompt" ] || (printf '%s' "$MSG" | grep -qi "waiting\|idle"); then
  IS_IDLE=true
fi
```

**If running on Windows (Git Bash):**
Shell profile for vault relocate is `~/.bashrc` (or `~/.bash_profile`), not `~/.zshrc`. The skill must detect `$SHELL`:
```bash
case "$SHELL" in
  */zsh) PROFILE="$HOME/.zshrc" ;;
  */bash) PROFILE="$HOME/.bashrc" ;;
  *) PROFILE="$HOME/.bash_profile" ;;
esac
```
`sed` works in Git Bash with GNU syntax (no `-i ''` needed). `jq` works as normal.

**If settings.json has no `env` block yet:**
The `jq` update must handle the case where `.env` is absent:
```bash
jq --arg p "$NEW_PATH" '.env = (.env // {}) | .env.BRAIN_PATH = $p' ~/.claude/settings.json
```
The `(.env // {})` guard prevents `null` from causing the update to fail silently.

**If pattern-store.json is absent or has zero patterns with encounter_count > 0:**
The `/brain-pattern-summary` skill should degrade gracefully: if the store is absent or all `encounter_count` values are 0, output a one-line message ("No patterns encountered yet — add patterns with /brain-add-pattern") rather than an empty table.

---

## Version Compatibility

| Feature | Minimum Version | Notes |
|---------|----------------|-------|
| `Notification` hook event | Claude Code v2.1+ | Available in current v2.1.79. The `idle_prompt` matcher type is documented in current official hooks reference. |
| `Notification` hook `notification_type` field | Unknown — see caveat | Field is documented but was confirmed absent in some versions (issue #11964, closed without fix). Treat as unreliable without fallback logic. |
| `messageIdleNotifThresholdMs` in `~/.claude.json` | Unknown | Not in official docs. LOW confidence. Do not require it. |
| `jq` `.env.BRAIN_PATH` path update | jq 1.6+ | `.env = (.env // {}) | .env.BRAIN_PATH = $p` syntax works in jq 1.6+. 1.7.1 confirmed installed. |
| `sed` for shell profile line replacement | POSIX sed (any) | Uses standard substitute `s|pattern|replacement|` — no GNU extensions needed. Works on macOS BSD sed, GNU sed, and Git Bash sed. |

---

## Sources

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) — HIGH confidence. Official documentation. `Notification` event type, `idle_prompt` matcher, notification payload schema (`session_id`, `transcript_path`, `cwd`, `hook_event_name`, `message`, `title`, `notification_type`), `additionalContext` output support.
- [Claude Code Settings Reference](https://code.claude.com/docs/en/settings) — HIGH confidence. Official documentation. Full `settings.json` schema (no `messageIdleNotifThresholdMs` present). `~/.claude.json` global config fields documented (does not include `messageIdleNotifThresholdMs`).
- [GitHub issue #11964: Notification hook events missing `notification_type` field](https://github.com/anthropics/claude-code/issues/11964) — MEDIUM confidence. Closed NOT PLANNED (January 2026). Confirms `notification_type` field was absent from actual payloads. No fix shipped. Motivates defensive fallback pattern.
- [GitHub issue #13922: Configurable timeout for idle_prompt notification hook](https://github.com/anthropics/claude-code/issues/13922) — LOW confidence for `messageIdleNotifThresholdMs`. Issue documents that `idle_prompt` fires after 60 seconds (MEDIUM confidence, consistent with other sources). A comment from March 6, 2026 claims `messageIdleNotifThresholdMs` was implemented — but this is a single unverified comment, not in official docs.
- [GitHub issue #8320: 60-Second Idle Notifications Not Triggering](https://github.com/anthropics/claude-code/issues/8320) — MEDIUM confidence. Closed NOT PLANNED (January 2026). Confirms `idle_prompt` is designed to fire after genuine 60-second inactivity (not after every response). Related issue #9708 marked COMPLETED suggests underlying execution bug was fixed.
- [GitHub issue #12048: Add notification matcher for when Claude is waiting for user input](https://github.com/anthropics/claude-code/issues/12048) — MEDIUM confidence. Closed as duplicate of #10168. Confirms `idle_prompt` fires after every response in some configurations (contradicts 60-second design). Risk flag: idle_prompt behavior may be inconsistent across versions.
- Existing `hooks/lib/brain-path.sh` — HIGH confidence. Read directly from codebase. Confirms `update_encounter_count`, `init_pattern_store`, `encounter_count` field, and `last_seen` are fully implemented. v1.2 pattern tracking requires no new data layer code.
- Existing `onboarding-kit/setup.sh` — HIGH confidence. Read directly from codebase. Confirms `jq` atomic write pattern (temp+mv) and `sed` template substitution are already established patterns in the toolkit. Vault relocate follows identical approach.
- Live Claude Code v2.1.79 — confirmed via `claude --version`. jq 1.7.1 confirmed via `jq --version`. Both on the development machine (Windows 10, 2026-03-21).

---

*Stack research for: Claude Brain Mode v1.2 — idle detection, vault relocate, pattern encounter tracking*
*Researched: 2026-03-21*
