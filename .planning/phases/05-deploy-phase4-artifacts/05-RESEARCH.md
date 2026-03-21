# Phase 5: Deploy Phase 4 Artifacts - Research

**Researched:** 2026-03-21
**Domain:** Shell installer (setup.sh) extension — deploying hooks and slash commands post-phase
**Confidence:** HIGH

---

## Summary

Phase 5 has a single, tightly-scoped job: update `onboarding-kit/setup.sh` so that after running it, the two Phase 4 artifacts (`hooks/post-tool-use.sh` and `commands/brain-add-pattern.md`) are live on the user's machine and wired into Claude Code's configuration. All code is already written and verified. This phase contains zero implementation work — only installer surgery.

The root cause of the gap is timing: `setup.sh` was authored in Phase 3, before Phase 4 added `post-tool-use.sh` and `commands/brain-add-pattern.md`. The Phase 4 verification confirmed the code works correctly; the v1.0 milestone audit identified that neither artifact is deployed. Three discrete gaps exist in `setup.sh`: (1) `post-tool-use.sh` is absent from the `cp` deploy list, (2) the `PostToolUse` hook type is absent from the `BRAIN_HOOKS` merge string, and (3) the `commands/brain-add-pattern.md` file has no deploy path at all.

There is a fourth gap that the milestone audit flagged: the installed `~/.claude/hooks/post-tool-use-failure.sh` and `~/.claude/hooks/lib/brain-path.sh` are Phase 1 versions — they do not contain the Phase 4 pattern-matching code and utility functions. `setup.sh` already deploys both files, but the installed copies are stale because no one has re-run `setup.sh` since Phase 4 completed. Re-running the updated `setup.sh` will automatically overwrite them with the Phase 4 versions. No special handling is required; the existing cp commands cover this.

Additionally, the installed `~/.claude/settings.json` has `"async": true` on `PostToolUseFailure`, which Phase 4's plan 04-01 explicitly removed from the repo's `settings.json`. The BRAIN_HOOKS merge in `setup.sh` must omit `async: true` from PostToolUseFailure (Phase 4 requirement) and add PostToolUse as a synchronous entry.

**Primary recommendation:** Add four lines to `setup.sh` — one `cp` for `post-tool-use.sh`, one `cp` for `brain-add-pattern.md` (with `mkdir -p` for the new `commands/brain/` directory), update the BRAIN_HOOKS merge string to add PostToolUse and remove `async:true` from PostToolUseFailure, and add both new files to the verification checklist at the end of setup.sh.

---

## Standard Stack

### Core

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| bash `cp` + `chmod +x` | System bash | Deploy shell scripts to `~/.claude/hooks/` | Already the established pattern in setup.sh for all hook files |
| bash `cp` | System bash | Deploy markdown skill file to `~/.claude/commands/brain/` | Standard Claude Code pattern — `.md` files in `~/.claude/commands/<namespace>/` become `/namespace:command` slash commands |
| jq heredoc merge | jq 1.6+ | Add PostToolUse to `~/.claude/settings.json` hooks block idempotently | Already the established pattern in setup.sh Phase 6 |
| `mkdir -p` | System bash | Ensure `~/.claude/commands/brain/` exists before copying | Standard guard before cp; `commands/brain/` is a new directory not created by prior setup.sh phases |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `check_file` helper | setup.sh internal | Add verification checks for new artifacts in Phase 8 | Already exists in setup.sh; call with new file paths to extend the verification pass |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Direct `cp` for brain-add-pattern.md | Glob loop over all `commands/` files | Glob loop is safer for future additions but requires knowing that `commands/` is a flat namespace with subdirectories. Direct `cp` is explicit and matches the Phase 4 artifact set exactly. Use direct cp for this phase; Phase 6 can refactor if more commands are added. |
| Update BRAIN_HOOKS heredoc | Run a separate `jq` mutation command to add PostToolUse | Heredoc is the established pattern. Adding to the heredoc is simpler and keeps the merge logic in one place. |

**Installation:**

No new dependencies. `jq`, `bash`, and `cp` are already prerequisites verified by setup.sh Phase 1.

---

## Architecture Patterns

### Where setup.sh installs things

Understanding the target layout is critical for this phase:

```
~/.claude/
├── hooks/
│   ├── lib/
│   │   ├── brain-path.sh       # deployed by setup.sh Phase 4 — cp from hooks/lib/
│   │   └── brain-context.sh    # deployed by setup.sh Phase 4 — cp from hooks/lib/
│   ├── session-start.sh        # deployed by setup.sh Phase 4
│   ├── stop.sh                 # deployed by setup.sh Phase 4
│   ├── pre-compact.sh          # deployed by setup.sh Phase 4
│   ├── post-tool-use-failure.sh # deployed by setup.sh Phase 4 — STALE (Phase 1 version installed)
│   └── post-tool-use.sh        # MISSING — must add to setup.sh Phase 4 deploy block
├── commands/
│   ├── brain/                  # directory does NOT exist yet — must mkdir -p
│   │   └── brain-add-pattern.md # MISSING — must add new deploy step
│   └── gsd/                    # example: gsd commands are in a subdirectory
├── settings.json               # merged by setup.sh Phase 6 — PostToolUse MISSING, PostToolUseFailure has async:true
└── agents/
    └── brain-mode.md           # deployed by setup.sh Phase 2
```

### Pattern 1: Adding a New Hook File to setup.sh

**What:** Add a single `cp` line in the existing "Deploy hook scripts" block (currently labeled `[4/9]`) and a corresponding `chmod +x` guard.

**When to use:** Any new `.sh` file in the repo's `hooks/` directory that must be installed.

**Example (from existing setup.sh pattern):**

```bash
# In the [4/9] Deploy hook scripts block:
cp "$REPO_DIR/hooks/post-tool-use.sh" "$CLAUDE_DIR/hooks/post-tool-use.sh"
# ...after existing cp lines
chmod +x "$CLAUDE_DIR/hooks/"*.sh   # already present — glob covers new file automatically
echo "  + post-tool-use.sh deployed"
```

Note: The existing `chmod +x "$CLAUDE_DIR/hooks/"*.sh` line uses a glob — it will automatically make `post-tool-use.sh` executable once it exists. No change to the chmod line is needed.

### Pattern 2: Deploying a slash command (.md) file

**What:** Slash commands in Claude Code live at `~/.claude/commands/<namespace>/<name>.md`. They are invoked as `/<namespace>:<name>` or (if in a flat directory) `/<name>`. The repo uses the `brain` namespace (confirmed by checking `~/.claude/commands/brain/` which contains `scan.md` etc. from adjacent GSD tooling).

**When to use:** Any `.md` file in the repo's `commands/` directory that becomes a Claude Code slash command.

**Example:**

```bash
# New deploy block — insert after existing "Deploy hook scripts" section
echo "[4b/9] Deploying slash commands..."
mkdir -p "$CLAUDE_DIR/commands/brain"
cp "$REPO_DIR/commands/brain-add-pattern.md" "$CLAUDE_DIR/commands/brain/brain-add-pattern.md"
echo "  + brain-add-pattern.md deployed to $CLAUDE_DIR/commands/brain/"
```

The destination filename must match for the slash command invocation. Users call `/brain:brain-add-pattern` or `/brain-add-pattern` depending on Claude Code version. The file goes in the `brain` subdirectory because that is the namespace already used by the toolkit (`~/.claude/commands/brain/`).

### Pattern 3: Updating the BRAIN_HOOKS merge string

**What:** The `BRAIN_HOOKS` heredoc in setup.sh Phase 6 is the source of truth for what hooks get merged into `~/.claude/settings.json`. It must be updated to: (1) add PostToolUse, (2) remove `async: true` from PostToolUseFailure.

**Current BRAIN_HOOKS (stale):**

```json
{
  "SessionStart": [{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start.sh","timeout":10}]}],
  "PreCompact": [{"hooks":[{"type":"command","command":"~/.claude/hooks/pre-compact.sh","timeout":10}]}],
  "Stop": [{"hooks":[{"type":"command","command":"~/.claude/hooks/stop.sh","timeout":10}]}],
  "PostToolUseFailure": [{"hooks":[{"type":"command","command":"~/.claude/hooks/post-tool-use-failure.sh","timeout":10,"async":true}]}]
}
```

**Updated BRAIN_HOOKS (correct for Phase 4):**

```json
{
  "SessionStart": [{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start.sh","timeout":10}]}],
  "PreCompact": [{"hooks":[{"type":"command","command":"~/.claude/hooks/pre-compact.sh","timeout":10}]}],
  "Stop": [{"hooks":[{"type":"command","command":"~/.claude/hooks/stop.sh","timeout":10}]}],
  "PostToolUseFailure": [{"hooks":[{"type":"command","command":"~/.claude/hooks/post-tool-use-failure.sh","timeout":10}]}],
  "PostToolUse": [{"hooks":[{"type":"command","command":"~/.claude/hooks/post-tool-use.sh","timeout":10}]}]
}
```

Key changes:
- `async:true` removed from PostToolUseFailure entry (Phase 4 plan 04-01 requirement)
- PostToolUse entry added (synchronous, no matcher — filtering done in script)

The jq idempotency check uses `index(command)` to detect if the hook is already registered. The same check works for PostToolUse since it uses a unique command path `post-tool-use.sh`.

**Critical:** The installed `~/.claude/settings.json` currently has `"async": true` on PostToolUseFailure (confirmed by inspection). The jq merge in setup.sh must handle this existing entry correctly. The current merge logic only adds entries — it does not update existing ones. This means re-running setup.sh will NOT remove `async: true` from an already-registered PostToolUseFailure entry.

This is a known limitation: the merge is append-only. To fix the stale async entry in the installed settings.json, the merge logic must be changed OR a separate jq mutation must run to remove `async: true` from the existing PostToolUseFailure entry. See the "Pitfalls" section.

### Pattern 4: Extending the Verification Checklist

**What:** setup.sh Phase 8 has a `check_file` loop. Add the two new artifacts.

```bash
check_file "$CLAUDE_DIR/hooks/post-tool-use.sh"               "hooks/post-tool-use.sh"
check_file "$CLAUDE_DIR/commands/brain/brain-add-pattern.md"  "commands/brain/brain-add-pattern.md"
```

Also add a PostToolUse hook registration check alongside the existing SessionStart check:

```bash
if jq '.hooks.PostToolUse' "$SETTINGS" 2>/dev/null | grep -q "post-tool-use.sh"; then
  echo "  + settings.json contains brain PostToolUse hook"
else
  echo "  x settings.json missing brain PostToolUse hook"
  PASS=false
fi
```

### Anti-Patterns to Avoid

- **Deploying brain-add-pattern.md to `~/.claude/commands/brain-add-pattern.md` (flat):** Commands in flat `commands/` without a subdirectory are accessible as `/brain-add-pattern`. Commands in `commands/brain/` are accessible as `/brain:brain-add-pattern`. The existing `~/.claude/commands/brain/` directory structure (from GSD tooling inspection) confirms subdirectory namespacing is the convention. Use `commands/brain/`.
- **Adding `async: true` to PostToolUse:** The PostToolUse hook uses `decision:block` which requires synchronous execution. Never add `async: true` to this hook.
- **Forgetting `mkdir -p "$CLAUDE_DIR/commands/brain"`:** If this directory doesn't exist when `cp` runs, cp will fail. The `mkdir -p` must precede the `cp`. This directory is NOT created by any prior setup.sh phase.
- **Assuming chmod +x covers .md files:** The `chmod +x "$CLAUDE_DIR/hooks/"*.sh` glob covers hook scripts. The `commands/brain-add-pattern.md` file is a markdown file, not a shell script — it does not need to be executable. Do not add it to any chmod glob.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idempotent settings.json merge | Custom JSON merge logic | The existing jq merge pattern in setup.sh — extend the BRAIN_HOOKS heredoc | The existing pattern handles idempotency correctly via `index(command)` check. Extending it is lower risk than adding parallel merge logic. |
| Slash command naming | Research naming convention | Use `~/.claude/commands/brain/` subdirectory | Confirmed by inspection of installed `~/.claude/commands/` — brain namespace already exists |
| async:true removal from existing settings | Custom migration script | Add a targeted `jq` del statement before the BRAIN_HOOKS merge | Simpler and auditable; runs idempotently |

**Key insight:** This phase is pure installer delta. Every piece of code is already written. The only work is editing setup.sh in four specific places.

---

## Common Pitfalls

### Pitfall 1: The BRAIN_HOOKS merge does not update existing hook entries

**What goes wrong:** The installed `~/.claude/settings.json` already has PostToolUseFailure registered with `"async": true`. The current setup.sh merge only adds missing entries — it does not patch existing ones. Re-running setup.sh will skip adding PostToolUseFailure again (it's already there), so `async: true` remains. The Phase 4 code expects PostToolUseFailure to be synchronous.

**Why it happens:** The jq merge uses `index(command) != null` as the idempotency guard — if the command is already registered, nothing changes, including stale fields like `async: true`.

**How to avoid:** Add a targeted jq mutation step before the BRAIN_HOOKS merge that removes `async` from any existing PostToolUseFailure entry:

```bash
# Remove async:true from PostToolUseFailure if present (Phase 4 requires synchronous)
TEMP="$SETTINGS.tmp"
jq '
  if .hooks.PostToolUseFailure then
    .hooks.PostToolUseFailure = [
      .hooks.PostToolUseFailure[] |
      .hooks = [.hooks[] | del(.async)]
    ]
  else . end
' "$SETTINGS" > "$TEMP" && mv "$TEMP" "$SETTINGS"
```

This runs idempotently — if `async` is already absent, `del(.async)` is a no-op.

**Warning signs:** After running setup.sh, `jq '.hooks.PostToolUseFailure[0].hooks[0].async' ~/.claude/settings.json` returns `true` instead of `null`.

---

### Pitfall 2: commands/brain/ directory not created before cp

**What goes wrong:** `cp "$REPO_DIR/commands/brain-add-pattern.md" "$CLAUDE_DIR/commands/brain/brain-add-pattern.md"` fails with "No such file or directory" if `~/.claude/commands/brain/` does not exist.

**Why it happens:** `~/.claude/commands/brain/` is a new directory. Prior setup.sh phases only create `hooks/lib/` and `agents/`. The commands directory is not created anywhere in the existing setup.sh.

**How to avoid:** Always precede the `cp` with `mkdir -p "$CLAUDE_DIR/commands/brain"`.

**Warning signs:** setup.sh exits with a non-zero code during the commands deploy step.

---

### Pitfall 3: Installed post-tool-use-failure.sh is Phase 1 version

**What goes wrong:** The Phase 5 changes update setup.sh to deploy `post-tool-use.sh` and wire PostToolUse in settings.json — but the installed `post-tool-use-failure.sh` is still the Phase 1 version (no pattern matching, no `COMMAND` extraction, has `exit 1` on validation failure). The pattern matching flow (Flow 4) will fail silently.

**Why it happens:** `post-tool-use-failure.sh` was deployed by a previous setup.sh run that predates Phase 4.

**How to avoid:** This is automatically fixed when setup.sh redeploys `post-tool-use-failure.sh` and `brain-path.sh` — the existing cp lines in setup.sh Phase 4 already copy these files. Re-running the updated setup.sh will overwrite the stale installed versions with Phase 4 versions. No special handling needed; the fix comes for free.

**Warning signs:** After running updated setup.sh, `grep "pattern-store" ~/.claude/hooks/post-tool-use-failure.sh` returns nothing — meaning the stale file was not overwritten.

---

### Pitfall 4: set -e causes silent failures when files are missing

**What goes wrong:** setup.sh uses `set -e`. If any `cp` command fails (e.g., source file missing from repo), the entire script exits without running later phases and without a clear error message to the user.

**Why it happens:** `set -e` is correct for an installer — you want it to stop on error. But silent exits without context messages are confusing.

**How to avoid:** The existing setup.sh structure already handles this implicitly (all source files must exist in the repo). For the new `cp` commands, verify source file paths are correct relative to `$REPO_DIR`:
- `$REPO_DIR/hooks/post-tool-use.sh` — confirmed exists at `hooks/post-tool-use.sh`
- `$REPO_DIR/commands/brain-add-pattern.md` — confirmed exists at `commands/brain-add-pattern.md`

**Warning signs:** setup.sh exits immediately after the new cp line with no output.

---

### Pitfall 5: PostToolUse hook timeout too short for decision:block latency

**What goes wrong:** The PostToolUse hook uses `decision:block` which makes Claude pause and act. If the hook's `timeout` in settings.json is too short, Claude Code may time out the hook before the response is used.

**Why it happens:** The research repo's settings.json already sets `timeout: 10` for PostToolUse (10 seconds). The hook script itself is fast (pure bash + jq). The decision:block response is returned synchronously. 10 seconds is sufficient.

**How to avoid:** Use `"timeout": 10` in the BRAIN_HOOKS entry for PostToolUse — consistent with all other hooks. Do not change it.

---

## Code Examples

### Full BRAIN_HOOKS heredoc (updated)

```bash
# Source: onboarding-kit/setup.sh — BRAIN_HOOKS heredoc, updated for Phase 4
BRAIN_HOOKS=$(cat <<'HOOKS_EOF'
{
  "SessionStart": [{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start.sh","timeout":10}]}],
  "PreCompact": [{"hooks":[{"type":"command","command":"~/.claude/hooks/pre-compact.sh","timeout":10}]}],
  "Stop": [{"hooks":[{"type":"command","command":"~/.claude/hooks/stop.sh","timeout":10}]}],
  "PostToolUseFailure": [{"hooks":[{"type":"command","command":"~/.claude/hooks/post-tool-use-failure.sh","timeout":10}]}],
  "PostToolUse": [{"hooks":[{"type":"command","command":"~/.claude/hooks/post-tool-use.sh","timeout":10}]}]
}
HOOKS_EOF
)
```

### async:true removal jq snippet

```bash
# Source: project convention — same atomic write pattern used throughout setup.sh
# Remove async:true from any existing PostToolUseFailure entries (Phase 4 requires synchronous)
jq '
  if .hooks.PostToolUseFailure then
    .hooks.PostToolUseFailure = [
      .hooks.PostToolUseFailure[] |
      .hooks = [.hooks[] | del(.async)]
    ]
  else . end
' "$SETTINGS" > "$TEMP" && mv "$TEMP" "$SETTINGS"
```

### New commands deploy block

```bash
# Deploy slash commands — add after existing hook deploy block
echo "[4b/9] Deploying slash commands..."
mkdir -p "$CLAUDE_DIR/commands/brain"
cp "$REPO_DIR/commands/brain-add-pattern.md" "$CLAUDE_DIR/commands/brain/brain-add-pattern.md"
echo "  + brain-add-pattern.md deployed to $CLAUDE_DIR/commands/brain/"
echo ""
```

### Updated verification checks

```bash
# Add to setup.sh Phase 8 check_file calls:
check_file "$CLAUDE_DIR/hooks/post-tool-use.sh"              "hooks/post-tool-use.sh"
check_file "$CLAUDE_DIR/commands/brain/brain-add-pattern.md" "commands/brain/brain-add-pattern.md"

# Add to settings.json registration checks:
if jq '.hooks.PostToolUse' "$SETTINGS" 2>/dev/null | grep -q "post-tool-use.sh"; then
  echo "  + settings.json contains brain PostToolUse hook"
else
  echo "  x settings.json missing brain PostToolUse hook"
  PASS=false
fi
```

---

## State of the Art

| Old Approach | Current Approach | Notes | Impact |
|--------------|------------------|-------|--------|
| PostToolUseFailure with `async: true` | PostToolUseFailure synchronous (no async field) | Changed in Phase 4 plan 04-01 — required for additionalContext to work reliably | setup.sh must not re-introduce async:true |
| Only 4 hook types in setup.sh BRAIN_HOOKS | 5 hook types (add PostToolUse) | Phase 4 added PostToolUse for commit detection | Installer gap |
| No commands/ deployment in setup.sh | commands/brain/ directory + brain-add-pattern.md | Phase 4 introduced the commands/ directory convention | New deploy path required |

---

## Open Questions

1. **Slash command namespace: `/brain-add-pattern` vs `/brain:brain-add-pattern`**
   - What we know: Files in `~/.claude/commands/brain/` are namespaced as `brain`. Based on Claude Code documentation conventions, a file at `commands/brain/brain-add-pattern.md` is invoked as `/brain:brain-add-pattern`.
   - What's unclear: Whether the command is also accessible as just `/brain-add-pattern` (flat alias). The `commands/brain-add-pattern.md` skill references itself as `/brain-add-pattern` in its confirmation message.
   - Recommendation: Deploy to `commands/brain/brain-add-pattern.md`. The agent context (brain-mode.md) lists it as `/brain-add-pattern` — Claude will call it that way regardless. If the namespace prefix is required, it becomes a usability issue for the user invoking it manually, but that is out of scope for this phase. Document the deployment path; do not alter the skill file.

2. **Section renumbering in setup.sh**
   - What we know: setup.sh currently has sections labeled [1/9] through [9/9]. Adding a new `[4b/9]` section for commands deploy keeps the numbering legible without requiring a full renumber.
   - What's unclear: Whether to renumber to [1/10] through [10/10] for cleanliness.
   - Recommendation: Use `[4b/9]` label for the new commands section. It reads clearly and avoids touching every echo statement. Do not renumber.

---

## Sources

### Primary (HIGH confidence)

- `onboarding-kit/setup.sh` (repo codebase) — existing deploy pattern, BRAIN_HOOKS heredoc, jq merge logic, verification checklist
- `.planning/v1.0-MILESTONE-AUDIT.md` (repo codebase) — exact list of gaps, root cause analysis, confirmed file paths for missing artifacts
- `.planning/phases/04-intelligence-layer/04-VERIFICATION.md` (repo codebase) — confirmed all Phase 4 artifacts exist and are correct; identifies the exact 3 setup.sh gaps
- `hooks/post-tool-use.sh`, `hooks/post-tool-use-failure.sh`, `hooks/lib/brain-path.sh`, `commands/brain-add-pattern.md` (repo codebase) — Phase 4 source files confirmed present
- `~/.claude/settings.json` (live system) — confirmed PostToolUse absent, PostToolUseFailure has `async: true`, current installed state
- `~/.claude/hooks/post-tool-use-failure.sh` (live system) — confirmed Phase 1 version installed (no pattern-store.json references)
- `~/.claude/commands/` (live system) — confirmed `brain/` subdirectory is the correct namespace for brain toolkit commands

### Secondary (MEDIUM confidence)

- Claude Code slash command conventions (inferred from `~/.claude/commands/brain/` and `~/.claude/commands/gsd/` directory structure) — subdirectory = namespace prefix

### Tertiary (LOW confidence — flagged for validation)

- Slash command invocation syntax (`/brain:brain-add-pattern` vs `/brain-add-pattern`) — exact invocation syntax for subdirectory-namespaced commands was not verified against official docs. Confirm with a live test or official Claude Code documentation during execution.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools (bash, cp, jq, mkdir) are verified in the existing installer; patterns are confirmed by reading the live codebase
- Architecture: HIGH — deploy paths confirmed by inspecting `~/.claude/` live; source file paths confirmed by inspecting the repo
- Pitfalls: HIGH — async:true issue confirmed by inspecting live settings.json; BRAIN_HOOKS gaps confirmed by milestone audit and live settings inspection

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (30 days — setup.sh is a stable shell script; risks are codebase-internal, not ecosystem-driven)
