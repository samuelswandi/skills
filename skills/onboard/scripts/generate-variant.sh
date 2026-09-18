#!/usr/bin/env bash
# Generate an onboard-<org> skill from templates/variant.md.
#
# Usage: scripts/generate-variant.sh <org-slug> [--project] [--force]
#
#   <org-slug>   lowercase, hyphenated org name, e.g. "acme" or "acme-corp"
#   --project    write to ./.claude/skills/ instead of ~/.claude/skills/
#   --force      overwrite an existing variant
#
# The generated SKILL.md still contains <!-- FILL: ... --> placeholders. The
# agent that runs this script is responsible for replacing every one of them
# with the org's real systems before reporting success.

set -euo pipefail

SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SKILL_ROOT/templates/variant.md"

ORG_SLUG=""
SCOPE="global"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project) SCOPE="project" ;;
    --global)  SCOPE="global" ;;
    --force)   FORCE=1 ;;
    -h|--help)
      sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "error: unknown option '$1'" >&2
      exit 2
      ;;
    *)
      if [ -n "$ORG_SLUG" ]; then
        echo "error: unexpected argument '$1' (org slug already set to '$ORG_SLUG')" >&2
        exit 2
      fi
      ORG_SLUG="$1"
      ;;
  esac
  shift
done

if [ -z "$ORG_SLUG" ]; then
  echo "error: missing <org-slug>" >&2
  echo "usage: scripts/generate-variant.sh <org-slug> [--project] [--force]" >&2
  exit 2
fi

# The slug becomes a skill name, which the Agent Skills spec requires to be
# lowercase with hyphens. Reject anything else rather than emitting a skill that
# fails validation downstream.
if ! printf '%s' "$ORG_SLUG" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*$'; then
  echo "error: org slug '$ORG_SLUG' must be lowercase letters, digits, and hyphens" >&2
  echo "       e.g. 'acme', 'acme-corp'" >&2
  exit 2
fi

if [ ! -f "$TEMPLATE" ]; then
  echo "error: template not found at $TEMPLATE" >&2
  exit 1
fi

SKILL_NAME="onboard-$ORG_SLUG"

if [ "$SCOPE" = "project" ]; then
  DEST_DIR="$PWD/.claude/skills/$SKILL_NAME"
else
  DEST_DIR="$HOME/.claude/skills/$SKILL_NAME"
fi
DEST="$DEST_DIR/SKILL.md"

if [ -e "$DEST" ] && [ "$FORCE" -ne 1 ]; then
  echo "error: $DEST already exists" >&2
  echo "       use --force to overwrite, or use the existing variant instead" >&2
  exit 1
fi

# ORG_NAME is a display name derived from the slug: "acme-corp" -> "Acme Corp".
# The agent should refine it if the org capitalizes differently (e.g. "StraitsX").
ORG_NAME="$(
  printf '%s' "$ORG_SLUG" | awk -F'-' '{
    for (i = 1; i <= NF; i++) {
      $i = toupper(substr($i, 1, 1)) substr($i, 2)
    }
    print
  }' OFS=' '
)"

mkdir -p "$DEST_DIR"

# Substitute via awk rather than sed -i, which is not portable between GNU and
# BSD. Write to a temp file and move into place so a failure cannot leave a
# half-written skill behind.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

awk -v slug="$ORG_SLUG" -v name="$ORG_NAME" '
  { gsub(/ORG_SLUG/, slug); gsub(/ORG_NAME/, name); print }
' "$TEMPLATE" > "$tmp"

if [ ! -s "$tmp" ]; then
  echo "error: generated an empty skill; leaving $DEST untouched" >&2
  exit 1
fi

mv "$tmp" "$DEST"
trap - EXIT

remaining="$(grep -c 'FILL:' "$DEST" || true)"

echo "Created $SKILL_NAME"
echo "  path:         $DEST"
echo "  scope:        $SCOPE"
echo "  display name: $ORG_NAME"
echo ""
echo "$remaining FILL placeholder(s) remain. Replace every one with this org's real"
echo "systems, repositories, and conventions before telling the user it is ready."
