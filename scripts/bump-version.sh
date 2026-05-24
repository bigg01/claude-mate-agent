#!/usr/bin/env bash
# Bump the project version everywhere it is declared.
#
# Usage:
#   scripts/bump-version.sh <new-version>      # set to exact version
#   scripts/bump-version.sh patch              # 1.2.3 → 1.2.4
#   scripts/bump-version.sh minor              # 1.2.3 → 1.3.0
#   scripts/bump-version.sh major              # 1.2.3 → 2.0.0
#   scripts/bump-version.sh --check            # print current version, exit 0
#
# The script keeps the following files in sync with the canonical VERSION file:
#   - VERSION
#   - container/pyproject.toml      [project] version
#   - charts/claude-mate-agent/Chart.yaml      version + appVersion
#   - charts/claude-mate-agent/values.yaml     image.tag
#
# It does NOT create a git tag or commit — that's the release workflow's job.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"

current=$(tr -d '[:space:]' < "$VERSION_FILE")

case "${1:-}" in
  ""|--help|-h)
    sed -n '2,/^set -/p' "$0" | sed -n 's/^# \?//p'
    exit 0
    ;;
  --check)
    echo "$current"
    exit 0
    ;;
esac

# Resolve target version
case "$1" in
  patch|minor|major)
    IFS=. read -r MA MI PA <<< "$current"
    case "$1" in
      patch) PA=$((PA + 1)) ;;
      minor) MI=$((MI + 1)); PA=0 ;;
      major) MA=$((MA + 1)); MI=0; PA=0 ;;
    esac
    new="${MA}.${MI}.${PA}"
    ;;
  *)
    # Accept full SemVer: MAJOR.MINOR.PATCH[-prerelease][+build]
    if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
      echo "ERROR: '$1' is not a valid SemVer 2.0.0 string" >&2
      echo "       Expected MAJOR.MINOR.PATCH[-prerelease][+build]" >&2
      exit 2
    fi
    new="$1"
    ;;
esac

echo "Bumping $current → $new"

# Update files using portable sed.
# macOS sed needs `-i ''` while GNU sed needs `-i`; detect and branch.
if sed --version >/dev/null 2>&1; then
  SED_INPLACE=(sed -i)
else
  SED_INPLACE=(sed -i '')
fi

echo "$new" > "$VERSION_FILE"

# pyproject.toml: version = "X.Y.Z" in the [project] table
"${SED_INPLACE[@]}" -E 's/^version = "[^"]+"/version = "'"$new"'"/' \
  "$ROOT/container/pyproject.toml"

# Chart.yaml: version + appVersion (appVersion is quoted)
"${SED_INPLACE[@]}" -E 's/^version: .*/version: '"$new"'/' \
  "$ROOT/charts/claude-mate-agent/Chart.yaml"
"${SED_INPLACE[@]}" -E 's/^appVersion: "[^"]+"/appVersion: "'"$new"'"/' \
  "$ROOT/charts/claude-mate-agent/Chart.yaml"

# values.yaml: image.tag
"${SED_INPLACE[@]}" -E 's/^(  tag): "[^"]+"/\1: "'"$new"'"/' \
  "$ROOT/charts/claude-mate-agent/values.yaml"

echo "OK. Updated:"
printf '  %s\n' \
  VERSION \
  container/pyproject.toml \
  charts/claude-mate-agent/Chart.yaml \
  charts/claude-mate-agent/values.yaml
echo ""
echo "Next steps:"
echo "  1. Review the diff:    git diff"
echo "  2. Commit:             git commit -am \"chore: release $new\""
echo "  3. Tag:                git tag -a v$new -m \"v$new\""
echo "  4. Push tag:           git push origin v$new"
