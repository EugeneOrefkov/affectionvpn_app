#!/usr/bin/env bash
# Cuts a release tag by computing the next version from the latest existing
# tag. The tag is the single source of truth: CI derives every packaged
# version (APK, deb, tarball, PKGBUILD, pubspec) from it.
#
# Usage:
#   scripts/release.sh            # next patch version (default)
#   scripts/release.sh minor      # bump minor
#   scripts/release.sh major      # bump major
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

bump="${1:-patch}"
case "$bump" in
  major|minor|patch) ;;
  *) echo "usage: $0 [major|minor|patch]" >&2; exit 1 ;;
esac

current="$(git fetch --tags -q && git tag --list 'v*' --sort=-v:refname | head -1)"
if [ -z "$current" ]; then
  echo "no v* tags found" >&2
  exit 1
fi
current="${current#v}"
IFS=. read -r maj min pat <<< "$current"
case "$bump" in
  major) maj=$((maj + 1)); min=0; pat=0 ;;
  minor) min=$((min + 1)); pat=0 ;;
  patch) pat=$((pat + 1)) ;;
esac
next="v$maj.$min.$pat"

branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || { echo "must be on main (now: $branch)" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree is dirty, commit first" >&2; exit 1; }
git pull --ff-only origin main >/dev/null

printf 'Cut release %s (previous: v%s)? [y/N] ' "$next" "$current"
read -r answer
[ "$answer" = "y" ] || { echo "aborted"; exit 1; }

git tag -a "$next" -m "release $next"
git push origin "$next"
echo "tag $next pushed. Watch the pipeline: https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]//;s/\.git$//')/actions"
