#!/usr/bin/env bash
input=$(cat)

MODEL=$(printf '%s' "$input" | jq -r '.model.display_name // "Claude"')
AGENT=$(printf '%s' "$input" | jq -r '.agent.name // ""')
PCT=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

if [ "$AGENT" = "brain-mode" ]; then
  # Read brain state from file — default to idle if file absent or BRAIN_PATH unset
  BRAIN_STATE="idle"
  if [ -n "${BRAIN_PATH:-}" ] && [ -f "$BRAIN_PATH/.brain-state" ]; then
    BRAIN_STATE=$(cut -d' ' -f1 "$BRAIN_PATH/.brain-state" 2>/dev/null || echo "idle")
  fi

  case "$BRAIN_STATE" in
    captured)
      # green circle + brain — capture ran successfully this session
      printf '\360\237\237\242\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
      ;;
    error)
      # red circle + brain — hook error or degraded state
      printf '\360\237\224\264\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
      ;;
    *)
      # idle (default) — brain active, no recent hook activity
      printf '\360\237\247\240 [%s] %s%%\n' "$MODEL" "$PCT"
      ;;
  esac
else
  printf '[%s] %s%%\n' "$MODEL" "$PCT"
fi
