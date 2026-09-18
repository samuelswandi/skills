#!/usr/bin/env bash
# Regenerate the skills table in README.md from the skills on disk.
#
# Rewrites whatever sits between the <!-- skills:start --> and <!-- skills:end -->
# markers. Pass --check to verify the table is current without writing (used in CI).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/skills"
README="$REPO_ROOT/README.md"

START_MARKER='<!-- skills:start -->'
END_MARKER='<!-- skills:end -->'

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
  CHECK_ONLY=1
fi

if [ ! -f "$README" ]; then
  echo "error: no README.md at $README" >&2
  exit 1
fi

if ! grep -qF "$START_MARKER" "$README" || ! grep -qF "$END_MARKER" "$README"; then
  echo "error: README.md is missing the $START_MARKER / $END_MARKER markers" >&2
  exit 1
fi

frontmatter_value() {
  local file="$1" key="$2"
  awk -v key="$key" '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    {
      if (index($0, key ":") == 1) {
        value = substr($0, length(key) + 2)
        sub(/^[ \t]+/, "", value)
        sub(/[ \t]+$/, "", value)
        if (value ~ /^".*"$/) { value = substr(value, 2, length(value) - 2) }
        else if (value ~ /^\047.*\047$/) { value = substr(value, 2, length(value) - 2) }
        print value
        exit
      }
    }
  ' "$file"
}

# Build the table in a temp file. Passing multi-line text through `awk -v` does
# not work, so the replacement block is read from a file instead.
table_file="$(mktemp)"
new_readme="$(mktemp)"
trap 'rm -f "$table_file" "$new_readme"' EXIT

{
  printf '| Skill | Description |\n'
  printf '| ----- | ----------- |\n'
} > "$table_file"

while IFS= read -r skill_md; do
  skill_dir="$(dirname "$skill_md")"
  rel_dir="${skill_dir#"$REPO_ROOT"/}"
  name="$(frontmatter_value "$skill_md" name)"
  description="$(frontmatter_value "$skill_md" description)"
  [ -n "$name" ] || name="$(basename "$skill_dir")"
  # Escape pipes so a description does not break the table.
  description="${description//|/\\|}"
  printf '| [`%s`](%s/) | %s |\n' "$name" "$rel_dir" "$description" >> "$table_file"
done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 4 -name SKILL.md | sort)

awk -v start="$START_MARKER" -v end="$END_MARKER" -v tablefile="$table_file" '
  index($0, start) {
    print
    while ((getline line < tablefile) > 0) print line
    close(tablefile)
    skipping = 1
    next
  }
  index($0, end) { skipping = 0 }
  !skipping      { print }
' "$README" > "$new_readme"

# Never leave a truncated README behind: only replace it once awk succeeded and
# produced non-empty output that still contains both markers.
if [ ! -s "$new_readme" ]; then
  echo "error: generated README was empty; leaving $README untouched" >&2
  exit 1
fi
if ! grep -qF "$START_MARKER" "$new_readme" || ! grep -qF "$END_MARKER" "$new_readme"; then
  echo "error: generated README lost its markers; leaving $README untouched" >&2
  exit 1
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  if diff -q "$README" "$new_readme" >/dev/null; then
    echo "README skills table is up to date."
    exit 0
  fi
  echo "error: README skills table is stale. Run ./scripts/sync-readme.sh" >&2
  diff "$README" "$new_readme" || true
  exit 1
fi

cat "$new_readme" > "$README"
echo "Updated the skills table in README.md."
