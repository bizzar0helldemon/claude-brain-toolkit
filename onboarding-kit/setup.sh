#!/usr/bin/env bash
# Claude Brain Toolkit — Brain Mode Setup Script
# Run this from the repo root or from inside the onboarding-kit directory
#
# Usage: bash onboarding-kit/setup.sh
#        bash setup.sh  (if run from inside onboarding-kit/)

set -e

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$KIT_DIR/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo ""
echo "=========================================="
echo "  Claude Brain Toolkit — Brain Mode Setup"
echo "=========================================="
echo ""

# ---- Helper: check for required command ----
check_cmd() {
  if command -v "$1" &>/dev/null; then
    echo "  + $1 found: $($1 --version 2>&1 | head -1)"
  else
    echo "  x $1 NOT FOUND — install from $2"
    MISSING=true
  fi
}

# ---- Phase 1: Prerequisites ----
echo "[1/9] Checking prerequisites..."

MISSING=false
check_cmd node "https://nodejs.org/"
check_cmd git "https://git-scm.com/"
check_cmd jq "https://jqlang.github.io/jq/download/"
check_cmd claude "Run: npm install -g @anthropic-ai/claude-code"

if [ "$MISSING" = true ]; then
  echo ""
  echo "  Some prerequisites are missing. Install them and run this script again."
  exit 1
fi

echo ""

# ---- Phase 2: Deploy brain-mode agent ----
echo "[2/9] Deploying brain-mode agent..."

mkdir -p "$CLAUDE_DIR/agents"
cp "$REPO_DIR/agents/brain-mode.md" "$CLAUDE_DIR/agents/brain-mode.md"
echo "  + brain-mode.md deployed to $CLAUDE_DIR/agents/"

echo ""

# ---- Phase 3: Deploy global skills ----
echo "[3/9] Deploying global skills..."

SKILL_COUNT=0

# Copy global skills (brain-capture, daily-note, brain-audit)
for SKILL_DIR in "$REPO_DIR/global-skills"/*/; do
  SKILL_NAME="$(basename "$SKILL_DIR")"
  mkdir -p "$CLAUDE_DIR/skills/$SKILL_NAME"
  cp -r "$SKILL_DIR"* "$CLAUDE_DIR/skills/$SKILL_NAME/"
  SKILL_COUNT=$((SKILL_COUNT + 1))
  echo "  + $SKILL_NAME deployed"
done

# Copy onboarding-kit skills (brain-setup and any others)
for SKILL_DIR in "$KIT_DIR/skills"/*/; do
  SKILL_NAME="$(basename "$SKILL_DIR")"
  mkdir -p "$CLAUDE_DIR/skills/$SKILL_NAME"
  cp -r "$SKILL_DIR"* "$CLAUDE_DIR/skills/$SKILL_NAME/"
  SKILL_COUNT=$((SKILL_COUNT + 1))
  echo "  + $SKILL_NAME deployed"
done

# Template substitution: replace {{SET_YOUR_BRAIN_PATH}} with $BRAIN_PATH env var reference
# Portable pattern: temp file + mv (NOT sed -i which differs between macOS and GNU)
for SKILL_FILE in \
  "$CLAUDE_DIR/skills/brain-capture/SKILL.md" \
  "$CLAUDE_DIR/skills/daily-note/SKILL.md" \
  "$CLAUDE_DIR/skills/brain-audit/SKILL.md"; do
  if [ -f "$SKILL_FILE" ]; then
    sed "s|{{SET_YOUR_BRAIN_PATH}}|\$BRAIN_PATH|g" "$SKILL_FILE" > "$SKILL_FILE.tmp" && mv "$SKILL_FILE.tmp" "$SKILL_FILE"
  fi
done

echo "  + $SKILL_COUNT skills deployed, placeholders substituted with \$BRAIN_PATH"

echo ""

# ---- Phase 4: Deploy hook scripts ----
echo "[4/9] Deploying hook scripts..."

mkdir -p "$CLAUDE_DIR/hooks/lib"

cp "$REPO_DIR/hooks/session-start.sh" "$CLAUDE_DIR/hooks/session-start.sh"
cp "$REPO_DIR/hooks/stop.sh" "$CLAUDE_DIR/hooks/stop.sh"
cp "$REPO_DIR/hooks/pre-compact.sh" "$CLAUDE_DIR/hooks/pre-compact.sh"
cp "$REPO_DIR/hooks/post-tool-use-failure.sh" "$CLAUDE_DIR/hooks/post-tool-use-failure.sh"
cp "$REPO_DIR/hooks/post-tool-use.sh" "$CLAUDE_DIR/hooks/post-tool-use.sh"

cp "$REPO_DIR/hooks/lib/brain-path.sh" "$CLAUDE_DIR/hooks/lib/brain-path.sh"
cp "$REPO_DIR/hooks/lib/brain-context.sh" "$CLAUDE_DIR/hooks/lib/brain-context.sh"

chmod +x "$CLAUDE_DIR/hooks/"*.sh

echo "  + session-start.sh deployed"
echo "  + stop.sh deployed"
echo "  + pre-compact.sh deployed"
echo "  + post-tool-use-failure.sh deployed"
echo "  + post-tool-use.sh deployed"
echo "  + lib/brain-path.sh deployed"
echo "  + lib/brain-context.sh deployed"

echo ""

# ---- Phase 5: Deploy statusline ----
echo "[5/9] Deploying statusline..."

cp "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
chmod +x "$CLAUDE_DIR/statusline.sh"
echo "  + statusline.sh deployed to $CLAUDE_DIR/"

echo ""

# ---- Phase 5b: Deploy slash commands ----
echo "[5b/9] Deploying slash commands..."

mkdir -p "$CLAUDE_DIR/commands/brain"
cp "$REPO_DIR/commands/brain-add-pattern.md" "$CLAUDE_DIR/commands/brain/brain-add-pattern.md"
echo "  + brain-add-pattern.md deployed to $CLAUDE_DIR/commands/brain/"

echo ""

# ---- Phase 6: Merge brain hooks into ~/.claude/settings.json ----
echo "[6/9] Updating ~/.claude/settings.json..."

SETTINGS="$CLAUDE_DIR/settings.json"

# Create settings.json if it doesn't exist
if [ ! -f "$SETTINGS" ]; then
  echo '{"hooks":{}}' > "$SETTINGS"
  echo "  + Created new $SETTINGS"
fi

TEMP="$SETTINGS.tmp"

# Brain hooks object to merge in
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

# Merge: for each hook type, append brain hook entry if the command is not already registered
# Then set statusLine. Idempotent — running twice will not duplicate entries.
jq --argjson bh "$BRAIN_HOOKS" '
  reduce ($bh | keys[]) as $key (.;
    if ((.hooks[$key] // []) | map(.hooks[]?.command) | index($bh[$key][0].hooks[0].command)) != null
    then .
    else .hooks[$key] = ((.hooks[$key] // []) + $bh[$key])
    end
  )
  | .statusLine = {"type":"command","command":"~/.claude/statusline.sh"}
' "$SETTINGS" > "$TEMP" && mv "$TEMP" "$SETTINGS"

# Remove async:true from PostToolUseFailure (Phase 4 requirement: sync hooks only)
jq '
  if .hooks.PostToolUseFailure then
    .hooks.PostToolUseFailure = [
      .hooks.PostToolUseFailure[] |
      .hooks = [.hooks[] | del(.async)]
    ]
  else . end
' "$SETTINGS" > "$TEMP" && mv "$TEMP" "$SETTINGS"

echo "  + Brain hooks merged into $SETTINGS (idempotent)"
echo "  + statusLine set to ~/.claude/statusline.sh"

echo ""

# ---- Phase 7: BRAIN_PATH configuration ----
echo "[7/9] Checking BRAIN_PATH configuration..."

if [ -n "$BRAIN_PATH" ] && [ -d "$BRAIN_PATH" ]; then
  echo "  + BRAIN_PATH already configured: $BRAIN_PATH"
elif [ -n "$BRAIN_PATH" ] && [ ! -d "$BRAIN_PATH" ]; then
  echo "  ! BRAIN_PATH is set to '$BRAIN_PATH' but the directory does not exist."
  echo "    Start Claude Code and run /brain-setup to create your vault."
else
  echo "  ! BRAIN_PATH is not yet configured."
  echo "    Start Claude Code and run /brain-setup to complete first-time vault setup."
fi

echo ""

# ---- Phase 8: Verification ----
echo "[8/9] Verifying deployment..."
echo ""

PASS=true

check_file() {
  if [ -f "$1" ]; then
    echo "  + $2"
  else
    echo "  x MISSING: $1"
    PASS=false
  fi
}

check_file "$CLAUDE_DIR/agents/brain-mode.md"                   "agents/brain-mode.md"
check_file "$CLAUDE_DIR/skills/brain-capture/SKILL.md"          "skills/brain-capture/SKILL.md"
check_file "$CLAUDE_DIR/skills/daily-note/SKILL.md"             "skills/daily-note/SKILL.md"
check_file "$CLAUDE_DIR/skills/brain-audit/SKILL.md"            "skills/brain-audit/SKILL.md"
check_file "$CLAUDE_DIR/skills/brain-setup/SKILL.md"            "skills/brain-setup/SKILL.md"
check_file "$CLAUDE_DIR/hooks/session-start.sh"                 "hooks/session-start.sh"
check_file "$CLAUDE_DIR/hooks/stop.sh"                          "hooks/stop.sh"
check_file "$CLAUDE_DIR/hooks/pre-compact.sh"                   "hooks/pre-compact.sh"
check_file "$CLAUDE_DIR/hooks/post-tool-use-failure.sh"         "hooks/post-tool-use-failure.sh"
check_file "$CLAUDE_DIR/hooks/post-tool-use.sh"                 "hooks/post-tool-use.sh"
check_file "$CLAUDE_DIR/hooks/lib/brain-path.sh"                "hooks/lib/brain-path.sh"
check_file "$CLAUDE_DIR/hooks/lib/brain-context.sh"             "hooks/lib/brain-context.sh"
check_file "$CLAUDE_DIR/statusline.sh"                          "statusline.sh"
check_file "$CLAUDE_DIR/commands/brain/brain-add-pattern.md"    "commands/brain/brain-add-pattern.md"

# Check settings.json contains brain hooks
if jq '.hooks.SessionStart' "$SETTINGS" 2>/dev/null | grep -q "session-start.sh"; then
  echo "  + settings.json contains brain SessionStart hook"
else
  echo "  x settings.json missing brain SessionStart hook"
  PASS=false
fi

if jq '.hooks.PostToolUse' "$SETTINGS" 2>/dev/null | grep -q "post-tool-use.sh"; then
  echo "  + settings.json contains brain PostToolUse hook"
else
  echo "  x settings.json missing brain PostToolUse hook"
  PASS=false
fi

echo ""

# ---- Phase 9: Next steps ----
echo "[9/9] Done."
echo ""

if [ "$PASS" = true ]; then
  echo "=========================================="
  echo "  Setup complete!"
  echo "=========================================="
  echo ""
  echo "  Start brain mode:"
  echo "    claude --agent brain-mode"
  echo ""
  if [ -z "$BRAIN_PATH" ]; then
    echo "  First time? Run /brain-setup after starting Claude"
    echo "  to create your vault and configure your BRAIN_PATH."
    echo ""
  fi
else
  echo "  Some verification checks failed. Review the output above."
  exit 1
fi
