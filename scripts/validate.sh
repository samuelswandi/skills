#!/usr/bin/env bash
# Validate every skill in skills/ before publishing.
#
# Checks each SKILL.md for the frontmatter the Agent Skills spec requires, that
# the declared name matches its directory, and that no obvious private data
# leaked in. Exits non-zero on the first category of failure so CI fails loudly.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"

RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
GREEN=$'\033[0;32m'
NC=$'\033[0m'

errors=0
warnings=0

fail() {
  echo "${RED}FAIL${NC} $1"
  errors=$((errors + 1))
}

warn() {
  echo "${YELLOW}WARN${NC} $1"
  warnings=$((warnings + 1))
}

ok() {
  echo "${GREEN}ok${NC}   $1"
}

if [ ! -d "$SKILLS_DIR" ]; then
  fail "no skills/ directory at $SKILLS_DIR"
  exit 1
fi

# Read one key out of the YAML frontmatter block. Handles plain and quoted
# scalars on a single line, which is all the spec requires for name and
# description.
frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    {
      # match "key:" at the start of a line, not nested under another key
      if (index($0, key ":") == 1) {
        value = substr($0, length(key) + 2)
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
        # strip a single layer of matching quotes
        if (value ~ /^".*"$/ || value ~ /^'"'"'.*'"'"'$/) {
          value = substr(value, 2, length(value) - 2)
        }
        print value
        exit
      }
    }
  ' "$file"
}

echo "=== Validating skills in $SKILLS_DIR ==="
echo ""

skill_count=0

# Find SKILL.md up to three levels deep, matching the CLI's discovery depth.
while IFS= read -r skill_md; do
  skill_count=$((skill_count + 1))
  skill_dir="$(dirname "$skill_md")"
  rel="${skill_md#"$REPO_ROOT"/}"
  dir_name="$(basename "$skill_dir")"

  # 1. Frontmatter must open on line 1.
  if [ "$(head -1 "$skill_md")" != "---" ]; then
    fail "$rel: missing YAML frontmatter (line 1 must be '---')"
    continue
  fi

  # 2. Required fields.
  name="$(frontmatter_value "$skill_md" name)"
  description="$(frontmatter_value "$skill_md" description)"

  if [ -z "$name" ]; then
    fail "$rel: frontmatter is missing 'name'"
  elif [ "$name" != "$dir_name" ]; then
    fail "$rel: name '$name' does not match directory '$dir_name'"
  elif ! printf '%s' "$name" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
    fail "$rel: name '$name' should be lowercase with hyphens only"
  fi

  if [ -z "$description" ]; then
    fail "$rel: frontmatter is missing 'description'"
  elif [ "${#description}" -lt 20 ]; then
    warn "$rel: description is only ${#description} chars; agents match on this, so say when to use the skill"
  fi

  # 3. Body must contain something beyond the frontmatter.
  body_lines="$(awk 'NR>1 && $0=="---" {found=NR; exit} END {print found+0}' "$skill_md")"
  total_lines="$(wc -l < "$skill_md" | tr -d ' ')"
  if [ "$body_lines" -gt 0 ] && [ "$((total_lines - body_lines))" -lt 3 ]; then
    warn "$rel: body is nearly empty"
  fi

  # 4. Private data that must not be published.
  if grep -nE '/(Users|home)/[a-zA-Z0-9._-]+/' "$skill_md" >/dev/null 2>&1; then
    fail "$rel: contains a hardcoded home directory path"
    grep -nE '/(Users|home)/[a-zA-Z0-9._-]+/' "$skill_md" | sed 's/^/       /'
  fi

  if [ -z "$name" ] || [ -z "$description" ]; then
    continue
  fi
  ok "$rel ($name)"
done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 4 -name SKILL.md | sort)

echo ""

if [ "$skill_count" -eq 0 ]; then
  fail "no SKILL.md files found under skills/"
fi

# Repo-wide secret scan across every tracked file under skills/.
echo "=== Scanning for secrets and private paths ==="
secret_hits=0

scan() {
  local label="$1" pattern="$2"
  local hits
  hits="$(grep -rInE "$pattern" "$SKILLS_DIR" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    fail "possible $label:"
    printf '%s\n' "$hits" | sed 's/^/       /'
    secret_hits=$((secret_hits + 1))
  fi
}

scan "private key" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
scan "AWS access key" 'AKIA[0-9A-Z]{16}'
scan "GitHub token" 'gh[pousr]_[A-Za-z0-9]{16,}'
scan "Slack token" 'xox[abprs]-[A-Za-z0-9-]{10,}'
scan "hardcoded credential" '(api[_-]?key|secret|password|passwd|access[_-]?token)[[:space:]]*[=:][[:space:]]*["'"'"'][^"'"'"'{}$<]{8,}["'"'"']'
scan "home directory path" '/(Users|home)/[a-zA-Z0-9._-]+/'

if [ "$secret_hits" -eq 0 ]; then
  ok "no secrets or private paths found"
fi

# The Claude Code plugin manifest lists skill paths explicitly, so it silently
# goes stale when a skill is added or renamed. Compare it against disk.
MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"
if [ -f "$MANIFEST" ]; then
  echo ""
  echo "=== Checking .claude-plugin/marketplace.json ==="

  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST" 2>/dev/null; then
    fail ".claude-plugin/marketplace.json is not valid JSON"
  else
    on_disk="$(
      find "$SKILLS_DIR" -mindepth 2 -maxdepth 4 -name SKILL.md \
        | sed "s|^$REPO_ROOT/|./|; s|/SKILL.md$||" | sort
    )"
    declared="$(
      python3 -c '
import json, sys
manifest = json.load(open(sys.argv[1]))
paths = set()
for plugin in manifest.get("plugins", []):
    for skill in plugin.get("skills", []) or []:
        paths.add(skill.rstrip("/"))
print("\n".join(sorted(paths)))
' "$MANIFEST"
    )"

    if [ "$on_disk" = "$declared" ]; then
      ok "manifest skill list matches skills/ on disk"
    else
      fail "manifest skill list is out of sync with skills/ on disk"
      diff <(printf '%s\n' "$declared") <(printf '%s\n' "$on_disk") \
        | sed 's/^/       /' || true
      echo "       (< declared in manifest, > present on disk)"
    fi
  fi
fi

echo ""
echo "=== Summary ==="
echo "skills checked: $skill_count"
echo "errors:         $errors"
echo "warnings:       $warnings"

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "${RED}Validation failed.${NC} Fix the errors above before publishing."
  exit 1
fi

echo ""
echo "${GREEN}Validation passed.${NC}"
