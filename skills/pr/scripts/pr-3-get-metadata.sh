#!/bin/bash
# Phase 3: Get PR metadata (reviewer assignment and available labels)
# Assigns reviewers: top git contributor, or least-loaded collaborator as fallback.
# Uses GitHub commits API for author→login mapping (no fuzzy matching).
# Uses repo collaborators API for team roster (no hardcoded list).
# Usage: ./pr-3-get-metadata.sh [base-branch]
# Default base branch: origin/master, because local master is often stale

set -euo pipefail

command -v git >/dev/null || { echo "Error: git not found"; exit 1; }
command -v gh >/dev/null || { echo "Error: gh CLI not found. Install from https://cli.github.com/"; exit 1; }

echo "=== PR METADATA ANALYSIS ==="
echo ""

# === PART 1: REVIEWER ASSIGNMENT ===

echo "## Reviewer Assignment"
echo ""

BASE_BRANCH="${1:-origin/master}"
SUGGESTED_REVIEWER=""
GITHUB_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
REPO_NAME=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || echo "")

git fetch origin +refs/heads/master:refs/remotes/origin/master --quiet 2>/dev/null || true

# Accounts that should never be auto-suggested as reviewers
# (bots + former teammates still listed as collaborators).
EXCLUDED_REVIEWERS=("bex-novo" "eminentgu")
is_excluded_reviewer() {
  local candidate="$1"
  for blocked in "${EXCLUDED_REVIEWERS[@]}"; do
    [ "$candidate" = "$blocked" ] && return 0
  done
  return 1
}

if [ -z "$GITHUB_USER" ]; then
  echo "⚠️  Unable to determine current GitHub username (run: gh auth status)"
  exit 1
fi

echo "Current GitHub user: @$GITHUB_USER"
echo ""

# Bot-mode override: if PR_BOT_REVIEWER is set, use it verbatim as the
# suggested reviewer and skip the git-history / collaborators queries entirely.
# Human runs (no env var) are unaffected — they fall through to the standard
# picker below.
if [ -n "${PR_BOT_REVIEWER:-}" ]; then
  echo "✅ Suggested reviewer: @$PR_BOT_REVIEWER (bot override via PR_BOT_REVIEWER)"
  echo ""
  # Skip the rest of Part 1; still emit Parts 2+3 (fix-branch detection,
  # available labels) since /pr Phase 4 relies on the label list.
  BOT_REVIEWER_SET=1
else
  BOT_REVIEWER_SET=0
fi

# Fetch current repo collaborators (used to filter out departed teammates)
COLLABORATORS=$(gh api "repos/$REPO_NAME/collaborators" --jq '.[].login' 2>/dev/null || echo "")

# Skip the reviewer-picking work entirely when the bot override is set.
if [ "$BOT_REVIEWER_SET" = "0" ]; then
  # Get changed files
  CHANGED_FILES=""
  if git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
    DIFF_BASE=$(git merge-base "$BASE_BRANCH" HEAD)
    CHANGED_FILES=$(git diff "$DIFF_BASE" --name-only)
  fi

  if [ -z "$CHANGED_FILES" ]; then
    echo "No changes found vs $BASE_BRANCH"
    echo ""
  else
    # Use GitHub commits API to find recent contributors with resolved logins.
    # The API returns .author.login directly — no email-to-username mapping needed.
    SINCE=$(date -d '3 months ago' -I 2>/dev/null || date -v-3m +%Y-%m-%d)
    CANDIDATES_FILE=$(mktemp)
    trap 'rm -f "$CANDIDATES_FILE"' EXIT

    echo "Analyzing recent contributors via GitHub API..."
    echo ""

    while IFS= read -r file; do
      [ -f "$file" ] || continue
      # Get commits for this file, extract author login (skip null/bot authors)
      gh api "repos/$REPO_NAME/commits?path=$file&since=${SINCE}T00:00:00Z&per_page=100" \
        --jq '.[].author.login // empty' 2>/dev/null >> "$CANDIDATES_FILE" || true
    done <<< "$CHANGED_FILES"

    # Count by login, exclude self + bots, filter to current collaborators, pick top contributor
    if [ -s "$CANDIDATES_FILE" ]; then
      SUGGESTED_REVIEWER=$(sort "$CANDIDATES_FILE" | grep -vx "$GITHUB_USER" | uniq -c | sort -rn | awk '{print $2}' | while read -r user; do
        is_excluded_reviewer "$user" && continue
        echo "$COLLABORATORS" | grep -qx "$user" && echo "$user" && break
      done)
    fi

    if [ -n "$SUGGESTED_REVIEWER" ]; then
      echo "✅ Suggested reviewer: @$SUGGESTED_REVIEWER (top contributor to changed files)"
    fi

    # Fallback: no git history contributors — use repo collaborators
    if [ -z "$SUGGESTED_REVIEWER" ]; then
      echo "No recent contributors found. Falling back to repo collaborators..."
      echo ""

      BEST_CANDIDATE=""
      MIN_LOAD=999999

      for username in $COLLABORATORS; do
        [ "$username" = "$GITHUB_USER" ] && continue
        is_excluded_reviewer "$username" && continue
        review_count=$(gh pr list --search "review-requested:$username is:open" --json number --jq '. | length' 2>/dev/null || echo "0")
        printf "  @%-15s - %d open reviews\n" "$username" "$review_count"

        if [ "$review_count" -lt "$MIN_LOAD" ]; then
          MIN_LOAD=$review_count
          BEST_CANDIDATE=$username
        fi
      done

      echo ""
      if [ -n "$BEST_CANDIDATE" ]; then
        SUGGESTED_REVIEWER=$BEST_CANDIDATE
        echo "✅ Suggested reviewer: @$SUGGESTED_REVIEWER (lowest review load)"
      fi
    fi
  fi

  echo ""
fi

# === PART 2: FIX BRANCH DETECTION ===

CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" =~ /fix/ ]]; then
  cat <<'EOF'

⚠️  FIX BRANCH DETECTED

This appears to be a bug fix. Consider if this needs to be cherry-picked:
- Does this fix a production issue?
- Should this be deployed ASAP before the next regular release?
- If YES → Add the 'cherrypick' label when creating the PR

EOF
fi

# === PART 3: AVAILABLE LABELS ===

echo "## Available GitHub Labels"
echo ""

if [ -n "$REPO_NAME" ] && gh api "repos/$REPO_NAME/labels" --jq '.[].name' 2>/dev/null; then
  cat <<'EOF'

Label Selection Guidance:

Primary label (pick ONE):
- Domain/project labels: april-*, catalina-re, tokio-marine, codex, etc.
- Use 'eng' as fallback for general engineering changes

Optional additional labels:

ci:skip - Skip CI workflows (use ONLY when changes cannot break CI):
  ✅ Safe: Documentation, CLAUDE.md, .cursor/rules/*, .claude/commands/*,
          .vscode/settings.json, .gitignore, pure CSS, whitespace-only
  ❌ NOT safe: Any production code, shared packages, configs (package.json,
          tsconfig, etc.), database, API routes, Docker, Terraform, tests
  → When in doubt, do NOT use ci:skip

cherrypick - Deploy to production ASAP (before next regular release)
  Use for: Critical bug fixes, security patches, urgent production issues
  This PR will be cherry-picked and deployed outside the normal release cycle

Use affected-test detection rather than guessing:
  pnpm --filter @agmi/unified exec tsx scripts/ci/run-affected-tests.ts --dry-run --markdown

Use detected `ci:*` labels from the JSON output, and apply only labels that exist in the GitHub label list above:
  pnpm --filter @agmi/unified exec tsx scripts/ci/run-affected-tests.ts --dry-run --json

EOF
else
  echo "⚠️  Unable to fetch labels from GitHub. Check gh CLI authentication."
fi
echo ""

echo "=== END PR METADATA ANALYSIS ==="
