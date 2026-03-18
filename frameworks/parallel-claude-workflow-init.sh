#!/bin/bash
# =============================================================================
# parallel-workflow-init.sh
# 
# Initializes the parallel Claude Code workflow branching structure
# on any existing git repository.
#
# Usage:
#   bash parallel-workflow-init.sh
#   bash parallel-workflow-init.sh --operator stephen
#   bash parallel-workflow-init.sh --operator stephen --partner partner
#
# Run this from the root of the project repo you want to set up.
# =============================================================================

set -e

# --- Defaults ---
OPERATOR="stephen"
PARTNER="partner"
BRAIN_REPO_PATH=""   # Optional: path to your brain repo for symlinking

# --- Arg parsing ---
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --operator) OPERATOR="$2"; shift ;;
    --partner) PARTNER="$2"; shift ;;
    --brain) BRAIN_REPO_PATH="$2"; shift ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

# --- Verify we're in a git repo ---
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "ERROR: Not inside a git repository. Run this from your project root."
  exit 1
fi

PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
CURRENT_BRANCH=$(git branch --show-current)

echo ""
echo "=============================================="
echo "  Parallel Workflow Init"
echo "  Project : $PROJECT_NAME"
echo "  Operator: $OPERATOR"
echo "  Partner : $PARTNER"
echo "=============================================="
echo ""

# --- Ensure main branch exists ---
if ! git show-ref --verify --quiet refs/heads/main; then
  echo "[+] Renaming current branch to 'main'..."
  git branch -m "$CURRENT_BRANCH" main
fi

git checkout main

# --- Create dev branch if it doesn't exist ---
if git show-ref --verify --quiet refs/heads/dev; then
  echo "[=] 'dev' branch already exists, skipping."
else
  echo "[+] Creating 'dev' branch from main..."
  git checkout -b dev
  git checkout main
fi

echo ""
echo "Branch structure ready:"
echo "  main  ← stable, production-ready"
echo "  dev   ← integration branch"
echo ""
echo "Working branch convention:"
echo "  $OPERATOR/[task-name]"
echo "  $PARTNER/[task-name]"
echo ""

# --- Create handoffs directory in project (optional local copy) ---
if [ ! -d "handoffs" ]; then
  echo "[+] Creating handoffs/ directory..."
  mkdir -p handoffs
  cat > handoffs/.gitkeep << 'EOF'
# Handoff notes live here.
# Format: YYYY-MM-DD-[operator]-[task].md
# See PARALLEL_WORKFLOW.md in the brain repo for the full template.
EOF
  git add handoffs/.gitkeep
  git commit -m "chore: initialize parallel workflow structure"
  echo "[+] Committed handoffs/ directory."
else
  echo "[=] handoffs/ already exists, skipping."
fi

# --- Optional: add .claudeignore hint ---
if [ ! -f ".claudeignore" ]; then
  echo "[+] Creating .claudeignore..."
  cat > .claudeignore << EOF
# Files Claude Code instances should not touch without explicit instruction
# Add sensitive configs, generated files, or cross-scope files here

.env
.env.*
*.lock
node_modules/
dist/
build/
EOF
  git add .claudeignore
  git commit -m "chore: add .claudeignore for Claude Code scope discipline"
  echo "[+] Committed .claudeignore."
else
  echo "[=] .claudeignore already exists, skipping."
fi

# --- Optional: symlink to brain repo PARALLEL_WORKFLOW.md ---
if [ -n "$BRAIN_REPO_PATH" ]; then
  WORKFLOW_DOC="$BRAIN_REPO_PATH/PARALLEL_WORKFLOW.md"
  if [ -f "$WORKFLOW_DOC" ]; then
    echo "[+] Linking PARALLEL_WORKFLOW.md from brain repo..."
    ln -sf "$WORKFLOW_DOC" ./PARALLEL_WORKFLOW.md
    echo "[=] Symlink created: ./PARALLEL_WORKFLOW.md -> $WORKFLOW_DOC"
  else
    echo "[!] Brain repo path provided but PARALLEL_WORKFLOW.md not found at: $WORKFLOW_DOC"
  fi
fi

# --- Done ---
echo ""
echo "=============================================="
echo "  Setup complete. You're on: $(git branch --show-current)"
echo ""
echo "  To start your first parallel session:"
echo ""
echo "  Terminal 1:"
echo "    git checkout dev && git pull origin dev"
echo "    git checkout -b $OPERATOR/[task-a]"
echo "    claude"
echo ""
echo "  Terminal 2:"
echo "    git checkout dev && git pull origin dev"
echo "    git checkout -b $OPERATOR/[task-b]"
echo "    claude"
echo ""
echo "  Read PARALLEL_WORKFLOW.md before your first session."
echo "=============================================="
echo ""
