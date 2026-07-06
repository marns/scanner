#!/bin/sh
# Registers the git clean filters this repo relies on. Filters live in
# .git/config (per-clone, never committed), so every fresh clone must run this
# once. Safe to re-run; it just rewrites the same config values.
#
#   ./scripts/setup-git-filters.sh
#
# strip-team: blanks DEVELOPMENT_TEAM in project.pbxproj on staging so an Apple
# Developer team ID is never committed to this public fork. The value stays in
# your working tree (Xcode automatic signing keeps working); git only sees "".
set -eu

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

git config filter.strip-team.clean \
  "sed -E 's/DEVELOPMENT_TEAM = [A-Za-z0-9]+;/DEVELOPMENT_TEAM = \"\";/'"
git config filter.strip-team.smudge cat
git config filter.strip-team.required true

echo "Registered git clean filter 'strip-team'."
echo "DEVELOPMENT_TEAM will be blanked in commits; your working copy is untouched."

# Re-normalize the already-tracked project file so the filter takes effect now
# without waiting for the next Xcode re-stamp.
git add --renormalize StrayScanner.xcodeproj/project.pbxproj 2>/dev/null || true
