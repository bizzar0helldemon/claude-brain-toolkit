# Domain Pitfalls — v1.2 Feature Research

**Domain:** Claude Code CLI Hook System — Adding idle detection, vault relocate, pattern encounter tracking
**Researched:** 2026-03-21
**Scope:** NEW pitfalls only. v1.0/v1.1 solved pitfalls (hook loop, exit code discipline, JSON ordering, intrusiveness detection) are documented in the v1.0 research archive and not repeated here.
**Confidence:** HIGH for hook-system pitfalls (verified against official docs + codebase inspection); MEDIUM for idle detection timing edge cases (WebSearch verified against official TeammateIdle documentation)

---

## Critical Pitfalls

### Pitfall 1: Idle Detection Fires on Long-Running Tool Calls, Not True Idleness

**What goes wrong:**
You implement idle detection using `TeammateIdle` (the official Claude Code hook event) or by comparing timestamps between hook firings. Claude appears "idle" while it is actually waiting for a long-running Bash command (a build, a test suite, an npm install) to return. The idle detection triggers a capture prompt or suggestion mid-task. The user is not idle at all — they're waiting for the tool to finish.

**Why it happens:**
`TeammateIdle` fires when an agent teammate finishes its turn in a team context. In a single-agent session (the common brain mode case), there is no native "user is not typing" event in Claude Code hooks. The workaround — comparing the timestamp of the last `PostToolUse` event to the current time — cannot distinguish between "user stopped working" and "user is watching a 3-minute test suite run." Both look like a gap with no tool calls.

**How to avoid:**
- Do not use timestamp gap between tool calls as a proxy for user idleness. It is not reliable.
- If implementing idle detection, use the `.brain-state` file's timestamp (written by `write_brain_state`) to detect time-since-last-hook-activity, not time-since-last-tool-call. Hooks only fire around tool use, so a gap there just means no tools are being called — not that the user is idle.
- Gate any idle-triggered behavior on exit from a completed session, not on a time gap within a session. The v1.2 LIFE-06 requirement says "offers to summarize when user pauses" — this is safer to implement at Stop time with a "session was long but nothing was captured" signal than as a mid-session timer.
- If a timer approach is unavoidable, require a minimum gap of 5+ minutes AND check that no async operations are visible in the transcript before firing.

**Warning signs:**
- Idle prompt appears while Claude is still running a long command
- Idle detection triggers during a build, test run, or npm install
- Users report that "brain interrupts me while I'm waiting for something to finish"

**Phase to address:** The phase implementing LIFE-06 (idle detection). Do not attempt polling-based idle detection — design around the Stop hook's "session ended with no capture" signal instead.

---

### Pitfall 2: Vault Relocate Updates BRAIN_PATH in Shell Profile but Not in settings.json — Hooks Still Use Old Path

**What goes wrong:**
User runs a vault relocate command. The command correctly updates `export BRAIN_PATH=...` in `~/.zshrc` (or `~/.bashrc`). The user opens a new terminal and BRAIN_PATH is correct. But Claude Code hooks read BRAIN_PATH from the `env` block in `~/.claude/settings.json`, not from the shell profile — because hooks run in non-interactive subshells that do not source `~/.zshrc`. The hooks continue writing to the old vault location until the user manually edits `settings.json`.

**Why it happens:**
Claude Code injects environment variables into hook subprocesses from its own `env` config block, not from the user's shell profile. This is documented in the official hooks reference. The vault relocate feature has two distinct targets to update (shell profile + settings.json), and the natural implementation path (update shell profile, done) misses the second target completely. The bug is invisible at first because new terminal sessions appear correct — it only surfaces when hooks run and write to the old path.

**How to avoid:**
Any vault relocate implementation MUST update both locations atomically:
1. Patch `export BRAIN_PATH=...` in the shell profile
2. Patch the `env.BRAIN_PATH` field in `~/.claude/settings.json` using `jq` with atomic tmp+mv write
3. Verify both are consistent before confirming success to the user

The relocate command should validate that `settings.json` was successfully updated and report both the shell profile path and the settings.json path it wrote to. Never rely on a single update.

Additionally: any running Claude Code session will not pick up the new path until the session is restarted — the `env` block is read at session launch, not dynamically. The relocate command must warn: "Restart any open Claude Code sessions for the new vault path to take effect."

**Warning signs:**
- After vault relocate, new files appear in the old BRAIN_PATH location
- Brain captures succeed (no errors) but vault at new location is empty
- `echo $BRAIN_PATH` in a new terminal shows the new path but hook output still references old path
- `grep BRAIN_PATH ~/.claude/settings.json` shows the old value

**Phase to address:** The phase implementing ONBR-03. Test by: (1) run relocate, (2) check settings.json BRAIN_PATH value, (3) open new Claude Code session, (4) trigger a hook, (5) verify write lands in new location.

---

### Pitfall 3: Pattern Store Grows Unbounded — Old Patterns Never Expire or Rotate

**What goes wrong:**
Users add patterns over months of use. The `pattern-store.json` grows without limit. After several hundred patterns, the jq query in `post-tool-use-failure.sh` scans the entire array on every tool failure. Hook execution time climbs. More concretely: the full `additionalContext` payload injected into Claude's context on every match includes the solution text of matching patterns — if the solution text is verbose and multiple patterns match, the context injection is proportionally large.

A secondary failure mode: patterns added early in usage stop being relevant (the tool, library version, or workflow changed) but remain in the store forever. Old patterns with high `encounter_count` match more noise than useful signal.

**Why it happens:**
`update_encounter_count` increments counters but never prunes. `brain-add-pattern.md` has no size limit or TTL concept. This is intentional for v1.0/v1.1 (pattern store is small, premature optimization avoided) but becomes a real problem at scale.

**How to avoid:**
- Implement a soft cap on pattern array length (recommended: 100 patterns). When adding a new pattern would exceed the cap, prune by evicting the pattern with the lowest `encounter_count` that hasn't been seen in the longest time (composite score: `encounter_count * recency_weight`).
- Add a `last_seen` threshold: patterns not seen in 90 days are candidates for auto-archival, not deletion.
- Keep solution text brief (1-3 sentences enforced by the add-pattern command). Long solutions should be stored in a separate vault note and referenced by path, not inlined.
- The pattern matching query already uses `head -1` (returns only the first match), which prevents multiple-match context explosion. Preserve this.

**Warning signs:**
- `wc -c "$BRAIN_PATH/brain-mode/pattern-store.json"` grows past 50KB
- PostToolUseFailure hook execution time visibly delays Claude's response to errors
- Patterns with `encounter_count: 0` from years ago appear in the store
- Users report false-positive pattern matches for unrelated errors

**Phase to address:** The phase implementing MENT-01 (pattern encounter tracking). Add pruning logic in the same phase — counter tracking without pruning is the technical debt that causes this.

---

### Pitfall 4: Pattern Encounter Counter Race Condition — Two Concurrent Sessions Update the Same Store Simultaneously

**What goes wrong:**
User runs two Claude Code sessions simultaneously (different project directories, both in brain mode). Both sessions hit errors matching the same pattern within milliseconds of each other. Both call `update_encounter_count`. Both read `pattern-store.json`, both compute the incremented value, both write to a `.tmp.$$` file, both `mv` the tmp file to `pattern-store.json`. One write overwrites the other. The counter is incremented only once instead of twice, and whichever session won the `mv` race determines the final store state — potentially overwriting pattern updates from the other session.

**Why it happens:**
`update_encounter_count` uses atomic tmp+mv, which is correct for single-writer scenarios. With two concurrent writers, both tmp files are created with different PID suffixes (`$$`) so they don't collide, but both `mv` to the same final target. The last `mv` wins. This is the standard read-modify-write race condition documented in the Claude Code `.claude.json` race condition issues (GitHub issues #28813, #28922, #29217).

**How to avoid:**
For the v1.2 scope (single-user, personal toolkit), the practical risk is low — simultaneous error-match on the same pattern across two sessions is rare. Do not over-engineer. The correct mitigation is proportional to the risk:

- Add a comment in `update_encounter_count` documenting the known limitation: "Not safe for concurrent writes from multiple simultaneous sessions — single-user use case makes this acceptable."
- If multi-session safety is required in a future phase: use `flock` to create an advisory lock file before the read-modify-write cycle: `flock -x "${store_path}.lock" jq ... > tmp && mv tmp store`
- Do NOT use `flock` speculatively in v1.2 — the added complexity is disproportionate to the risk.

**Warning signs:**
- `encounter_count` in the store is lower than expected after running multiple simultaneous sessions
- Pattern store `updated` timestamp occasionally jumps backward relative to expected activity
- Pattern data disappears after concurrent sessions (indicates full overwrite, not just counter loss)

**Phase to address:** Flag in implementation comments during MENT-01. Defer flock-based locking to a future phase unless concurrent session support is explicitly in scope.

---

### Pitfall 5: Vault Relocate Breaks Relative Symlinks Inside the Vault

**What goes wrong:**
The vault contains symlinks between notes (Obsidian-style cross-linking) or symlinked subdirectories. When vault relocate copies or moves the vault directory, relative symlinks that point outside the vault root become dangling references. The new BRAIN_PATH is valid, the directory exists, but hooks that read specific vault files (session logs, pattern store, skill files) silently fail because their target paths are broken symlinks.

**Why it happens:**
`brain_path_validate` checks that `BRAIN_PATH` is a directory — it does not check that key files within the vault are readable. A broken symlink passes `[ -d "$BRAIN_PATH" ]` because the parent directory exists. The hook then tries to read `$BRAIN_PATH/brain-mode/pattern-store.json` and gets a broken symlink, which `[ -f ]` returns false for — causing silent degradation.

**How to avoid:**
- Vault relocate should use `cp -r` (not `mv`) to the new location, then verify the copy before updating BRAIN_PATH, then optionally remove the old location.
- After copy: run a symlink integrity check: `find "$NEW_PATH" -type l ! -exec test -e {} \; -print` to surface broken symlinks before committing to the new location.
- The relocate command should warn users who have symlinks in their vault that relative symlinks may need to be updated.
- `brain_path_validate` should optionally check that `$BRAIN_PATH/brain-mode/` exists and is accessible (not a broken symlink), not just that `$BRAIN_PATH` itself is a directory.

**Warning signs:**
- After relocate, `[ -d "$BRAIN_PATH" ]` passes but `[ -f "$BRAIN_PATH/brain-mode/pattern-store.json" ]` fails
- Brain hooks silently degrade (fall through to `exit 0`) after a successful-looking relocate
- `ls -la "$BRAIN_PATH"` shows some entries with `->` pointing to non-existent paths

**Phase to address:** The phase implementing ONBR-03. Include a post-relocate verification step that reads the pattern store and at least one session log to confirm the vault is functional at the new path.

---

### Pitfall 6: Idle Detection Timestamp Comparison Is Platform-Dependent

**What goes wrong:**
The idle detection logic computes elapsed time by comparing the current epoch to the timestamp stored in `.brain-state`. On macOS, `date -u +%s` returns seconds since epoch correctly. On Linux with older glibc, the same command works. However: `stat` for file modification time uses different flags on macOS (`-f %m`) versus GNU/Linux (`-c %Y`). If the idle detection code uses `stat` to check when `.brain-state` was last modified (a tempting shortcut), it fails silently on the opposite platform.

**Why it happens:**
The existing codebase uses `date -u +"%Y-%m-%dT%H:%M:%SZ"` for timestamps (ISO-8601 string comparison, not epoch arithmetic) and writes state to `.brain-state` in `write_brain_state`. If idle detection needs to compute "how many minutes since last brain activity," comparing ISO-8601 strings requires parsing — and the temptation is to reach for `stat` to get the file's mtime instead. `stat` is not portable between macOS and Linux.

**How to avoid:**
- Store epoch seconds in `.brain-state` alongside the ISO string: `"$state $iso_timestamp $epoch_seconds"`. This makes elapsed-time arithmetic trivial without `stat`.
- If epoch is not available: use ISO-8601 comparison only for "is this today or not" checks. For precise elapsed minutes, extend the state file format rather than relying on filesystem metadata.
- Never use `stat` in hooks without a platform guard.
- The v1.1 `.brain-state` format is `"<state> <ISO-8601>"`. Any idle detection phase that needs elapsed time should extend this format rather than introduce `stat`.

**Warning signs:**
- Idle detection works on developer's machine (macOS) but fails silently in CI or on Linux
- `stat: illegal option` errors appear in hook stderr
- Time-based comparisons produce incorrect results (off by hours due to timezone in string comparison)

**Phase to address:** The phase implementing LIFE-06. Document the state file format extension in the phase plan before implementation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip pattern store pruning in MENT-01 | Simpler first implementation | Store grows unbounded after months of use; matching slows; context injection grows | Never — add cap in same phase as counter tracking |
| Update only shell profile in vault relocate | Simpler relocate command | Hooks write to old path until user manually fixes settings.json | Never — both update targets are required |
| Use stat for idle time arithmetic | Avoids extending .brain-state format | Platform-specific failure on macOS vs Linux | Never — extend state file format instead |
| Implement idle detection as a polling loop in a background process | Feels more "real" idle detection | Adds persistent background process; conflicts with Claude Code's synchronous hook model | Never — work within the hook lifecycle |
| Infer idleness from tool call timestamp gaps | Simple to implement | Cannot distinguish waiting-for-tool from idle user | Never — use session-end signals instead |
| Store full verbose solution text in pattern store | Richer context injection | Pattern store grows fast; large solutions injected on every match inflate context | Acceptable only for solutions under 200 chars; link to vault file otherwise |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Vault relocate + settings.json | Update only `~/.zshrc` or `~/.bashrc` | Update both shell profile AND `env.BRAIN_PATH` in `~/.claude/settings.json` atomically |
| Vault relocate + running sessions | Assume new path takes effect immediately | Warn user to restart any open Claude Code sessions; env block is read at session launch |
| Pattern store + concurrent sessions | Assume single-writer safety from tmp+mv | Document limitation; add `flock` advisory lock only if explicit multi-session support is in scope |
| Idle detection + TeammateIdle hook | Use TeammateIdle for single-agent sessions | TeammateIdle is a team/multi-agent event; single-agent sessions need session-end signals instead |
| Idle detection + long tool calls | Fire idle trigger on any gap in tool calls | Long-running Bash commands create gaps — require gap AND no pending tool calls before triggering |
| Pattern encounter tracking + solution text | Inline long solutions in pattern JSON | Keep solution text under 200 chars; store verbose solutions in vault files, reference by path |
| Vault relocate + symlinks | cp -r silently copies broken symlinks | Verify symlink integrity post-copy before committing to new location |
| .brain-state + elapsed time | Use stat to read file mtime | Embed epoch seconds in state file format; never use stat (platform-specific flags) |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Idle detection prompt fires mid-task | Interrupts user waiting for a long tool call; feels wrong | Fire idle-based capture suggestion only at Stop time, not mid-session |
| Vault relocate with no progress feedback | User unsure if copy succeeded; may close terminal early | Report each step: "Copying vault... done. Updating settings.json... done. Verifying new path... done." |
| Pattern store shows no encounter counts after MENT-01 ships | Users can't tell if the pattern tracking is working | Surface encounter count somewhere visible — in `/brain-capture` output or a `/brain-status` summary |
| Vault relocate doesn't restart hint | User relocates vault, triggers hook, hook writes to old path | Always append: "Restart Claude Code sessions for the new vault path to take effect" |
| Pattern store silent pruning removes a valued pattern | User notices their carefully-crafted pattern is gone | Archive pruned patterns to a separate JSON or append to a vault note — never hard-delete |

---

## "Looks Done But Isn't" Checklist

### Idle Detection (LIFE-06)
- [ ] Verify idle trigger does NOT fire while a long Bash command is still running (test with `sleep 300`)
- [ ] Verify idle detection works from session-end signals, not mid-session timestamp gaps
- [ ] Verify state file timestamp format includes sufficient information for elapsed-time comparison without using `stat`
- [ ] Test on both macOS and Linux (or document supported platforms explicitly)
- [ ] Verify idle detection respects the v1.1 lesson: silent by default, visible only at natural pause points

### Vault Relocate (ONBR-03)
- [ ] Verify `env.BRAIN_PATH` in `~/.claude/settings.json` is updated, not just shell profile
- [ ] Verify hooks write to new location after a fresh Claude Code session (not just `echo $BRAIN_PATH`)
- [ ] Verify broken symlinks in the vault are surfaced before the relocate is committed
- [ ] Verify the relocate command fails loudly (not silently) if `settings.json` write fails
- [ ] Test: relocate while a Claude Code session is open; confirm session still writes to old location (expected); confirm after session restart it writes to new location

### Pattern Encounter Tracking (MENT-01)
- [ ] Verify `encounter_count` increments when an error matches a pattern (not just when added)
- [ ] Verify pattern store does not grow past the soft cap — add a pattern that exceeds the cap and confirm oldest/least-seen is evicted
- [ ] Verify that the pruning logic uses `last_seen`, not `first_seen`, when deciding what to evict
- [ ] Verify the `additionalContext` injected on match is not bloated by verbose solutions (inspect payload size)
- [ ] Verify concurrent session write produces no data corruption — simulate by running two hooks simultaneously against the same store

---

## Pitfall-to-Phase Mapping

| Pitfall | Feature | Prevention Phase | Verification Approach |
|---------|---------|------------------|----------------------|
| Idle fires during long tool calls | LIFE-06: Idle detection | Idle detection phase | Test with 5-minute sleep command; confirm no idle trigger fires |
| Vault relocate misses settings.json | ONBR-03: Vault relocate | Vault relocate phase | grep settings.json BRAIN_PATH after relocate |
| Pattern store unbounded growth | MENT-01: Pattern tracking | Same phase as counter | Fill store to 101 patterns; confirm eviction |
| Encounter counter race condition | MENT-01: Pattern tracking | Same phase; document limitation | Concurrent session test or written disclaimer in code |
| Relocate breaks symlinks | ONBR-03: Vault relocate | Vault relocate phase | Create symlink in test vault, relocate, verify integrity |
| Idle time platform-dependency (stat) | LIFE-06: Idle detection | Idle detection phase | Review all timestamp code for stat usage; extend state file format |

---

## Sources

- [Claude Code Hooks Reference — official docs](https://code.claude.com/docs/en/hooks) — HIGH confidence, authoritative; confirms TeammateIdle is team/multi-agent, not single-agent; confirms non-interactive subshell env injection from settings.json
- [Race condition: .claude.json corrupted by concurrent writes — GitHub Issue #29217](https://github.com/anthropics/claude-code/issues/29217) — HIGH confidence, official issue tracker; confirms real-world concurrent write corruption
- [.claude.json race condition (multiple issues) — GitHub Issue #28813](https://github.com/anthropics/claude-code/issues/28813) — HIGH confidence; confirms tmp+mv is correct but insufficient for multiple concurrent writers
- [Things UNIX can do atomically — rcrowley.org](https://rcrowley.org/2010/01/06/things-unix-can-do-atomically.html) — HIGH confidence; confirms rename() is atomic on POSIX, foundation for tmp+mv pattern
- [Using Lock Files for Job Control in Bash Scripts — putorius.net](https://www.putorius.net/lock-files-bash-scripts.html) — MEDIUM confidence; documents flock advisory lock approach for concurrent write safety
- [Windowed Deduplicator: Eliminate Duplicates Without Running Out of Memory — Medium, 2026](https://medium.com/@francotesei/windowed-deduplicator-eliminate-duplicates-without-running-out-of-memory-534770417362) — MEDIUM confidence; confirms TTL/windowed approach as standard for unbounded-growth prevention
- [5 Claude Code Hook Mistakes That Silently Break Your Safety Net — DEV Community](https://dev.to/yurukusa/5-claude-code-hook-mistakes-that-silently-break-your-safety-net-58l3) — MEDIUM confidence; verified exit code discipline and JSON/exit-code mutual exclusivity
- [correct or inotify: pick one — wingolog.org](https://wingolog.org/archives/2018/05/21/correct-or-inotify-pick-one) — MEDIUM confidence; documents race conditions in file event-based idle detection approaches
- Codebase inspection of `hooks/lib/brain-path.sh`, `hooks/stop.sh`, `hooks/post-tool-use-failure.sh`, `commands/brain-add-pattern.md` — HIGH confidence; direct analysis of existing implementation patterns and gaps

---
*Pitfalls research for: Claude Brain Mode v1.2 — idle detection, vault relocate, pattern encounter tracking*
*Researched: 2026-03-21*
