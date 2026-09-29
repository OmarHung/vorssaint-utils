#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Exercises the fork-maintenance scripts against throwaway repositories, with no
# network and stubs for build.sh and open:
#   sync-upstream.py     clean rebase with push and build, tag signatures, conflict
#                        (aborted, branch unchanged), replayed resolution, verify-only
#                        rerun, a tag moved upstream, worktree delegation, a dirty
#                        checkout, a concurrent sync, Cancel, bad tags
#   stamp-fork-source.sh a checkout path with quotes and spaces, no release tag
#   install-local-build.sh  install, and a failed install that restores the old app
#
#   Tools/fork-maintenance/test-sync-upstream.sh

set -uo pipefail
HERE="${0:A:h}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
check() {
    if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; failures=$((failures + 1)); fi
}
git_q() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c tag.gpgsign=false "$@" >/dev/null 2>&1; }
events() { grep -o 'VORSSAINT_SYNC_EVENT .*' "$1" | sed 's/VORSSAINT_SYNC_EVENT //'; }
json_field() { /usr/bin/python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"; }

ssh-keygen -q -t ed25519 -N '' -C test -f "$WORK/key"
signed_tag() { git_q -c gpg.format=ssh -c user.signingkey="$WORK/key" tag -s -m "$1" "$1"; }

# upstream: v1.0.0 -> v1.1.0 (other file) -> v1.2.0 (same line the fork edits) -> v1.3.0,
# all signed; v1.4.0 unsigned
UP="$WORK/upstream"; mkdir -p "$UP" && cd "$UP" && git_q init -b main
printf 'shared line\n' > shared.txt; printf 'a\n' > other.txt
cat > build.sh <<'EOF'
#!/bin/zsh
echo "build.sh $*" >> "${0:A:h}/../build-calls.log"
[[ -n "${SLOW_TEST:-}" && "${1:-}" == --test ]] && sleep 20
exit 0
EOF
chmod +x build.sh
git_q add -A && git_q commit -m base && signed_tag v1.0.0
printf 'b\n' >> other.txt && git_q commit -am "upstream: other" && signed_tag v1.1.0
git_q tag v1.1.1-beta.1
printf 'upstream line\n' > shared.txt && git_q commit -am "upstream: shared" && signed_tag v1.2.0
printf 'c\n' >> other.txt && git_q commit -am "upstream: more" && signed_tag v1.3.0
printf 'd\n' >> other.txt && git_q commit -am "upstream: unsigned" && git_q tag -a -m v1.4.0 v1.4.0
git init -q --bare "$WORK/fork.git"

# the fork: omar/custom = v1.0.0 + the scripts and signers + an edit of the shared line
F="$WORK/fork"; git clone -q "$UP" "$F" 2>/dev/null && cd "$F"
git remote rename origin upstream && git remote add origin "$WORK/fork.git"
git_q config rerere.enabled true && git_q config rerere.autoUpdate true
git_q switch -c omar/custom v1.0.0
mkdir -p Tools/fork-maintenance && cp "$HERE/sync-upstream.py" Tools/fork-maintenance/
echo "t@t namespaces=\"git\" $(cat "$WORK/key.pub")" > Tools/fork-maintenance/upstream-allowed-signers
git_q add -A && git_q commit -m "fork: sync script"
printf 'fork line\n' > shared.txt && git_q commit -am "fork: shared"
# The interpreter the app runs it with, not whichever python3 is first on PATH.
sync() { /usr/bin/python3 -u Tools/fork-maintenance/sync-upstream.py "$@" --events --log "$WORK/log.txt"; }

echo "clean rebase, push and build"
: > "$WORK/log.txt"; sync v1.1.0 --push --build; code=$?
check "exits 0" '[[ $code == 0 ]]'
check "reports every stage, then done" \
    '[[ "$(events "$WORK/log.txt" | sed -E "s/.*\"(stage|type)\": \"([a-z]+)\".*/\2/" | tr "\n" " ")" == "fetch rebase verify push build done " ]]'
check "verifies the tag signature" 'grep -q "Good \"git\" signature for t@t" "$WORK/log.txt"'
check "is based on v1.1.0" 'git merge-base --is-ancestor v1.1.0 HEAD'
check "keeps the fork commits" '[[ "$(cat shared.txt)" == "fork line" ]]'
check "backs up the old branch" 'git rev-parse -q --verify backup/omar-custom-v1.0.0 >/dev/null'
check "pushes the branch to the fork" '[[ "$(git rev-parse HEAD)" == "$(git --git-dir="$WORK/fork.git" rev-parse omar/custom)" ]]'
check "mirrors upstream main to the fork" '[[ "$(git --git-dir="$WORK/fork.git" rev-parse main)" == "$(git rev-parse upstream/main)" ]]'
check "runs the tests, then the build" '[[ "$(tr "\n" "|" < "$WORK/build-calls.log")" == "build.sh --test|build.sh |" ]]'

echo "tag signatures"
before="$(git rev-parse HEAD)"
: > "$WORK/log.txt"; sync v1.4.0; code=$?
check "refuses an unsigned tag before touching the branch" \
    '[[ $code == 1 && "$(git rev-parse HEAD)" == "$before" ]] && events "$WORK/log.txt" | grep -q "is not signed"'
mv Tools/fork-maintenance/upstream-allowed-signers "$WORK/signers"
git_q commit -am "drop signers"
: > "$WORK/log.txt"; sync v1.2.0; code=$?
check "refuses when no signers are pinned" '[[ $code == 1 ]] && events "$WORK/log.txt" | grep -q "cannot be verified"'
git_q reset --hard "$before"

echo "conflict"
: > "$WORK/log.txt"; sync v1.2.0 --build; code=$?
check "exits 2" '[[ $code == 2 ]]'
check "names the conflicted file and both tags" \
    'events "$WORK/log.txt" | grep -q "\"type\": \"conflict\".*\"baseTag\": \"v1.1.0\".*\"targetTag\": \"v1.2.0\".*\"files\": \[\"shared.txt\"\]"'
check "leaves the branch unchanged" '[[ "$(git rev-parse HEAD)" == "$before" && -z "$(git status --porcelain)" ]]'
check "is not left mid-rebase" '[[ ! -d .git/rebase-merge && ! -d .git/rebase-apply ]]'

echo "resolved by hand, then the verify-only rerun"
git rebase --onto v1.2.0 v1.1.0 omar/custom >/dev/null 2>&1
printf 'fork line on upstream\n' > shared.txt && git add shared.txt
GIT_EDITOR=true git_q rebase --continue
: > "$WORK/log.txt"; sync v1.2.0 --build; code=$?
check "exits 0" '[[ $code == 0 ]]'
check "skips the rebase" '! events "$WORK/log.txt" | grep -q "\"stage\": \"rebase\""'

echo "a recorded resolution replays on its own"
git_q reset --hard backup/omar-custom-v1.0.0 && git_q rebase --onto v1.1.0 v1.0.0 omar/custom
: > "$WORK/log.txt"; sync v1.2.0; code=$?
check "exits 0" '[[ $code == 0 ]]'
check "applies the earlier resolution" '[[ "$(cat shared.txt)" == "fork line on upstream" ]]'

echo "dirty checkout"
printf 'x\n' >> other.txt
: > "$WORK/log.txt"; sync v1.3.0; code=$?
check "refuses with a failed event" '[[ $code == 1 ]] && events "$WORK/log.txt" | grep -q "uncommitted changes"'
git_q checkout -- other.txt

echo "a tag moved upstream, and worktree delegation"
(cd "$UP" && git_q tag -f v1.1.1-beta.1 v1.3.0)
git_q switch -c feat/x
: > "$WORK/log.txt"; sync v1.3.0 --auto-worktree; code=$?
check "exits 0 although a local tag now differs from upstream" '[[ $code == 0 ]]'
check "runs in a new omar/custom worktree beside the checkout" \
    '[[ -d "$F-omar-custom" ]] && git -C "$F-omar-custom" merge-base --is-ancestor v1.3.0 HEAD'
check "leaves the checkout on its own branch" '[[ "$(git rev-parse --abbrev-ref HEAD)" == "feat/x" ]]'
rm -rf "$F-omar-custom"
: > "$WORK/log.txt"; sync v1.3.0 --auto-worktree; code=$?
check "recreates a worktree folder deleted by hand" '[[ $code == 0 && -d "$F-omar-custom" ]]'
rm -rf "$F-omar-custom"; git worktree prune; git_q switch omar/custom

echo "one sync at a time"
/usr/bin/python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"w"); fcntl.flock(f,fcntl.LOCK_EX); time.sleep(3)' \
    "$F/.git/vorssaint-sync.lock" &
sleep 0.5
: > "$WORK/log.txt"; sync v1.3.0; code=$?
check "refuses a second sync" '[[ $code == 1 ]] && events "$WORK/log.txt" | grep -q "already running"'
wait

echo "cancel"
: > "$WORK/log.txt"
# Its own session, as the app starts it, so the whole group can be signalled.
SLOW_TEST=1 /usr/bin/python3 -c 'import os, sys; os.setsid(); os.execv(sys.argv[1], sys.argv[1:])' \
    /usr/bin/python3 -u Tools/fork-maintenance/sync-upstream.py v1.3.0 --events --log "$WORK/log.txt" &
sync_pid=$!
for _ in {1..100}; do events "$WORK/log.txt" | grep -q '"stage": "verify"' && break; sleep 0.1; done
kill -TERM -- -"$sync_pid"; wait "$sync_pid"; code=$?
check "stops on SIGTERM to its group" '[[ $code == 1 ]] && events "$WORK/log.txt" | grep -q "\"message\": \"Cancelled.\""'
check "leaves a clean branch" '[[ -z "$(git status --porcelain)" && ! -d .git/rebase-merge ]]'

echo "bad input"
: > "$WORK/log.txt"; sync v1.1.1-beta.1; code=$?
check "refuses a beta tag" '[[ $code == 1 ]]'
: > "$WORK/log.txt"; sync v1.0.0; code=$?
check "refuses an older tag" '[[ $code == 1 ]] && events "$WORK/log.txt" | grep -q "is older"'

echo "stamp"
S="$WORK/it's a \"quoted\" dir"; mkdir -p "$S" && cd "$S" && git_q init -b main
touch a && git_q add a && git_q commit -m a && git_q tag -a -m v2.0.0 v2.0.0 && git_q tag -a -m b v2.0.1-beta.1
plutil -create xml1 "$WORK/Info.plist"
/bin/zsh "$HERE/stamp-fork-source.sh" "$WORK/Info.plist" >/dev/null
check "keeps quotes and spaces in the checkout path" \
    '[[ "$(plutil -extract VorssaintForkSource.Checkout raw -o - "$WORK/Info.plist")" == "${S:A}" ]]'
check "records the stable base, not the later beta" \
    '[[ "$(plutil -extract VorssaintForkSource.BaseTag raw -o - "$WORK/Info.plist")" == "v2.0.0" ]]'
git_q tag -d v2.0.0
/bin/zsh "$HERE/stamp-fork-source.sh" "$WORK/Info.plist" >/dev/null 2>&1; code=$?
check "still stamps without a release tag, leaving the base out" \
    '[[ $code == 0 ]] && ! plutil -extract VorssaintForkSource.BaseTag raw -o - "$WORK/Info.plist" >/dev/null 2>&1'

echo "install"
I="$WORK/install"; mkdir -p "$I/bin" "$I/checkout"
cat > "$I/bin/open" <<EOF
#!/bin/zsh
echo "\$*" >> "$I/open-calls"
EOF
cat > "$I/checkout/build.sh" <<'EOF'
#!/bin/zsh
# build.sh --install: removes the installed app, then copies and signs the new one.
rm -rf "$VORSSAINT_INSTALLED_APP"; mkdir -p "$VORSSAINT_INSTALLED_APP"
if [[ -n "${FAIL_INSTALL:-}" ]]; then echo partial > "$VORSSAINT_INSTALLED_APP/marker"; exit 1; fi
echo new > "$VORSSAINT_INSTALLED_APP/marker"
EOF
chmod +x "$I/bin/open" "$I/checkout/build.sh"
(cd "$I/checkout" && git_q init -b main && git_q add -A && git_q commit -m c && git_q tag -a -m v3.0.0 v3.0.0)
export VORSSAINT_INSTALLED_APP="$I/Applications/Vorssaint.app"
support="$I/support \"x\""
install_once() {
    rm -rf "$VORSSAINT_INSTALLED_APP" "$I/open-calls"; mkdir -p "$VORSSAINT_INSTALLED_APP"
    echo old > "$VORSSAINT_INSTALLED_APP/marker"
    sleep 0.3 & local app_pid=$!
    PATH="$I/bin:$PATH" /bin/zsh "$HERE/install-local-build.sh" "$I/checkout" "$app_pid" \
        "$support/result.json" "$support/sync.log"
}
install_once
check "installs and reports it" \
    '[[ "$(json_field "$support/result.json" status)" == installed && "$(cat "$VORSSAINT_INSTALLED_APP/marker")" == new ]]'
check "records the base tag" '[[ "$(json_field "$support/result.json" baseTag)" == v3.0.0 ]]'
check "drops the kept copy and reopens the app" \
    '[[ ! -e "$support/Vorssaint-previous.app" && "$(cat "$I/open-calls")" == "-a $VORSSAINT_INSTALLED_APP" ]]'
FAIL_INSTALL=1 install_once
check "a failed install is reported" '[[ "$(json_field "$support/result.json" status)" == failed ]]'
check "and puts the previous app back, then reopens it" \
    '[[ "$(cat "$VORSSAINT_INSTALLED_APP/marker")" == old && "$(cat "$I/open-calls")" == "-a $VORSSAINT_INSTALLED_APP" ]]'

echo
if (( failures )); then echo "FAILED: $failures"; exit 1; fi
echo "fork-maintenance: all checks passed"
