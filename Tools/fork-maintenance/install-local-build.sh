#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# The install half of the app's "Sync & update". Started detached by the running
# fork build once sync-upstream.py has built the new version: waits for the app
# to quit, installs through build.sh (which signs the installed copy again, so
# macOS keeps the app's permissions), records the outcome and reopens the app.
#
#   install-local-build.sh <checkout> <app pid> <result.json> <log>
#
# VORSSAINT_INSTALLED_APP overrides where build.sh installs, for tests only.

set -uo pipefail
checkout="$1"
pid="$2"
result="$3"
log="$4"
app="${VORSSAINT_INSTALLED_APP:-/Applications/Vorssaint.app}"
previous="${result:h}/Vorssaint-previous.app"

mkdir -p "${result:h}" "${log:h}"
exec >>"$log" 2>&1
echo "\n[install-local-build] $(date '+%Y-%m-%d %H:%M:%S') installing from $checkout"
# Appended: the app's own PATH keeps the system tools first.
export PATH="$PATH:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"

# build.sh would stop the app itself, but a clean quit first lets it save state.
for _ in {1..300}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done

# build.sh --install deletes the installed app before copying the new one; keep
# it aside so a failed build or signature still leaves an app to reopen.
rm -rf "$previous"
[[ -d "$app" ]] && mv "$app" "$previous"

outcome=failed  # not "status": zsh reserves that name
if cd "$checkout" && ./build.sh --install; then
    outcome=installed
    rm -rf "$previous"
elif [[ -d "$previous" ]]; then
    rm -rf "$app"
    mv "$previous" "$app"
    echo "[install-local-build] restored the previous app"
fi

commit="$(git -C "$checkout" rev-parse --short HEAD 2>/dev/null || echo unknown)"
base="$(git -C "$checkout" describe --tags --abbrev=0 --match 'v*' --exclude '*-*' HEAD 2>/dev/null || echo '')"
/usr/bin/python3 -c 'import json, sys; print(json.dumps(dict(zip(("status", "commit", "baseTag", "log"), sys.argv[1:]))))' \
    "$outcome" "$commit" "$base" "$log" > "$result"
echo "[install-local-build] $outcome"

open -a "$app"
