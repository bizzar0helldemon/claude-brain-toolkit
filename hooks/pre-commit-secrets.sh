#!/usr/bin/env bash
# hooks/pre-commit-secrets.sh — PreToolUse hook
# Scans staged git diff for secrets before allowing git commit.
# Returns {"decision":"block","reason":"..."} if secrets detected.
# Silent passthrough for clean commits or non-commit commands.

HOOK_INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // ""')

# Only act on Bash tool calls
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')

# Only act on git commit commands
if ! printf '%s' "$COMMAND" | grep -q 'git commit'; then
  exit 0
fi

# Skip dry runs
if printf '%s' "$COMMAND" | grep -q '\-\-dry-run'; then
  exit 0
fi

# Get the staged diff
STAGED_DIFF=$(git diff --cached --unified=0 2>/dev/null)

# No staged changes — nothing to scan
if [ -z "$STAGED_DIFF" ]; then
  exit 0
fi

FINDINGS=""

# ── Secret pattern checks ────────────────────────────────────────

# AWS Access Key ID (AKIA...)
if printf '%s' "$STAGED_DIFF" | grep -qE 'AKIA[0-9A-Z]{16}'; then
  FINDINGS="${FINDINGS}  - AWS Access Key ID detected (AKIA...)\n"
fi

# AWS Secret Access Key (40-char base64)
if printf '%s' "$STAGED_DIFF" | grep -qE '(?<![A-Za-z0-9/+=])[A-Za-z0-9/+=]{40}(?![A-Za-z0-9/+=])' 2>/dev/null; then
  # Only flag if near AWS context
  if printf '%s' "$STAGED_DIFF" | grep -qiE '(aws|secret.?access.?key|aws_secret)'; then
    FINDINGS="${FINDINGS}  - Possible AWS Secret Access Key detected\n"
  fi
fi

# GitHub tokens (ghp_, gho_, ghu_, ghs_, ghr_)
if printf '%s' "$STAGED_DIFF" | grep -qE 'gh[pousr]_[A-Za-z0-9_]{36,}'; then
  FINDINGS="${FINDINGS}  - GitHub token detected (ghp_/gho_/ghu_/ghs_/ghr_...)\n"
fi

# Anthropic API keys
if printf '%s' "$STAGED_DIFF" | grep -qE 'sk-ant-[A-Za-z0-9_-]{20,}'; then
  FINDINGS="${FINDINGS}  - Anthropic API key detected (sk-ant-...)\n"
fi

# OpenAI API keys
if printf '%s' "$STAGED_DIFF" | grep -qE 'sk-[A-Za-z0-9]{20,}'; then
  # Exclude Anthropic keys (already caught above)
  if ! printf '%s' "$STAGED_DIFF" | grep -qE 'sk-ant-'; then
    FINDINGS="${FINDINGS}  - OpenAI API key detected (sk-...)\n"
  fi
fi

# Stripe keys (sk_live_, sk_test_, pk_live_, pk_test_)
if printf '%s' "$STAGED_DIFF" | grep -qE '[sp]k_(live|test)_[A-Za-z0-9]{20,}'; then
  FINDINGS="${FINDINGS}  - Stripe key detected\n"
fi

# Google API keys
if printf '%s' "$STAGED_DIFF" | grep -qE 'AIza[0-9A-Za-z_-]{35}'; then
  FINDINGS="${FINDINGS}  - Google API key detected (AIza...)\n"
fi

# Slack tokens (xoxb-, xoxp-, xoxs-, xoxa-)
if printf '%s' "$STAGED_DIFF" | grep -qE 'xox[bpsa]-[0-9A-Za-z-]{10,}'; then
  FINDINGS="${FINDINGS}  - Slack token detected (xox...)\n"
fi

# Private keys (RSA, SSH, PGP)
if printf '%s' "$STAGED_DIFF" | grep -qE '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----'; then
  FINDINGS="${FINDINGS}  - Private key detected (BEGIN PRIVATE KEY block)\n"
fi

# JWT tokens (eyJ...)
if printf '%s' "$STAGED_DIFF" | grep -qE 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'; then
  FINDINGS="${FINDINGS}  - JWT token detected (eyJ...)\n"
fi

# Connection strings with passwords
if printf '%s' "$STAGED_DIFF" | grep -qiE '(postgres|mysql|mongodb|redis)://[^:]+:[^@]+@'; then
  FINDINGS="${FINDINGS}  - Database connection string with embedded password detected\n"
fi

# Generic password assignments
if printf '%s' "$STAGED_DIFF" | grep -qiE '(password|passwd|pwd)\s*[=:]\s*["\x27][^"\x27]{8,}'; then
  FINDINGS="${FINDINGS}  - Hardcoded password assignment detected\n"
fi

# .env file being committed (check staged file list)
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)
if printf '%s' "$STAGED_FILES" | grep -qE '(^|/)\.env($|\.)'; then
  FINDINGS="${FINDINGS}  - .env file staged for commit — these typically contain secrets\n"
fi

# ── Emit result ──────────────────────────────────────────────────

if [ -n "$FINDINGS" ]; then
  REASON=$(printf 'Blocked: secrets detected in staged changes. Remove them before committing.\n\nFindings:\n%b\nUse git reset HEAD <file> to unstage, or move secrets to .env (and .gitignore it).' "$FINDINGS")
  printf '%s\n' "$REASON" | jq -Rs '{"decision":"block","reason":.}'
  exit 0
fi

# Clean — passthrough
exit 0
