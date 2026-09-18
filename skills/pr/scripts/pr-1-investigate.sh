#!/bin/bash
# Phase 1: Investigation script for PR workflow
# Gathers all git state and PR context in one pass
# Usage: ./pr-1-investigate.sh [pr-url]

set -euo pipefail

# Disable git pager to prevent opening vi/less
export GIT_PAGER=cat

# Color codes for better readability
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

PR_URL="${1:-}"

# =============================================================================
# PREREQUISITES - Hard-stop checks that must pass before workflow can proceed
# =============================================================================
echo "=== PREREQUISITES CHECK ==="
echo ""
PREREQ_FAILED=0

# 1. Git installed
if ! command -v git >/dev/null; then
  echo -e "${RED}❌ FAILED: git not found${NC}"
  echo "   Install git and try again"
  PREREQ_FAILED=1
else
  echo -e "${GREEN}✓ git installed${NC}"
fi

# 2. In a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo -e "${RED}❌ FAILED: Not in a git repository${NC}"
  echo "   Run this command from within a git repository"
  PREREQ_FAILED=1
else
  echo -e "${GREEN}✓ In git repository${NC}"
fi

# 3. gh CLI installed
if ! command -v gh >/dev/null; then
  echo -e "${RED}❌ FAILED: gh CLI not found${NC}"
  echo ""
  echo "   The /pr workflow requires the GitHub CLI to:"
  echo "   - Check if a PR already exists for your branch"
  echo "   - Create and update pull requests"
  echo "   - Get reviewers, labels, and PR metadata"
  echo ""
  echo "   Install from: https://cli.github.com/"
  echo "   Then run: gh auth login"
  echo "   Then run /pr again"
  PREREQ_FAILED=1
else
  echo -e "${GREEN}✓ gh CLI installed${NC}"

  # 4. gh authenticated (only check if gh is installed)
  if ! gh auth status >/dev/null 2>&1; then
    echo -e "${RED}❌ FAILED: gh CLI not authenticated${NC}"
    echo ""
    echo "   Run: gh auth login"
    echo "   Then run /pr again"
    PREREQ_FAILED=1
  else
    echo -e "${GREEN}✓ gh CLI authenticated${NC}"
  fi
fi

# 5. Not in detached HEAD state
if ! git symbolic-ref HEAD >/dev/null 2>&1; then
  echo -e "${RED}❌ FAILED: Detached HEAD state${NC}"
  echo "   You're not on a branch. Create or checkout a branch first:"
  echo "   git checkout -b <branch-name>"
  PREREQ_FAILED=1
else
  echo -e "${GREEN}✓ On a branch (not detached HEAD)${NC}"
fi

# 6. No unresolved merge conflicts
CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
if [ -n "$CONFLICTS" ]; then
  echo -e "${RED}❌ FAILED: Unresolved merge conflicts${NC}"
  echo "   Files with conflicts:"
  echo "$CONFLICTS" | sed 's/^/   - /'
  echo "   Resolve conflicts first, then run /pr again"
  PREREQ_FAILED=1
else
  echo -e "${GREEN}✓ No merge conflicts${NC}"
fi

echo ""

# Exit if any prerequisite failed
if [ "$PREREQ_FAILED" -eq 1 ]; then
  echo -e "${RED}=== PREREQUISITES FAILED ===${NC}"
  echo ""
  echo "Fix the issues above, then run /pr again."
  echo "DO NOT proceed with the PR workflow until all prerequisites pass."
  exit 1
fi

echo -e "${GREEN}=== ALL PREREQUISITES PASSED ===${NC}"
echo ""

# =============================================================================
# INVESTIGATION REPORT - Gather context for PR workflow
# =============================================================================

# Function to display PR context (eliminates duplication)
show_pr_context() {
  local pr_identifier="$1"
  local pr_label="$2"

  echo "## $pr_label"
  if ! gh pr view "$pr_identifier" --json state,title,body,headRefName,files 2>/dev/null; then
    echo "Unable to fetch PR details for: $pr_identifier"
    return 1
  fi
  echo ""

  echo "PR Checks Status:"
  gh pr checks "$pr_identifier" 2>/dev/null || echo "No checks found or checks unavailable"
  echo ""

  echo "PR Review Status:"
  gh pr view "$pr_identifier" --json reviewDecision,reviews
  echo ""

  echo "PR Labels:"
  gh pr view "$pr_identifier" --json labels --jq '.labels | map(.name) | join(", ")' || echo "No labels"
  echo ""
}

echo "=== PHASE 0 INVESTIGATION REPORT ==="
echo ""

# 1. Current branch
echo "## Current Branch"
CURRENT_BRANCH=$(git branch --show-current)
echo "$CURRENT_BRANCH"

# Safety check for protected branches
if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "production" ]]; then
  echo ""
  echo -e "${RED}⚠️  WARNING: You are on a protected branch ($CURRENT_BRANCH)${NC}"
  echo -e "${RED}⚠️  NEVER push directly to master or production (see CLAUDE.md Critical Restrictions)${NC}"
  echo -e "${RED}⚠️  Create a feature branch instead: git checkout -b <name>/feature/<description>${NC}"
fi
echo ""

# Git user (for branch naming)
echo "## Git User"
git config user.name || echo "Not configured"
echo ""

# 2. Branch freshness check (is branch up to date with origin/master?)
echo "## Branch Freshness"
# Fetch origin/master AND update local master ref (keeps worktrees in sync for Vibe Kanban diffs)
git fetch origin master:master --quiet 2>/dev/null || true

if [[ "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "production" ]]; then
  BEHIND=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
  if [ "$BEHIND" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  LOCAL $CURRENT_BRANCH IS STALE: $BEHIND commit(s) behind origin/master${NC}"
    echo "Run: git rebase origin/master"
  else
    echo "✓ Up to date with origin/master"
  fi
else
  BEHIND=$(git rev-list --count HEAD..origin/master 2>/dev/null || echo "0")
  if [ "$BEHIND" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  BRANCH IS STALE: $BEHIND commit(s) behind origin/master${NC}"
    echo ""
    echo "Recent master commits not in your branch:"
    git log --oneline HEAD..origin/master | head -5
    if [ "$BEHIND" -gt 5 ]; then
      echo "  ... and $((BEHIND - 5)) more"
    fi
    echo ""
    echo "Recommendation: Rebase before opening PR"
  else
    echo "✓ Branch is up to date with origin/master"
  fi
fi
echo ""

# 3. Remote tracking status
echo "## Remote Tracking Status"
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u})
  AHEAD=$(git rev-list --count "$UPSTREAM"..HEAD)
  BEHIND=$(git rev-list --count HEAD.."$UPSTREAM")
  echo "Tracking: $UPSTREAM"
  echo "Ahead: $AHEAD commits | Behind: $BEHIND commits"
else
  echo "No remote tracking branch set"
fi
echo ""

# 4. Git status
echo "## Git Status"
git status
echo ""

# 5. Branch commits (vs master)
echo "## Branch Commits (vs master)"
if [[ "$CURRENT_BRANCH" != "master" ]] && git rev-parse --verify master >/dev/null 2>&1; then
  BRANCH_COMMITS=$(git log master..HEAD --oneline | wc -l | tr -d ' ')
  if [ "$BRANCH_COMMITS" -eq 0 ]; then
    echo "No commits on this branch (same as master)"
  else
    echo "$BRANCH_COMMITS commit(s) on this branch:"
    git log master..HEAD --oneline
  fi
else
  echo "N/A (on master or master not found)"
fi
echo ""

# 6. Stash list
echo "## Stash List"
STASH_COUNT=$(git stash list | wc -l | tr -d ' ')
if [ "$STASH_COUNT" -eq 0 ]; then
  echo "No stashed changes"
elif [ "$STASH_COUNT" -le 5 ]; then
  echo "$STASH_COUNT stashed change(s):"
  git stash list
else
  echo "$STASH_COUNT stashed changes (showing most recent 5):"
  git stash list | awk 'NR <= 5'
fi
echo ""

# 7. Recent commits
echo "## Recent Commits"
git log --oneline -5
echo ""

# 8. Base branch comparison
echo "## Base Branch Comparison (master)"
if git rev-parse --verify master >/dev/null 2>&1; then
  AHEAD_BEHIND=$(git rev-list --left-right --count master...HEAD)
  echo "Commits behind master | Commits ahead of master"
  echo "$AHEAD_BEHIND"
  echo ""
  echo "Changed files summary:"
  git diff --stat master...HEAD
else
  echo "master branch not found locally"
fi
echo ""

# 9. Merge conflicts check (already verified in prerequisites, but show for completeness)
echo "## Merge Conflicts"
echo "✓ No merge conflicts"
echo ""

# 10. PR context for current branch
if gh pr list --head "$CURRENT_BRANCH" --json number,title,state,url 2>/dev/null | grep -q "number"; then
  echo "Found PR for current branch:"
  gh pr list --head "$CURRENT_BRANCH" --json number,title,state,url
  echo ""
  PR_NUMBER=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number')
  if [ -n "$PR_NUMBER" ]; then
    show_pr_context "$PR_NUMBER" "PR Details"
  fi
else
  echo "## PR Context for Current Branch"
  echo "No PR found for current branch"
  echo ""
fi

# 11. PR context from provided URL (if given)
if [ -n "$PR_URL" ]; then
  echo "URL: $PR_URL"
  show_pr_context "$PR_URL" "PR Context from Provided URL"
fi

# 12. Uncommitted changes overview
echo "## Uncommitted Changes"
if git diff --quiet && git diff --cached --quiet; then
  echo "No uncommitted changes"
else
  echo "Staged changes:"
  git diff --cached --name-status || echo "None"
  echo ""
  echo "Unstaged changes:"
  git diff --name-status || echo "None"
  echo ""
  echo "Untracked files:"
  git ls-files --others --exclude-standard || echo "None"
fi
echo ""

echo "=== END INVESTIGATION REPORT ==="
