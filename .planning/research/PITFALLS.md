# Pitfalls Research

**Domain:** Claude Code CLI Extension — AI Knowledge Management / Brain Mode
**Researched:** 2026-03-19
**Confidence:** HIGH (critical pitfalls verified against official Claude Code docs and multiple sources)

---

## Critical Pitfalls

### Pitfall 1: Stop Hook Infinite Loop

**What goes wrong:**
A Stop hook blocks Claude with `exit 2` (or `{"continue": true}`). Claude is prevented from stopping, so it tries to stop again. The hook fires again, blocks again. The session loops indefinitely, consuming tokens and hanging the terminal.

**Why it happens:**
Stop hooks are the most powerful lifecycle hook and the easiest to get wrong. The temptation is to always block on stop to force some capture behavior (e.g., "always save before quitting"), but without a guard condition the hook fires on every stop attempt including the ones it already triggered.

**How to avoid:**
Check `stop_hook_active` in every Stop hook before doing anything. If it is `true`, exit 0 immediately — Claude already tried to stop and was blocked, your capture logic already ran. Additionally: never return `{"continue": true}` from a Stop hook — that field signals Claude to continue, which re-triggers the Stop event.

```bash
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0  # Guard: already ran, let it stop
fi
# ... rest of capture logic
```

**Warning signs:**
- Session hangs after you close the terminal or type /exit
- Token counter climbs without any user input after a stop attempt
- Claude responds to "stopping" by generating more work unprompted

**Phase to address:** Phase 1 (Hook Infrastructure) — test Stop hook with explicit loop-prevention from day one.

---

### Pitfall 2: Context Window Bloat from Vault Loading

**What goes wrong:**
Brain mode loads too much vault content into context on SessionStart. A single 40KB skill file is manageable; five copies of it across a multi-directory workspace (or loading an entire vault index) consumes 100K+ tokens before the first prompt. LLM performance degrades measurably above ~147K tokens. Sessions compact early and lose brain state.

**Why it happens:**
The natural design is "load everything relevant at startup so brain mode is fully informed." This works for a single repo but a knowledge vault has no natural scope boundary. Without measurement, it is impossible to know whether a "helpful" SessionStart hook is quietly cutting effective session length in half.

**How to avoid:**
Load only a navigation skeleton (index files, current project context) at startup — never full note contents. Use PreCompact hooks to capture working state before compaction. Load specific vault content on-demand via tool calls, not upfront. Set a hard token budget for brain mode startup: keep SessionStart hook output under 2,000 tokens. Measure actual overhead with `/cost` or verbose output before shipping.

**Warning signs:**
- Auto-compaction fires within the first 10 minutes of a session
- `claude --verbose` shows SessionStart hook outputting more than a few hundred lines
- Sessions feel "shorter" than sessions without brain mode
- Context fills faster when using multi-repo workspaces

**Phase to address:** Phase 2 (Session Lifecycle) — establish and test startup token budget before adding any vault loading features.

---

### Pitfall 3: Wrong Exit Code Silences the Security Gate

**What goes wrong:**
A PreToolUse hook intended to block destructive vault operations uses `exit 1` instead of `exit 2`. Claude Code treats exit 1 as a non-blocking error — it logs the error and continues executing the tool anyway. The "safety gate" is effectively decorative.

**Why it happens:**
`exit 1` is the Unix convention for "something went wrong." Developers reach for it instinctively. Claude Code's exit code contract is non-standard: only `exit 2` blocks. Exit 0 passes. Any other code is non-blocking.

**How to avoid:**
Internalize the three-state contract for every hook that must block:
- `exit 0` = pass (or `exit 0` + JSON for structured output)
- `exit 2` = block (stderr message goes to user/Claude)
- Any other code = non-blocking error, execution continues

Never mix exit 2 with JSON output — Claude Code ignores JSON when exit code is 2. Use stderr for the user-facing block message.

**Warning signs:**
- Hook "runs" (you can see its output in verbose mode) but the operation it was meant to stop still happens
- Testing a hook with a known-bad input shows a warning message but the tool executes anyway

**Phase to address:** Phase 1 (Hook Infrastructure) — enforce exit code discipline in the hook scaffolding template used for all subsequent hooks.

---

### Pitfall 4: Shell Profile Output Corrupts JSON Parsing

**What goes wrong:**
A hook that outputs JSON for structured communication with Claude Code produces output like:

```
Welcome to bash! Today is Thursday.
{"decision": "block", "reason": "..."}
```

Claude Code cannot parse this — it expects clean JSON. The hook silently fails (or passes through when it should block).

**Why it happens:**
When Claude Code runs a hook, it spawns a shell that sources `~/.zshrc` or `~/.bashrc`. If those profiles contain unconditional `echo` statements (welcome messages, `nvm` version notices, `conda` activation output, etc.) that output runs before the hook's JSON.

**How to avoid:**
Wrap all profile output in interactive-shell guards:
```bash
[[ $- == *i* ]] && echo "Welcome to bash"
```
Test hooks by running them directly from the command line and piping to `jq` — if `jq` can't parse the output, Claude Code can't either. Run `/hooks` inside a Claude Code session to verify hooks are actually loaded and functioning.

**Warning signs:**
- Hook runs without error but structured decisions (block/allow/modify) are ignored
- `claude --verbose` shows hook output that starts with non-JSON text
- nvm, conda, or rbenv messages appear in hook output streams

**Phase to address:** Phase 1 (Hook Infrastructure) — include a hook self-test that validates JSON output is parseable before any hook goes live.

---

### Pitfall 5: SessionEnd Hook Timeout Kills Capture Logic

**What goes wrong:**
Brain mode's "auto-capture on session end" hook takes longer than 1.5 seconds (the default SessionEnd timeout). The hook is killed mid-execution. Vault writes are incomplete, partially written, or never happen. The user sees no error — Claude Code exits silently after the timeout.

**Why it happens:**
SessionEnd is designed not to block the user from exiting, so its timeout is aggressively short (1.5 seconds default). Any file I/O to a remote path, any vault indexing operation, or any subprocess call that involves network or disk latency will exceed this. It is the single hook type most affected by this constraint.

**How to avoid:**
Do not put slow operations in SessionEnd. Use PreCompact for any capture that must complete reliably. If SessionEnd capture is required, increase the timeout explicitly via environment variable and test against real vault paths (not local temp files):
```bash
CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS=5000 claude --brain
```
Instrument SessionEnd hooks with timing output during development; anything approaching 1 second is at risk.

**Warning signs:**
- Brain capture "works" in testing (local paths, fast disk) but misses entries in production (remote vault, network paths)
- BRAIN_PATH pointing to a network share or cloud-synced directory causes intermittent capture failures
- No errors reported but vault entries are missing after sessions

**Phase to address:** Phase 2 (Session Lifecycle) — explicitly test SessionEnd against the actual BRAIN_PATH target environment, not a local temp directory.

---

### Pitfall 6: BRAIN_PATH Env Var Not Set — Silent Degradation

**What goes wrong:**
Brain mode silently degrades to "do nothing" when `BRAIN_PATH` is not set. Hooks run, output success messages, but all file operations resolve to relative paths or empty strings. Vault writes go to the wrong directory (the current project directory, or `/`) or are silently skipped.

**Why it happens:**
Shell variable expansion with unset variables produces empty strings, not errors. A path like `$BRAIN_PATH/intake/session.md` becomes `/intake/session.md` or `intake/session.md` depending on the operation. This is valid syntax — no error is thrown. The feature appears to work during development because BRAIN_PATH is set in the developer's environment.

**How to avoid:**
Every hook that uses BRAIN_PATH must validate it is set and the path exists before doing anything else:
```bash
if [ -z "$BRAIN_PATH" ]; then
  echo "BRAIN_PATH is not set. Run brain onboarding or set it in your shell profile." >&2
  exit 1  # Non-blocking — warn but don't break the workflow
fi
if [ ! -d "$BRAIN_PATH" ]; then
  echo "BRAIN_PATH directory does not exist: $BRAIN_PATH" >&2
  exit 1
fi
```
The onboarding flow (Phase 3) must detect this condition and guide setup. First-run detection should verify BRAIN_PATH before activating any hooks.

**Warning signs:**
- Brain mode runs without errors but no vault files are created
- Files appear in the project directory unexpectedly
- Works on developer machine but not on a collaborator's machine
- Onboarding skip during testing masks the problem

**Phase to address:** Phase 3 (Onboarding) — BRAIN_PATH validation is the first gate in the onboarding flow. Phase 1 hooks should also contain the guard shown above.

---

### Pitfall 7: Adaptive Mentoring Logic Creates Notification Fatigue

**What goes wrong:**
The warn→silent fix→investigate mentoring escalation seems useful in design but becomes noise in practice. Users mute or ignore all brain notifications after a week of false positives. The "adaptive" system stops being consulted. Brain mode becomes decoration.

**Why it happens:**
Pattern detection for error sequences, idle states, and milestones requires heuristics. Heuristics produce false positives. If the first user experience with adaptive mentoring is an unsolicited suggestion during focused flow work, trust is broken. Notification fatigue in developer tools is well-documented — users are already managing IDE warnings, linter output, and CI alerts.

**How to avoid:**
Default to silent. Require explicit opt-in for proactive suggestions. Recommendations should only appear when the user is already paused (at a prompt, after a stop, not mid-task). Provide a clear, single-keypress way to suppress categories of advice. Track acknowledgment rate — if below 20%, the detection logic is too aggressive. Treat the mentoring system as a Phase 4+ feature, not Phase 1 infrastructure.

**Warning signs:**
- Users frequently dismiss brain suggestions without reading them
- Brain suggestions appear mid-task or interrupt flow
- "Brain mode is annoying" feedback without users being able to articulate why
- Users explicitly disable hooks to stop the suggestions

**Phase to address:** Phase 4 (Adaptive Mentoring) — start with logging only, no user-visible output, for at least one milestone before enabling visible recommendations.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode vault subpaths in hooks | Faster development | Breaks if vault structure changes; impossible to test with different layouts | Never — always derive from BRAIN_PATH |
| Load full CLAUDE.md into every hook's context | Hooks have all project context | CLAUDE.md grows; every hook invocation pays the read cost; circular dependency | Never |
| Write vault files synchronously in PreToolUse hooks | Simple logic | Adds latency to every tool use even when no brain write is needed | Never for PreToolUse; acceptable for PostToolUse |
| Skip `stop_hook_active` guard in MVP | Fewer lines of code | Infinite loop risk in first real session | Never — add the guard in the hook template from day one |
| Use `exit 1` as "block" in early testing | "Works" locally in simple tests | Security gates silently fail in production | Never |
| Bundle all skills into SessionStart | Simple "always ready" model | 100K+ token overhead kills effective session length | Never — load on demand |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| BRAIN_PATH file writes | Assume directory exists, write directly | Check `BRAIN_PATH` is set and directory exists; create subdirectories with `mkdir -p` |
| Cross-directory operations | Use relative paths from `$CLAUDE_PROJECT_DIR` | Always use `$BRAIN_PATH` as root; never assume working directory |
| Shell profile sourcing | Leave `echo` statements in `.bashrc`/`.zshrc` | Guard all profile output with `[[ $- == *i* ]]` |
| JSON output from hooks | Mix stdout text with JSON | Keep stdout clean; all non-JSON output goes to stderr |
| MCP tool matching | Use literal tool names in matchers | Use regex: `mcp__brain__.*` to match all brain server tools |
| `$CLAUDE_PLUGIN_DATA` vs state files | Write state to `$CLAUDE_PROJECT_DIR/.brain/` | Use `$CLAUDE_PLUGIN_DATA` for state that must survive plugin updates |
| SessionEnd capture | Write to vault in SessionEnd | Move critical writes to PreCompact; use SessionEnd only for lightweight metadata |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Loading full vault index at SessionStart | Session starts slow; auto-compaction fires early | Load only navigation skeleton; keep hook output under 2,000 tokens | First session with a vault over ~50 notes |
| Synchronous file scan in PreToolUse | Every tool use (file edits, bash runs) is delayed by the scan | Scope matchers narrowly; cache scan results; offload to PostToolUse | Once vault grows beyond ~20 files |
| Unbounded pattern history in memory | Pattern tracker grows without limit; JSON payload to hooks grows with each session | Rotate pattern history; keep to last 50 entries | After ~1 week of daily use |
| Duplicate skills across project directories | Workspace contexts consume 5x the expected token budget | Store generic skills in user-level `~/.claude/skills/`, not per-project | Any multi-directory workspace |
| MCP server with large tool schema | Tool definitions alone consume 17K-55K tokens before first prompt | Use Tool Search / lazy loading; audit MCP schema size | Any MCP server with more than ~10 tools |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Passing unsanitized hook input to shell commands | Code injection via crafted tool use arguments | Always use `jq` to extract specific fields; never eval or interpolate raw hook input |
| Writing session content to world-readable paths | Personal knowledge captured to `/tmp` or project directory visible to other processes | Always write to `$BRAIN_PATH` with appropriate permissions; never write to shared temp paths |
| Logging full conversation content in hooks | Sensitive session content persists in log files | Log metadata only (timestamps, categories, word counts); never log message content |
| Storing API keys in hook scripts | Credentials committed with project or readable in ps output | Use `allowedEnvVars` for HTTP hooks; never hardcode credentials in hook command strings |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Brain emoji statusline always visible | Constant reminder of monitoring; users feel watched | Make statusline opt-in; default to minimal indicator only on explicit brain actions |
| Proactive suggestions during active coding | Interrupts flow; trains users to ignore brain output | Surface suggestions only at natural pauses (prompt, session end, explicit request) |
| Onboarding that requires many steps before first value | Users abandon setup before brain mode activates | First-run flow delivers one concrete value (session capture) before asking for any configuration |
| No way to see what brain captured | Users don't trust a system they can't audit | Every capture operation logs what was written and where; provide a `/brain status` view |
| Silent failure on missing BRAIN_PATH | User thinks brain mode works; discovers nothing was saved later | Fail loudly and early with a specific fix instruction ("Set BRAIN_PATH in your shell profile") |
| Adaptive suggestions that contradict user's style | User distrust; feels like AI is overriding preferences | Learn from explicit dismissals; weight user behavior over heuristics; never suggest the same thing twice in a session |

---

## "Looks Done But Isn't" Checklist

- [ ] **Stop hook:** Verify `stop_hook_active` guard exists and is tested with a real stop sequence — not just a unit test of the bash logic
- [ ] **BRAIN_PATH validation:** Verify hook fails loudly (not silently) when BRAIN_PATH is unset — test by temporarily unsetting it
- [ ] **SessionEnd capture:** Verify capture completes against the real vault path with real latency — do not test only against `/tmp`
- [ ] **Exit codes:** Verify every hook that must block uses `exit 2` — run with a known-bad input and confirm the tool does NOT execute
- [ ] **JSON output:** Verify hook JSON parses cleanly with `| jq .` before shipping — shell profile noise commonly breaks this
- [ ] **Context overhead:** Measure actual token consumption of SessionStart hook with `claude --verbose` before claiming brain mode is "lightweight"
- [ ] **Cross-directory writes:** Verify vault writes succeed from a project directory that is NOT inside BRAIN_PATH
- [ ] **Onboarding path:** Verify first-run flow triggers when BRAIN_PATH is unset AND when it is set but vault is empty (two distinct cases)
- [ ] **Pattern tracker:** Verify history rotation works — fill the pattern store past its limit and confirm old entries are dropped
- [ ] **Mentoring dismissal:** Verify a dismissed suggestion does not re-appear in the same session

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Stop hook infinite loop | LOW | Kill the terminal; remove or fix the Stop hook in `~/.claude/settings.json`; restart |
| Context window bloat (vault overloaded) | LOW | Run `/compact` with explicit preservation instructions; reduce SessionStart hook output; restart session |
| Vault writes to wrong directory (BRAIN_PATH unset) | MEDIUM | Locate misplaced files; set BRAIN_PATH; move files to correct vault location; update hook with guard |
| Corrupted partial vault write (SessionEnd timeout) | MEDIUM | Identify incomplete files from timestamps; re-run capture manually via `/brain capture`; increase SessionEnd timeout |
| JSON parse failure from profile output | LOW | Add `[[ $- == *i* ]]` guards to shell profile; test hook output with `jq` to confirm clean output |
| Notification fatigue (mentoring over-fires) | HIGH | Disable mentoring feature entirely; audit and raise detection thresholds; re-enable with explicit user opt-in |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Stop hook infinite loop | Phase 1: Hook Infrastructure | Integration test: trigger stop with brain mode active; confirm session ends cleanly |
| Wrong exit code silences gate | Phase 1: Hook Infrastructure | Test suite: known-bad input to every blocking hook; confirm tool does NOT execute |
| Shell profile output corrupts JSON | Phase 1: Hook Infrastructure | CI check: pipe all hook output through `jq .` as part of hook test suite |
| BRAIN_PATH not set — silent degradation | Phase 3: Onboarding | Test with BRAIN_PATH unset; confirm error message with fix instruction appears |
| Context window bloat | Phase 2: Session Lifecycle | Measure token overhead of SessionStart with `claude --verbose` before shipping |
| SessionEnd timeout kills capture | Phase 2: Session Lifecycle | Test against real vault path; confirm writes complete within timeout budget |
| Adaptive mentoring notification fatigue | Phase 4: Adaptive Mentoring | Track dismissal rate for first 10 real sessions; gate on acknowledgment rate > 30% |
| Duplicate skills consuming token budget | Phase 2: Session Lifecycle | Audit skills loaded at startup; confirm generic skills live at user level, not per-project |

---

## Sources

- [Claude Code Hooks Reference — official docs](https://code.claude.com/docs/en/hooks) — HIGH confidence, authoritative
- [5 Claude Code Hook Mistakes That Silently Break Your Safety Net — DEV Community](https://dev.to/yurukusa/5-claude-code-hook-mistakes-that-silently-break-your-safety-net-58l3) — MEDIUM confidence, multiple real examples
- [Claude Code enters infinite loop when hooks are enabled — GitHub Issue #10205](https://github.com/anthropics/claude-code/issues/10205) — HIGH confidence, official issue tracker
- [When Your AI Memory System Eats Its Own Context Window — zolty.systems](https://blog.zolty.systems/posts/2026-02-23-ai-context-window-audit) — MEDIUM confidence, documented case study with measurements
- [Effective Context Engineering for AI Agents — Anthropic Engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — HIGH confidence, official Anthropic source
- [Claude Code Context Optimization: 54% token reduction — GitHub Gist](https://gist.github.com/johnlindquist/849b813e76039a908d962b2f0923dc9a) — MEDIUM confidence, verified measurements
- [Claude Code's Memory Evolution: Auto Memory & PreCompact Hooks — Yuanchang's Blog](https://yuanchang.org/en/posts/claude-code-auto-memory-and-hooks/) — MEDIUM confidence, multiple sources corroborate PreCompact behavior
- [Claude Code Session Hooks: Auto-Load Context Every Time — claudefa.st](https://claudefa.st/blog/tools/hooks/session-lifecycle-hooks) — MEDIUM confidence, practical patterns
- [UX and AI in 2026: From Experimentation to Trust — Cleverit Group](https://www.cleveritgroup.com/en/blog/ux-and-ai-in-2026-from-experimentation-to-trust) — LOW confidence, general UX research

---
*Pitfalls research for: Claude Brain Mode — Claude Code CLI Knowledge Extension*
*Researched: 2026-03-19*
