#!/usr/bin/env bash
# Claude Brain Partner Kit — Automated Setup Script
# Run this from inside the claude-partner-kit directory
#
# Usage: bash setup.sh

set -e

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo ""
echo "=========================================="
echo "  Claude Brain Partner Kit — Setup"
echo "=========================================="
echo ""

# ---- Phase 1: Check prerequisites ----
echo "[1/8] Checking prerequisites..."

check_cmd() {
  if command -v "$1" &>/dev/null; then
    echo "  ✓ $1 found: $($1 --version 2>&1 | head -1)"
  else
    echo "  ✗ $1 NOT FOUND — install from $2"
    MISSING=true
  fi
}

MISSING=false
check_cmd node "https://nodejs.org/"
check_cmd git "https://git-scm.com/"
check_cmd python "https://python.org/"
check_cmd claude "Run: npm install -g @anthropic-ai/claude-code"

if [ "$MISSING" = true ]; then
  echo ""
  echo "  Some prerequisites are missing. Install them and run this script again."
  exit 1
fi

echo ""

# ---- Phase 2: Install GSD ----
echo "[2/8] Installing GSD (Get Shit Done)..."
if npm list -g get-shit-done-cc &>/dev/null; then
  echo "  ✓ GSD already installed"
else
  npm install -g get-shit-done-cc
  echo "  ✓ GSD installed"
fi
echo ""

# ---- Phase 3: Install Superpowers plugin ----
echo "[3/8] Installing Superpowers plugin..."
claude plugins install superpowers@superpowers-marketplace 2>/dev/null || echo "  (may already be installed)"
echo "  ✓ Superpowers plugin ready"
echo ""

# ---- Phase 4: Copy global skills ----
echo "[4/8] Installing global skills..."
mkdir -p "$CLAUDE_DIR/skills"
cp -r "$KIT_DIR/skills/"* "$CLAUDE_DIR/skills/"
echo "  ✓ Skills copied to $CLAUDE_DIR/skills/"
echo ""

# ---- Phase 5: Copy brain:scan command ----
echo "[5/8] Installing brain:scan command..."
mkdir -p "$CLAUDE_DIR/commands/brain"
cp "$KIT_DIR/commands/brain/scan.md" "$CLAUDE_DIR/commands/brain/scan.md"
echo "  ✓ Command copied to $CLAUDE_DIR/commands/brain/"
echo ""

# ---- Phase 6: Clone brain vault ----
echo "[6/8] Setting up brain vault..."
echo ""
echo "  Where do you want your brain vault?"
echo "  Examples:"
echo "    ~/Documents/claude_brain"
echo "    ~/Desktop/memory/claude_brain"
echo ""
read -p "  Enter path: " BRAIN_PATH

# Expand ~ manually
BRAIN_PATH="${BRAIN_PATH/#\~/$HOME}"

if [ -d "$BRAIN_PATH" ]; then
  echo "  Directory already exists. Using existing vault."
else
  echo "  Cloning brain toolkit..."
  git clone https://github.com/bizzar0helldemon/claude-brain-toolkit.git "$BRAIN_PATH"
  echo "  ✓ Brain vault created at $BRAIN_PATH"
fi

# Copy global skills from the toolkit if they exist
if [ -d "$BRAIN_PATH/global-skills" ]; then
  cp -r "$BRAIN_PATH/global-skills/"* "$CLAUDE_DIR/skills/" 2>/dev/null || true
  echo "  ✓ Brain toolkit global skills merged"
fi
echo ""

# ---- Phase 7: Configure paths in skills ----
echo "[7/8] Configuring skill paths..."

# Convert backslashes to forward slashes for consistency
BRAIN_PATH_CLEAN=$(echo "$BRAIN_PATH" | sed 's|\\|/|g')

# Update daily-note skill
if [ -f "$CLAUDE_DIR/skills/daily-note/SKILL.md" ]; then
  sed -i "s|{{BRAIN_PATH}}|$BRAIN_PATH_CLEAN|g" "$CLAUDE_DIR/skills/daily-note/SKILL.md"
  echo "  ✓ daily-note skill configured"
fi

# Update brain-capture skill
if [ -f "$CLAUDE_DIR/skills/brain-capture/SKILL.md" ]; then
  sed -i "s|{{BRAIN_PATH}}|$BRAIN_PATH_CLEAN|g" "$CLAUDE_DIR/skills/brain-capture/SKILL.md"
  echo "  ✓ brain-capture skill configured"
fi
echo ""

# ---- Phase 8: Verify ----
echo "[8/8] Verifying setup..."
echo ""

PASS=true

[ -f "$CLAUDE_DIR/settings.json" ] && echo "  ✓ settings.json exists" || { echo "  ✗ settings.json missing (GSD should have created it)"; PASS=false; }
[ -d "$CLAUDE_DIR/skills/daily-note" ] && echo "  ✓ daily-note skill installed" || { echo "  ✗ daily-note skill missing"; PASS=false; }
[ -d "$CLAUDE_DIR/skills/brain-capture" ] && echo "  ✓ brain-capture skill installed" || { echo "  ✗ brain-capture skill missing"; PASS=false; }
[ -d "$CLAUDE_DIR/skills/changelog-generator" ] && echo "  ✓ changelog-generator skill installed" || { echo "  ✗ changelog-generator skill missing"; PASS=false; }
[ -d "$CLAUDE_DIR/skills/systematic-debugging" ] && echo "  ✓ systematic-debugging skill installed" || { echo "  ✗ systematic-debugging skill missing"; PASS=false; }
[ -f "$CLAUDE_DIR/commands/brain/scan.md" ] && echo "  ✓ brain:scan command installed" || { echo "  ✗ brain:scan command missing"; PASS=false; }
[ -d "$BRAIN_PATH" ] && echo "  ✓ brain vault exists at $BRAIN_PATH" || { echo "  ✗ brain vault not found"; PASS=false; }

echo ""

if [ "$PASS" = true ]; then
  echo "=========================================="
  echo "  Setup complete!"
  echo "=========================================="
  echo ""
  echo "  Next steps:"
  echo "    1. Open your brain vault in Claude Code:"
  echo "       cd \"$BRAIN_PATH\" && claude"
  echo ""
  echo "    2. Run /brain-intake to teach Claude about you"
  echo ""
  echo "    3. Run /gsd:help to see all project commands"
  echo ""
  echo "    4. Run /daily-note to start journaling"
  echo ""
else
  echo "  Some checks failed. Review the output above."
fi
