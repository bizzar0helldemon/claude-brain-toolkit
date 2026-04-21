#!/usr/bin/env bash
# bootstrap-linear-inbox.sh
#
# One-time setup: ensures an "Inbox" team exists in the user's Linear workspace.
# Idempotent — safe to run multiple times.
#
# Prerequisites:
#   - LINEAR_API_KEY environment variable set
#     (generate at https://linear.app/settings/account/security)
#
# Usage:
#   bash scripts/bootstrap-linear-inbox.sh
#
# Exit codes:
#   0 — Inbox team exists (either pre-existing or just created)
#   1 — LINEAR_API_KEY not set
#   2 — Linear API error (network / auth / rate limit)
#   3 — Unexpected response format

set -euo pipefail

API_URL="https://api.linear.app/graphql"
TEAM_NAME="Inbox"
TEAM_KEY="INBOX"
TEAM_DESCRIPTION="Catch-all for one-offs, scratch work, quick fixes, and exploratory tickets that don't yet belong to their own team or project."

# ─── Preflight ────────────────────────────────────────────────────────────────

if [[ -z "${LINEAR_API_KEY:-}" ]]; then
  cat >&2 <<'ERR'
ERROR: LINEAR_API_KEY is not set.

Generate a personal API key at:
  https://linear.app/settings/account/security

Then add to your shell profile (~/.bashrc / ~/.zshrc):
  export LINEAR_API_KEY="lin_api_..."

Reload your shell (or source the profile) and re-run this script.
ERR
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: curl is not installed. Install curl and re-run." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is not installed. Install jq (apt/brew install jq) and re-run." >&2
  exit 1
fi

# ─── Step 1: Check if Inbox team already exists ───────────────────────────────

echo "→ Checking for existing Inbox team..."

QUERY_BODY=$(jq -n \
  --arg query '{ teams(filter: { name: { eq: "Inbox" } }) { nodes { id name key } } }' \
  '{query: $query}')

LIST_RESPONSE=$(curl -sS -X POST "$API_URL" \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$QUERY_BODY")

# Check for GraphQL errors
if echo "$LIST_RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
  echo "ERROR: Linear API returned errors:" >&2
  echo "$LIST_RESPONSE" | jq '.errors' >&2
  exit 2
fi

EXISTING_COUNT=$(echo "$LIST_RESPONSE" | jq '.data.teams.nodes | length')

if [[ "$EXISTING_COUNT" -gt 0 ]]; then
  EXISTING_ID=$(echo "$LIST_RESPONSE" | jq -r '.data.teams.nodes[0].id')
  EXISTING_KEY=$(echo "$LIST_RESPONSE" | jq -r '.data.teams.nodes[0].key')
  cat <<EOF
✓ Inbox team already exists.
  ID:   $EXISTING_ID
  Key:  $EXISTING_KEY

No action needed. You can now run /brain-bind-project in any repo
to bind it to Linear, or file one-off tickets directly to the Inbox team.
EOF
  exit 0
fi

# ─── Step 2: Create the Inbox team ────────────────────────────────────────────

echo "→ Inbox team not found. Creating..."

MUTATION=$(jq -n \
  --arg name "$TEAM_NAME" \
  --arg key "$TEAM_KEY" \
  --arg desc "$TEAM_DESCRIPTION" \
  --arg query 'mutation($name: String!, $key: String!, $description: String) { teamCreate(input: { name: $name, key: $key, description: $description }) { success team { id name key } } }' \
  '{query: $query, variables: {name: $name, key: $key, description: $desc}}')

CREATE_RESPONSE=$(curl -sS -X POST "$API_URL" \
  -H "Authorization: $LINEAR_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$MUTATION")

if echo "$CREATE_RESPONSE" | jq -e '.errors' >/dev/null 2>&1; then
  echo "ERROR: Linear API returned errors during team creation:" >&2
  echo "$CREATE_RESPONSE" | jq '.errors' >&2
  exit 2
fi

SUCCESS=$(echo "$CREATE_RESPONSE" | jq -r '.data.teamCreate.success // false')

if [[ "$SUCCESS" != "true" ]]; then
  echo "ERROR: Unexpected response format (teamCreate.success was not true):" >&2
  echo "$CREATE_RESPONSE" | jq '.' >&2
  exit 3
fi

NEW_ID=$(echo "$CREATE_RESPONSE" | jq -r '.data.teamCreate.team.id')
NEW_KEY=$(echo "$CREATE_RESPONSE" | jq -r '.data.teamCreate.team.key')

cat <<EOF
✓ Inbox team created successfully.
  Name: Inbox
  ID:   $NEW_ID
  Key:  $NEW_KEY

This team is now your fallback for any work that doesn't merit its own
team or project. One-off tickets, scratch work, and exploratory
investigations should land here.

Next steps:
  - In any repo without a .brain.md, run /brain-bind-project to bind
    the repo to the appropriate team/project (or fall back to Inbox).
  - See docs/NEW-PROJECT-SOP.md for the full decision procedure.
EOF
