# Fork maintenance (OmarHung/vorssaint-utils)

This fork carries its own commits on top of upstream (`vorssaint/vorssaint-utils`) stable releases.

| Branch        | Role                                                                 |
| ------------- | -------------------------------------------------------------------- |
| `main`        | Mirror of upstream `main`. Never commit here.                        |
| `omar/custom` | Upstream release tag + this fork's commits. Use and build from this. |
| `feat/*`      | New work, branched from `omar/custom` and merged back.               |

Remotes: `origin` = `https://github.com/OmarHung/vorssaint-utils.git`, `upstream` = upstream.
`git rerere` (with `rerere.autoUpdate`) is enabled locally, so a conflict resolved once replays by
itself on later syncs.

Only stable tags (`vX.Y.Z`) are release bases; betas are skipped.

Upstream code is only built once its tag is verified: `sync-upstream.py` fetches just the target
tag and runs `git verify-tag` against `upstream-allowed-signers`, upstream's SSH signing keys as
GitHub publishes them (`gh api users/vorssaint/ssh_signing_keys`). That takes the place of the
Developer ID check the official updater relies on. If upstream rotates its key, the sync stops
with that message; add the new key to the file (principal `vorssaint@gmail.com`,
`namespaces="git"`) and commit it on `omar/custom`.

## Following a new upstream release

```bash
git switch omar/custom
python3 Tools/fork-maintenance/sync-upstream.py v3.4.1 --push --build
./build.sh --install
```

This backs up the branch (`backup/omar-custom-<old tag>`), rebases the fork's commits onto the new
tag, runs `./build.sh --test`, then with `--push` force-with-lease pushes `omar/custom` and
fast-forwards the fork's `main` to upstream `main`, and with `--build` builds the app.

On a conflict it stops. Resolve, `git add`, `git rebase --continue`, then re-run the same command:
a branch already on that tag is only verified, pushed and built.

## From the app

Every non-Developer build made from this fork runs `stamp-fork-source.sh` (a hook in `build.sh`),
which records the checkout, branch, commit and base tag in Info.plist as `VorssaintForkSource`.
A stamped build never installs official releases, which would replace it with upstream's app and
drop the fork's changes. It still checks upstream's latest stable release; when that is newer than
its base, the usual update banner appears, and **Update** opens the **Sync with upstream** window
instead of downloading a DMG:

1. `sync-upstream.py <tag> --push --build --auto-worktree --events --log …` runs detached, so
   quitting the app never leaves a half-done rebase; a relaunch follows it again. Progress comes
   from its log (`~/Library/Application Support/Vorssaint/ForkSync/sync.log`, **Show log**).
   **Cancel** sends SIGTERM to its process group; the script aborts a rebase in progress.
2. **Restart to install** starts `install-local-build.sh` detached and quits. It waits for the app
   to exit, runs `./build.sh --install` (which signs the installed copy again, so permissions
   survive), records the outcome and reopens Vorssaint, which reports it once. The installed app
   is kept aside meanwhile and put back if the build or its signature fails.

The window stays reachable from the update banner and from Settings › About while a sync is in
progress, stopped or built.

`--auto-worktree` runs in whichever worktree has `omar/custom` checked out, creating
`<checkout>-omar-custom` beside this one if none does, so the checkout you develop in is untouched.
It refuses when `omar/custom` itself has uncommitted changes.

On a conflict the rebase is aborted (branch unchanged) and the window lists the files, with
**Resolve with AI** (opens Terminal in that worktree running Claude Code, primed with the exact
rebase to redo, the files, and to test without pushing) and **Retry**, which then only verifies,
pushes, builds and installs.

App code: `Sources/Vorssaint/Services/Update/ForkSync*.swift`, `UI/ForkSync/ForkSyncView.swift`,
strings in `Core/ForkSyncStrings.swift`. The hooks in upstream files are kept small: `build.sh`
(stamp), `UpdateService.swift` (stable only, base version, sync instead of DMG, install result),
`AppDelegate.showUpdatePreview` and the Settings updates section (fork line instead of the beta
switch).

## Installing a fork build by hand

The first time, or to replace a build yourself:

```bash
git switch omar/custom
./build.sh --install
```

It quits Vorssaint, installs `/Applications/Vorssaint.app` signed with the local
"Vorssaint Utils Signing" identity (`Tools/setup-signing.sh` creates it once; no Apple account is
needed) and keeps your settings. Coming from the official app, whose signature is Apple's Developer
ID, macOS asks once to grant Accessibility, Screen Recording and the other permissions again.

Check it took: Settings › About shows **Fork build** with branch, base tag and commit, and
**Check now** says up to date while upstream has nothing newer.

## Testing the scripts

```bash
Tools/fork-maintenance/test-sync-upstream.sh
```

Runs the three scripts against throwaway repositories with `/usr/bin/python3` (the interpreter
the app uses) and stubs for `build.sh` and `open`. No network. `./build.sh --test` covers the
app side (`ForkSyncTests`).
