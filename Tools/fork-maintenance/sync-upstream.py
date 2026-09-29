#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Re-stack this fork's own commits (omar/custom) onto a newer upstream release tag.

    python3 Tools/fork-maintenance/sync-upstream.py v3.4.1 [--push] [--build]
                                                    [--auto-worktree] [--events] [--log PATH]

Steps: fetch the tag -> verify upstream's signature on it -> back up the branch ->
rebase --onto <new> <old> -> ./build.sh --test.
--push force-with-lease pushes the branch and fast-forwards the fork's main to upstream main;
--build then builds the app (./build.sh), stamped as a fork build.
A rebase conflict stops the script; resolutions git rerere has recorded replay on their own.

App mode (Vorssaint's "Sync & update"):
  --auto-worktree  run in whichever worktree has omar/custom checked out, creating one beside
                   this checkout if none does, so the checkout you develop in is left alone.
  --events         print `VORSSAINT_SYNC_EVENT <json>` lines (stage / conflict / failed / done)
                   and, on a conflict, abort the rebase so the branch is exactly as before (exit 2).
  --log PATH       send all output to PATH (the app starts this script detached, with no stdio).

SIGTERM (the app's Cancel) stops it, aborting a rebase in progress.
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path
from typing import Any, NoReturn, TextIO

UPSTREAM_REMOTE = "upstream"
FORK_REMOTE = "origin"
CUSTOM_BRANCH = "omar/custom"
RELEASE_TAG = re.compile(r"^v\d+\.\d+\.\d+$")
CONFLICT_EXIT = 2
STAGED_APP = Path("build/stage/Vorssaint.app")
# Upstream's SSH tag-signing keys (GitHub: users/vorssaint/ssh_signing_keys). The official app
# trusts upstream's Developer ID; a fork build instead trusts only tags signed with these keys.
ALLOWED_SIGNERS = Path("Tools/fork-maintenance/upstream-allowed-signers")
# A GUI app's PATH stops at /usr/bin; build.sh and git hooks may need Homebrew tools.
EXTRA_PATH = ["/opt/homebrew/bin", "/usr/local/bin"]

SCRIPT = Path(__file__).resolve()
REPO_ROOT = SCRIPT.parents[2]
SCRIPT_RELATIVE = SCRIPT.relative_to(REPO_ROOT)

parser = argparse.ArgumentParser(description="Re-stack omar/custom onto an upstream release tag.")
parser.add_argument("tag", nargs="?")
parser.add_argument("--push", action="store_true")
parser.add_argument("--build", action="store_true")
parser.add_argument("--auto-worktree", action="store_true")
parser.add_argument("--events", action="store_true")
parser.add_argument("--log")
options = parser.parse_args()
target_tag = options.tag
events_mode = options.events
current_stage = None


def redirect_output(path: str) -> None:
    """Detached from the app, stdout and stderr are /dev/null: point both at the log."""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    os.dup2(fd, 1)
    os.dup2(fd, 2)
    os.close(fd)
    sys.stdout = os.fdopen(1, "w", buffering=1, closefd=False)
    sys.stderr = os.fdopen(2, "w", buffering=1, closefd=False)


def emit(event: dict[str, Any]) -> None:
    if events_mode:
        # The leading newline keeps the marker at the start of a line even when a child
        # process left its last line unterminated.
        print(f"\nVORSSAINT_SYNC_EVENT {json.dumps(event)}", flush=True)


def stage(name: str) -> None:
    global current_stage
    current_stage = name
    emit({"type": "stage", "stage": name})


def fail(message: str) -> NoReturn:
    print(f"\n[sync-upstream] {message}", file=sys.stderr, flush=True)
    emit({"type": "failed", "stage": current_stage, "message": message})
    sys.exit(1)


def environment() -> dict[str, str]:
    env = dict(os.environ)
    parts = env.get("PATH", "/usr/bin:/bin:/usr/sbin:/sbin").split(":")
    env["PATH"] = ":".join(parts + [p for p in EXTRA_PATH if p not in parts])
    # Why: nobody is at a terminal in app mode, so a credential prompt would hang forever.
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_EDITOR"] = "true"
    return env


ENV = environment()


def run(*command: str, cwd: Path | None = None) -> None:
    print(f"\n$ {' '.join(command)}", flush=True)
    result = subprocess.run(command, cwd=cwd or REPO_ROOT, env=ENV)
    if result.returncode != 0:
        fail(f"`{' '.join(command)}` exited with {result.returncode}.")


def git(*git_args: str, check: bool = True) -> str:
    result = subprocess.run(["git", *git_args], cwd=REPO_ROOT, env=ENV,
                            capture_output=True, text=True)
    if check and result.returncode != 0:
        fail(f"`git {' '.join(git_args)}` failed: {result.stderr.strip()}")
    return result.stdout.strip()


def release_key(tag: str) -> tuple[int, ...]:
    return tuple(int(part) for part in tag[1:].split("."))


def find_custom_branch_worktree() -> str | None:
    # A worktree folder deleted by hand would otherwise still be listed.
    git("worktree", "prune")
    path = None
    for line in git("worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            path = line[len("worktree "):]
        elif line == f"branch refs/heads/{CUSTOM_BRANCH}":
            return path
    return None


def delegate_to_custom_branch_worktree() -> NoReturn:
    """Re-runs this script inside the worktree that owns the branch; never returns."""
    worktree = find_custom_branch_worktree()
    if worktree is None:
        worktree = f"{REPO_ROOT}-{CUSTOM_BRANCH.replace('/', '-')}"
        if Path(worktree).exists():
            fail(f"{worktree} exists but is not a worktree of {CUSTOM_BRANCH}. Move it aside and retry.")
        run("git", "worktree", "add", worktree, CUSTOM_BRANCH)
    print(f"[sync-upstream] Running in {CUSTOM_BRANCH} worktree {worktree}", flush=True)
    script = Path(worktree) / SCRIPT_RELATIVE
    if not script.exists():
        fail(f"{script} does not exist; {CUSTOM_BRANCH} has no sync script.")
    forwarded = [a for a in sys.argv[1:] if a != "--auto-worktree"]
    sys.stdout.flush()
    os.execv(sys.executable, [sys.executable, "-u", str(script), *forwarded])


def conflicted_files() -> list[str]:
    output = git("diff", "--name-only", "--diff-filter=U", check=False)
    return output.splitlines() if output else []


def rebase_in_progress() -> bool:
    git_dir = Path(git("rev-parse", "--git-dir"))
    git_dir = git_dir if git_dir.is_absolute() else REPO_ROOT / git_dir
    return (git_dir / "rebase-merge").exists() or (git_dir / "rebase-apply").exists()


def continue_with_recorded_resolutions(max_steps: int) -> bool:
    """rerere.autoUpdate stages resolutions it has seen before; keep going while it covers
    every conflict. Returns False once a conflict needs a person. Bounded, because a step
    that stops for another reason (an emptied commit) would otherwise loop forever."""
    for _ in range(max_steps):
        if not rebase_in_progress():
            return True
        if conflicted_files():
            return False
        print("[sync-upstream] rerere resolved this step; continuing.", flush=True)
        subprocess.run(["git", "rebase", "--continue"], cwd=REPO_ROOT, env=ENV)
    return not rebase_in_progress()


def rebase_onto(current_base: str) -> None:
    own = git("log", "--oneline", f"{current_base}..HEAD")
    print(f"\n[sync-upstream] Moving these commits from {current_base} to {target_tag}:\n{own}", flush=True)
    backup = f"backup/{CUSTOM_BRANCH.replace('/', '-')}-{current_base}"
    run("git", "branch", "-f", backup, "HEAD")
    print(f"[sync-upstream] Backup saved as {backup}.", flush=True)

    print(f"\n$ git rebase --onto {target_tag} {current_base} {CUSTOM_BRANCH}", flush=True)
    rebased = subprocess.run(["git", "rebase", "--onto", target_tag, current_base, CUSTOM_BRANCH],
                             cwd=REPO_ROOT, env=ENV).returncode == 0
    if rebased or continue_with_recorded_resolutions(2 * len(own.splitlines()) + 2):
        # A rebase refused up front (not a conflict) leaves no rebase in progress either.
        if subprocess.run(["git", "merge-base", "--is-ancestor", target_tag, "HEAD"],
                          cwd=REPO_ROOT, env=ENV).returncode != 0:
            fail(f"The rebase onto {target_tag} did not complete; see the output above.")
        return
    subject = git("log", "-1", "--format=%s", "REBASE_HEAD", check=False) or None
    if events_mode:
        # Why abort in app mode: nobody is at a terminal to finish a half-applied rebase, so
        # the branch returns to its pre-sync state; the event says exactly what to resolve.
        # Reported after the abort, so a Retry right away cannot race it.
        files = conflicted_files()
        subprocess.run(["git", "rebase", "--abort"], cwd=REPO_ROOT, env=ENV)
        emit({"type": "conflict", "worktree": str(REPO_ROOT), "baseTag": current_base,
              "targetTag": target_tag, "files": files, "commitSubject": subject})
        sys.exit(CONFLICT_EXIT)
    fail("\n".join([
        "Rebase stopped on a conflict. Resolve the files, then:",
        "  git add <files> && git rebase --continue",
        f"Then re-run this script with {target_tag} (same flags) to verify, push and build.",
        f"To give up: git rebase --abort (the branch returns to {backup}'s state).",
    ]))


def hold_lock() -> TextIO:
    """One sync at a time per repository: two would fight over the rebase."""
    common = Path(git("rev-parse", "--git-common-dir"))
    common = common if common.is_absolute() else REPO_ROOT / common
    handle = open(common / "vorssaint-sync.lock", "w")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        fail("Another sync is already running in this repository.")
    return handle


def main() -> None:
    if options.log:
        redirect_output(options.log)
    if not target_tag or not RELEASE_TAG.match(target_tag):
        fail("Usage: sync-upstream.py <release tag, e.g. v3.4.1> [--push] [--build] "
             "[--auto-worktree] [--events] [--log PATH]")
    if git("rev-parse", "--abbrev-ref", "HEAD") != CUSTOM_BRANCH:
        if options.auto_worktree:
            delegate_to_custom_branch_worktree()
        fail(f"Switch to {CUSTOM_BRANCH} first (git switch {CUSTOM_BRANCH}).")
    if git("status", "--porcelain"):
        fail(f"{REPO_ROOT} has uncommitted changes on {CUSTOM_BRANCH}. Commit or stash them first.")
    lock = hold_lock()

    stage("fetch")
    # Only the target tag, forced: one tag moved upstream (a re-cut beta) would otherwise make
    # every later fetch fail with "would clobber existing tag". The signature check follows.
    print(f"\n$ git fetch --no-tags {UPSTREAM_REMOTE} +refs/tags/{target_tag}:refs/tags/{target_tag}", flush=True)
    if subprocess.run(["git", "fetch", "--no-tags", UPSTREAM_REMOTE,
                       f"+refs/tags/{target_tag}:refs/tags/{target_tag}"], cwd=REPO_ROOT, env=ENV).returncode != 0:
        fail(f"Could not fetch tag {target_tag} from {UPSTREAM_REMOTE}.")
    signers = REPO_ROOT / ALLOWED_SIGNERS
    if not signers.exists():
        fail(f"{ALLOWED_SIGNERS} is missing, so {target_tag} cannot be verified.")
    print(f"\n$ git verify-tag {target_tag}", flush=True)
    if subprocess.run(["git", "-c", f"gpg.ssh.allowedSignersFile={signers}", "verify-tag", target_tag],
                      cwd=REPO_ROOT, env=ENV).returncode != 0:
        fail(f"{target_tag} is not signed by a key in {ALLOWED_SIGNERS}. If upstream rotated its "
             "signing key, add the new one from GitHub (users/vorssaint/ssh_signing_keys) and retry.")

    # Why --exclude: beta and rc tags ("-beta.1") are not release bases.
    current_base = git("describe", "--tags", "--abbrev=0", "--match", "v*", "--exclude", "*-*", "HEAD")
    if release_key(target_tag) < release_key(current_base):
        fail(f"{CUSTOM_BRANCH} is based on {current_base}; {target_tag} is older.")
    # Why verify-only on an equal base: after a conflict was resolved by hand the rebase is
    # already done, and re-running with the same tag should still test, push and build.
    if release_key(target_tag) == release_key(current_base):
        print(f"\n[sync-upstream] Already based on {target_tag}; verifying only.", flush=True)
    else:
        stage("rebase")
        rebase_onto(current_base)

    stage("verify")
    run("./build.sh", "--test")

    if options.push:
        stage("push")
        # --force-if-includes: a background fetch (an IDE's) must not turn the lease into a blind force.
        run("git", "push", "--force-with-lease", "--force-if-includes", FORK_REMOTE, CUSTOM_BRANCH)
        # Why best effort: the fork's main only mirrors upstream; a diverged main must not
        # hold back the app update.
        mirrored = subprocess.run(["git", "fetch", "--no-tags", UPSTREAM_REMOTE, "main"], cwd=REPO_ROOT, env=ENV).returncode == 0 \
            and subprocess.run(["git", "push", FORK_REMOTE,
                                f"refs/remotes/{UPSTREAM_REMOTE}/main:refs/heads/main"],
                               cwd=REPO_ROOT, env=ENV).returncode == 0
        if not mirrored:
            print(f"[sync-upstream] Warning: could not fast-forward {FORK_REMOTE}/main.", flush=True)

    if options.build:
        stage("build")
        run("./build.sh")
        emit({"type": "done", "checkout": str(REPO_ROOT), "app": str(REPO_ROOT / STAGED_APP),
              "baseTag": target_tag, "commit": git("rev-parse", "--short", "HEAD")})

    print(f"\n[sync-upstream] {CUSTOM_BRANCH} is now based on {target_tag}.", flush=True)
    if not options.push:
        print(f"Push when ready: git push --force-with-lease {FORK_REMOTE} {CUSTOM_BRANCH} "
              f"&& git push {FORK_REMOTE} refs/remotes/{UPSTREAM_REMOTE}/main:refs/heads/main", flush=True)
    lock.close()


class Cancelled(Exception):
    pass


def on_terminate(signum: int, frame: Any) -> None:
    raise Cancelled()


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, on_terminate)
    try:
        main()
    except Cancelled:
        if rebase_in_progress():
            subprocess.run(["git", "rebase", "--abort"], cwd=REPO_ROOT, env=ENV)
        fail("Cancelled.")
