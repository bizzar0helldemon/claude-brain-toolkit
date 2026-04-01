#!/usr/bin/env bash
# hooks/risk-classifier.sh — PreToolUse hook
# Blocks dangerous bash commands before execution.
# Returns {"decision":"block","reason":"..."} for hard-deny patterns.
# Returns {"decision":"warn","reason":"..."} for advisory patterns.
# Silent passthrough for safe commands.

HOOK_INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // ""')

# Only act on Bash tool calls
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

# Normalize: collapse whitespace, lowercase for matching
CMD_LOWER=$(printf '%s' "$COMMAND" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ')

# ── Hard-deny patterns (must-block) ─────────────────────────────

# git reset --hard
if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+reset\s+--hard'; then
  printf '{"decision":"block","reason":"Blocked: git reset --hard — this discards all uncommitted changes irreversibly. Use git stash or create a backup branch first."}\n'
  exit 0
fi

# git clean -f (with or without -d, -x, etc.)
if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+clean\s+-[a-z]*f'; then
  printf '{"decision":"block","reason":"Blocked: git clean -f — this permanently deletes untracked files. Review with git clean -n (dry-run) first."}\n'
  exit 0
fi

# git push --force to main/master
if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+push\s+.*--force' || \
   printf '%s' "$CMD_LOWER" | grep -qE 'git\s+push\s+-f'; then
  if printf '%s' "$CMD_LOWER" | grep -qE '(main|master)'; then
    printf '{"decision":"block","reason":"Blocked: force push to main/master — this rewrites shared history and can cause data loss for the entire team."}\n'
    exit 0
  fi
fi

# rm -rf on broad paths (/, ~, $HOME, .., or paths with fewer than 3 components)
if printf '%s' "$CMD_LOWER" | grep -qE 'rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r'; then
  if printf '%s' "$CMD_LOWER" | grep -qE 'rm\s+-rf\s+(/|~/|\$home|\.\./)'; then
    printf '{"decision":"block","reason":"Blocked: rm -rf on a broad path — this could delete critical files. Be more specific about what to remove."}\n'
    exit 0
  fi
fi

# chmod 777
if printf '%s' "$CMD_LOWER" | grep -qE 'chmod\s+777'; then
  printf '{"decision":"block","reason":"Blocked: chmod 777 — this makes files world-readable/writable/executable. Use more restrictive permissions (e.g., 755 or 644)."}\n'
  exit 0
fi

# Database destructive operations
if printf '%s' "$CMD_LOWER" | grep -qE 'drop\s+(table|database|schema|index)'; then
  printf '{"decision":"block","reason":"Blocked: DROP operation — this permanently destroys database objects. Verify this is intentional and consider backing up first."}\n'
  exit 0
fi

if printf '%s' "$CMD_LOWER" | grep -qE 'delete\s+from\s+\w+\s*;?\s*$' | grep -qvE 'where'; then
  # DELETE FROM table without WHERE clause
  printf '{"decision":"block","reason":"Blocked: DELETE FROM without WHERE clause — this deletes all rows. Add a WHERE clause to target specific records."}\n'
  exit 0
fi

# truncate table
if printf '%s' "$CMD_LOWER" | grep -qE 'truncate\s+table'; then
  printf '{"decision":"block","reason":"Blocked: TRUNCATE TABLE — this deletes all rows irreversibly. Verify this is intentional."}\n'
  exit 0
fi

# ── Advisory patterns (warn, don't block) ────────────────────────

# --no-verify on git commands
if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+.*--no-verify'; then
  printf '{"decision":"warn","reason":"Advisory: --no-verify skips pre-commit hooks. This bypasses safety checks. Consider running hooks and fixing any issues."}\n'
  exit 0
fi

# git checkout . or git restore . (discard all changes)
if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+(checkout|restore)\s+\.\s*$'; then
  printf '{"decision":"warn","reason":"Advisory: this discards all unstaged changes in the working directory. Consider git stash if you might need these changes later."}\n'
  exit 0
fi

# Force push to non-protected branches (caught after main/master block above)
if printf '%s' "$CMD_LOWER" | grep -qE 'git\s+push\s+.*--force|git\s+push\s+-f'; then
  printf '{"decision":"warn","reason":"Advisory: force push rewrites remote history. Make sure no one else is working on this branch."}\n'
  exit 0
fi

# Safe command — passthrough
exit 0
