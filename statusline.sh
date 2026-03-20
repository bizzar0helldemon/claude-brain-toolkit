#!/usr/bin/env bash
input=$(cat)

MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
AGENT=$(printf '%s' "$input" | jq -r '.agent.name // ""')
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

if [ "$AGENT" = "brain-mode" ]; then
  printf '\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
else
  printf '[%s] %s%%\n' "$MODEL" "$PCT"
fi
