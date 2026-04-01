#!/usr/bin/env bash
# hooks/loop-detector.sh — PreToolUse hook
# Detects when an agent repeats identical tool calls 5+ times.
# State tracked in /tmp/brain-loop-state-<ppid>.json (per-session).
# Returns {"decision":"block","reason":"..."} when loop detected.
# Silent passthrough otherwise.

HOOK_INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // ""')
TOOL_INPUT=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input // {} | tostring' | head -c 200)

# Build a fingerprint: tool name + first 200 chars of input
FINGERPRINT="${TOOL_NAME}:${TOOL_INPUT}"

# Session-scoped state file (PPID groups all hooks in one Claude session)
STATE_FILE="/tmp/brain-loop-state-${PPID}.json"
THRESHOLD=5

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  printf '{"calls":[]}\n' > "$STATE_FILE"
fi

# Read current state
CURRENT_CALLS=$(jq -r '.calls | length' "$STATE_FILE" 2>/dev/null || echo 0)

# Count how many recent calls match this fingerprint
# Keep a rolling window of last 20 calls
MATCH_COUNT=$(jq --arg fp "$FINGERPRINT" '[.calls[] | select(. == $fp)] | length' "$STATE_FILE" 2>/dev/null || echo 0)

# Append this call to the rolling window (keep last 20)
jq --arg fp "$FINGERPRINT" '.calls = (.calls + [$fp] | .[-20:])' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null && \
  mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null

# Check if we've hit the threshold
if [ "$MATCH_COUNT" -ge "$THRESHOLD" ]; then
  ACTUAL_COUNT=$((MATCH_COUNT + 1))
  printf '{"decision":"block","reason":"Loop detected: identical tool call repeated %d times (tool: %s). You appear to be stuck in a loop. Try a different approach or ask the user for guidance."}\n' \
    "$ACTUAL_COUNT" "$TOOL_NAME"
  exit 0
fi

# Below threshold — passthrough
exit 0
