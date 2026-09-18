#!/bin/bash
# Phase 2: Quality checks script for PR workflow
# Shows recent changes + full PR context, runs checks on entire PR
# Usage: ./pr-2-run-checks.sh

set -euo pipefail

# Disable git pager to prevent opening vi/less
export GIT_PAGER=cat

# Color codes for better readability
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Environment validation
command -v git >/dev/null || { echo "Error: git not found"; exit 1; }
command -v pnpm >/dev/null || { echo "Error: pnpm not found"; exit 1; }

# Get base branch (default: origin/master, because local master is often stale)
BASE_BRANCH="${1:-origin/master}"
CURRENT_BRANCH=$(git branch --show-current)

git fetch origin +refs/heads/master:refs/remotes/origin/master --quiet 2>/dev/null || {
  echo -e "${YELLOW}⚠️  Could not refresh origin/master; using local ref${NC}"
}

echo "=== PHASE 1 QUALITY CHECKS REPORT ==="
echo ""

# 1. Recent changes (since last push)
echo "## Recent Changes (Since Last Push)"
echo ""
if ! git diff --quiet HEAD; then
  echo "### Uncommitted Changes"
  git diff HEAD --stat
  echo ""
  git diff HEAD
  echo ""
elif git rev-parse --verify "origin/$CURRENT_BRANCH" >/dev/null 2>&1 && ! git diff --quiet "origin/$CURRENT_BRANCH" HEAD; then
  echo "### Unpushed Commits"
  git log --oneline "origin/$CURRENT_BRANCH"..HEAD
  echo ""
  git diff "origin/$CURRENT_BRANCH"..HEAD --stat
  echo ""
  git diff "origin/$CURRENT_BRANCH"..HEAD
  echo ""
else
  echo "No recent changes (everything committed and pushed)"
  echo ""
fi

# 2. Full PR context
echo "## Full PR Context (vs $BASE_BRANCH)"
echo ""
if git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  DIFF_BASE=$(git merge-base "$BASE_BRANCH" HEAD)
  echo "Diff base: $DIFF_BASE"
  echo ""

  echo "### Stats"
  git diff "$DIFF_BASE" --stat
  echo ""

  echo "### Change Type Classification"
  CHANGED_FILES=$(git diff "$DIFF_BASE" --name-only)
  if [ -z "$CHANGED_FILES" ]; then
    echo "No changes from $BASE_BRANCH"
    exit 0
  fi

  CODE_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(ts|tsx|js|jsx|mjs)$' || true)
  DOC_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(md|txt)$' || true)
  CONFIG_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(json|yaml|yml|toml|env)$' || true)
  SCRIPT_FILES=$(echo "$CHANGED_FILES" | grep -E '\.(sh|bash)$' || true)

  if [ -n "$CODE_FILES" ]; then echo "- Code files changed"; fi
  if [ -n "$DOC_FILES" ]; then echo "- Documentation files changed"; fi
  if [ -n "$CONFIG_FILES" ]; then echo "- Configuration files changed"; fi
  if [ -n "$SCRIPT_FILES" ]; then echo "- Script files changed"; fi
  echo ""

  echo "### Full PR Diff"
  git diff "$DIFF_BASE"
  echo ""
else
  echo "Base branch '$BASE_BRANCH' not found"
  exit 1
fi

# 3. Type Safety & Quality (for code changes in entire PR)
if [ -n "$CODE_FILES" ]; then
  echo "## Type Safety & Quality Checks (Entire PR)"
  echo ""

  echo "### Typecheck"
  if TYPECHECK_OUTPUT=$(pnpm typecheck 2>&1); then
    echo -e "${GREEN}✅ No type errors${NC}"
  else
    echo -e "${RED}⚠️  Type errors found:${NC}"
    echo "$TYPECHECK_OUTPUT"
  fi
  echo ""

  echo "### Code Quality Checks (in PR changes)"
  # TODO: Replace with proper ESLint once workspace config is fixed (see package.json _TODO)
  # Current implementation uses grep patterns as temporary solution
  for file in $CODE_FILES; do
    ANY_FOUND=""
    CONSOLE_FOUND=""

    if git diff "$DIFF_BASE" "$file" | grep -E "^\+.*:\s*any" >/dev/null 2>&1; then
      ANY_FOUND="yes"
    fi

    if git diff "$DIFF_BASE" "$file" | grep -E "^\+.*console\.log" >/dev/null 2>&1; then
      CONSOLE_FOUND="yes"
    fi

    if [ -n "$ANY_FOUND" ] || [ -n "$CONSOLE_FOUND" ]; then
      echo -e "${YELLOW}⚠️  Issues in: $file${NC}"
      if [ -n "$ANY_FOUND" ]; then
        echo "   - Uses 'any' type:"
        git diff "$DIFF_BASE" "$file" | grep -E "^\+.*:\s*any" || true
      fi
      if [ -n "$CONSOLE_FOUND" ]; then
        echo "   - Contains console.log:"
        git diff "$DIFF_BASE" "$file" | grep -E "^\+.*console\.log" || true
      fi
    fi
  done
  echo ""
fi

# 4. Style Guide Compliance
echo "## Style Guide Compliance"
echo ""
echo "Files to review against style guides (entire PR):"
echo "$CHANGED_FILES"
echo ""
echo "Relevant style guides:"
if [ -n "$CODE_FILES" ]; then
  echo "- CLAUDE.md and the relevant agent-docs/ files (working, code, and architecture rules)"
fi
if [ -n "$DOC_FILES" ]; then
  echo "- CLAUDE.md and the relevant agent-docs/ files (working and task-specific rules)"
fi
if [ -n "$SCRIPT_FILES" ]; then
  echo "- Shell scripts: error handling, defensive coding, clarity"
fi
echo "- Check for clarity, redundancy, and organization"
echo ""

echo "=== END QUALITY CHECKS REPORT ==="
