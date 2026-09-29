#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Called by build.sh for every non-Developer build made from this fork. Records
# where the build came from (checkout, branch, upstream release it is based on,
# commit) in the staged Info.plist, before signing. The app reads it and, instead
# of installing official releases that would drop the fork's own changes, offers
# to sync with upstream and rebuild. See README.md beside this script.
#
#   Tools/fork-maintenance/stamp-fork-source.sh <Info.plist>

set -euo pipefail
plist="$1"

root="$(git rev-parse --show-toplevel)"
branch="$(git rev-parse --abbrev-ref HEAD)"
commit="$(git rev-parse --short HEAD)"
[[ -n "$(git status --porcelain)" ]] && commit="$commit-dirty"
# Why --exclude: beta and rc tags are not release bases.
base="$(git describe --tags --abbrev=0 --match 'v*' --exclude '*-*' HEAD 2>/dev/null || true)"

# plutil takes each value as given; PlistBuddy parses it and silently drops a
# quote or backslash in a path, leaving a build that looks official.
plutil -remove VorssaintForkSource "$plist" 2>/dev/null || true
plutil -insert VorssaintForkSource -dictionary "$plist"
plutil -insert VorssaintForkSource.Checkout -string "$root" "$plist"
plutil -insert VorssaintForkSource.Branch -string "$branch" "$plist"
plutil -insert VorssaintForkSource.Commit -string "$commit" "$plist"
if [[ -n "$base" ]]; then
    plutil -insert VorssaintForkSource.BaseTag -string "$base" "$plist"
else
    echo "  ⚠ no upstream release tag below HEAD; the app cannot offer upstream syncs" >&2
fi

# Read it back: an unstamped fork build would let the official updater replace it.
if [[ "$(plutil -extract VorssaintForkSource.Checkout raw -o - "$plist")" != "$root" ]]; then
    echo "✗ the fork stamp did not reach $plist" >&2
    exit 1
fi
echo "  stamped fork build: $branch @ $commit on ${base:-no release tag}"
