#!/usr/bin/env bash
# Claude Brain Toolkit — Shell Aliases (optional)
#
# Adds convenience aliases for launching brain-mode sessions.
# Run this script to install, or source it to preview.
#
# Usage:
#   bash onboarding-kit/aliases.sh          # install aliases
#   source onboarding-kit/aliases.sh        # preview (current shell only)

# ── Alias definitions ────────────────────────────────────────────

# Standard brain-mode launch
alias brain='claude --agent brain-mode'

# Brain-mode with permissions bypass (no tool-use confirmations)
# ⚠ WARNING: This skips ALL permission prompts. Claude can read, write,
# and execute without asking. Only use in trusted project directories
# where you're comfortable with autonomous operation.
alias brain-dangerous='claude --agent brain-mode --dangerously-skip-permissions'

# ── Installer ────────────────────────────────────────────────────

# If executed (not sourced), install aliases to shell profile
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Detect shell config file
  if [ -n "$ZSH_VERSION" ] || [ "$(basename "$SHELL")" = "zsh" ]; then
    RC_FILE="$HOME/.zshrc"
  elif [ -n "$BASH_VERSION" ]; then
    RC_FILE="$HOME/.bashrc"
  else
    RC_FILE="$HOME/.profile"
  fi

  MARKER="# Claude Brain Toolkit aliases"

  if grep -q "$MARKER" "$RC_FILE" 2>/dev/null; then
    echo "Brain aliases already installed in $RC_FILE"
    echo "  To update, remove the existing block and run again."
    exit 0
  fi

  echo ""
  echo "This will add the following aliases to $RC_FILE:"
  echo ""
  echo "  brain            → claude --agent brain-mode"
  echo "  brain-dangerous  → claude --agent brain-mode --dangerously-skip-permissions"
  echo ""
  echo "⚠  brain-dangerous skips ALL permission prompts."
  echo "   Claude can read, write, and execute without confirmation."
  echo ""
  read -p "Install aliases? [y/N] " -n 1 -r
  echo ""

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    cat >> "$RC_FILE" << 'EOF'

# Claude Brain Toolkit aliases
alias brain='claude --agent brain-mode'
alias brain-dangerous='claude --agent brain-mode --dangerously-skip-permissions'
EOF
    echo "Aliases installed in $RC_FILE"
    echo "Run 'source $RC_FILE' or open a new terminal to use them."
  else
    echo "Skipped. You can run this again anytime."
  fi
fi
