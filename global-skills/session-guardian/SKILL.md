---
name: session-guardian
description: Context checkpoint detection and runaway research prevention — auto-warns at 70%/85% context usage and detects unfocused exploration loops.
argument-hint: [--status]
---

# Session Guardian — Context & Focus Protection

Monitors your session for two risks that cause partial achievement:

1. **Context exhaustion** — warns at 70%, auto-handoff at 85%
2. **Runaway research** — detects 5+ consecutive reads without writes

This skill works both **proactively** (as a hook via PostToolUse) and **on-demand** (as a slash command for status checks).

**Usage**: `/session-guardian [--status]`

- `/session-guardian` — show current session metrics and risk assessment
- `/session-guardian --status` — same as above (quick check)

## How It Works (Proactive Mode)

The PostToolUse hook tracks session metrics in `$BRAIN_PATH/.brain-session-metrics.json`. On every tool call, it:

1. Reads context window percentage from the hook input
2. Increments read/write counters based on tool type
3. Checks thresholds and injects warnings when crossed

### Context Checkpoint Detection

| Threshold | Action |
|-----------|--------|
| **< 70%** | Silent — no intervention |
| **70%** | Inject warning: "Context at {N}%. Consider wrapping up current work or running `/brain-handoff --lite` to preserve progress." |
| **85%** | Inject urgent warning: "Context at {N}%. Auto-creating handoff to preserve session progress. Run `/brain-handoff` now for a complete handoff, or `/brain-handoff --lite` for a quick one." |

**One warning per threshold per session.** The hook tracks `warned_70` and `warned_85` flags to avoid repeated warnings.

### Runaway Research Detection

Track tool calls by category:

| Category | Tools |
|----------|-------|
| **Read** | Read, Grep, Glob, WebFetch, WebSearch |
| **Write** | Write, Edit, Bash (when command contains write-like operations) |
| **Neutral** | Agent, TaskCreate, TaskUpdate (don't affect the counter) |

**Detection rule:** If `consecutive_reads >= 5` with zero writes in between:

> "You've made {N} consecutive read operations without writing anything. This may indicate unfocused exploration. Consider: (1) acting on what you've learned so far, (2) narrowing your search focus, or (3) documenting your findings with a note."

**Reset:** The consecutive read counter resets to 0 whenever a Write-category tool is used.

## Metrics File

Path: `$BRAIN_PATH/.brain-session-metrics.json`

```json
{
  "session_start": "2026-04-01T20:00:00Z",
  "total_reads": 0,
  "total_writes": 0,
  "consecutive_reads": 0,
  "last_context_pct": 0,
  "warned_70": false,
  "warned_85": false,
  "warned_runaway": false
}
```

**Lifecycle:**
- Created fresh at session start (SessionStart hook resets it)
- Updated on every PostToolUse call
- Read by `/session-guardian --status` for on-demand checks

## On-Demand Mode (`/session-guardian`)

When invoked as a slash command, read the metrics file and present:

```
Session Guardian — Status

  Context: {N}% [{status_emoji} {status_label}]
  Duration: {time}
  Reads: {N} | Writes: {N} | Ratio: {N}:{N}
  Consecutive reads: {N}

  {risk_assessment}
```

**Risk assessment logic:**
- Context < 70%, reads balanced: "All clear — session is healthy."
- Context 70-84%: "Approaching context limit. Consider creating a handoff soon."
- Context >= 85%: "Critical — create a handoff now to preserve your work."
- Consecutive reads >= 5: "Research focus may be drifting. Consider acting on findings."
- Consecutive reads >= 10: "Heavy exploration without output. Strongly recommend documenting or acting on what you've found."

## Hook Implementation

### PostToolUse Hook Extension

The session guardian piggybacks on the existing `post-tool-use.sh` hook. Add a call to `session-guardian-check.sh` at the top of the hook, before the git commit detection logic.

Alternatively, register as a **separate** PostToolUse hook entry in `settings.json` so it runs independently. This is cleaner — one hook per concern.

**Hook file:** `hooks/session-guardian.sh`

```bash
#!/usr/bin/env bash
HOOK_INPUT=$(cat)

source ~/.claude/hooks/lib/brain-path.sh

if ! brain_path_validate; then
  exit 0
fi

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // ""')
CONTEXT_PCT=$(printf '%s' "$HOOK_INPUT" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

METRICS_FILE="$BRAIN_PATH/.brain-session-metrics.json"

# Initialize metrics if missing
if [ ! -f "$METRICS_FILE" ]; then
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"session_start":"%s","total_reads":0,"total_writes":0,"consecutive_reads":0,"last_context_pct":0,"warned_70":false,"warned_85":false,"warned_runaway":false}\n' "$NOW" > "$METRICS_FILE"
fi

# Classify tool
IS_READ=0
IS_WRITE=0
case "$TOOL_NAME" in
  Read|Grep|Glob|WebFetch|WebSearch) IS_READ=1 ;;
  Write|Edit) IS_WRITE=1 ;;
  Bash)
    CMD=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')
    if printf '%s' "$CMD" | grep -qE '(git commit|git push|mkdir|touch|cp |mv )'; then
      IS_WRITE=1
    else
      IS_READ=1
    fi
    ;;
esac

# Update metrics
if [ "$IS_READ" -eq 1 ]; then
  jq '.total_reads += 1 | .consecutive_reads += 1 | .last_context_pct = ($pct | tonumber)' \
    --arg pct "$CONTEXT_PCT" "$METRICS_FILE" > "${METRICS_FILE}.tmp" && \
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
elif [ "$IS_WRITE" -eq 1 ]; then
  jq '.total_writes += 1 | .consecutive_reads = 0 | .last_context_pct = ($pct | tonumber)' \
    --arg pct "$CONTEXT_PCT" "$METRICS_FILE" > "${METRICS_FILE}.tmp" && \
    mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
fi

# Read current state
WARNED_70=$(jq -r '.warned_70' "$METRICS_FILE")
WARNED_85=$(jq -r '.warned_85' "$METRICS_FILE")
WARNED_RUNAWAY=$(jq -r '.warned_runaway' "$METRICS_FILE")
CONSEC_READS=$(jq -r '.consecutive_reads' "$METRICS_FILE")

# Check context thresholds
if [ "$CONTEXT_PCT" -ge 85 ] && [ "$WARNED_85" = "false" ]; then
  jq '.warned_85 = true' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
  REASON="Session Guardian: Context at ${CONTEXT_PCT}%. Auto-creating handoff to preserve session progress. Run /brain-handoff now for a complete handoff, or /brain-handoff --lite for a quick one."
  emit_json "$(jq -n --arg r "$REASON" '{"decision":"block","reason":$r}')"
  exit 0
elif [ "$CONTEXT_PCT" -ge 70 ] && [ "$WARNED_70" = "false" ]; then
  jq '.warned_70 = true' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
  REASON="Session Guardian: Context at ${CONTEXT_PCT}%. Consider wrapping up current work or running /brain-handoff --lite to preserve progress."
  emit_json "$(jq -n --arg r "$REASON" '{"decision":"block","reason":$r}')"
  exit 0
fi

# Check runaway research
if [ "$CONSEC_READS" -ge 5 ] && [ "$WARNED_RUNAWAY" = "false" ]; then
  jq '.warned_runaway = true' "$METRICS_FILE" > "${METRICS_FILE}.tmp" && mv "${METRICS_FILE}.tmp" "$METRICS_FILE"
  REASON="Session Guardian: ${CONSEC_READS} consecutive read operations without writing. This may indicate unfocused exploration. Consider acting on what you've learned, narrowing your search, or documenting findings."
  emit_json "$(jq -n --arg r "$REASON" '{"decision":"block","reason":$r}')"
  exit 0
fi

# All clear — passthrough
exit 0
```

### SessionStart Hook Extension

Reset the metrics file at session start. Add to `session-start.sh` or register as a separate SessionStart hook:

```bash
# Reset session guardian metrics
if [ -n "${BRAIN_PATH:-}" ] && [ -d "$BRAIN_PATH" ]; then
  NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"session_start":"%s","total_reads":0,"total_writes":0,"consecutive_reads":0,"last_context_pct":0,"warned_70":false,"warned_85":false,"warned_runaway":false}\n' "$NOW" > "$BRAIN_PATH/.brain-session-metrics.json"
fi
```

## Error Handling

| Error | Action |
|-------|--------|
| `BRAIN_PATH` not set | Degrade gracefully — skip all checks |
| Metrics file corrupt | Re-initialize with defaults |
| `jq` update fails | Log error, skip check, don't block |
| Context % unavailable | Skip context check, still track reads/writes |

## Design Principles

- **One warning per threshold.** Never nag — each threshold fires once per session.
- **Non-blocking for reads/writes.** Only block to deliver the warning message, then resume.
- **Lightweight.** This hook fires on every tool call — keep it fast (< 100ms).
- **Additive to handoff.** Session guardian doesn't replace `/brain-handoff` — it triggers it.
