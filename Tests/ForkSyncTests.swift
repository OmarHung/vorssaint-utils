// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ForkSyncTests {
    static func run(_ suite: TestSuite) {
        forkSource(suite)
        events(suite)
        installResults(suite)
        conflictHandOff(suite)
    }

    private static func stamp(_ fields: [String: Any]) -> [String: Any] {
        [ForkSource.infoKey: fields]
    }

    private static func forkSource(_ suite: TestSuite) {
        let complete = ForkSource(info: stamp(["Checkout": "/Users/me/vorssaint", "Branch": "omar/custom",
                                               "Commit": "abc1234", "BaseTag": "v3.4.0"]))
        suite.expect(complete?.baseTag == "v3.4.0" && complete?.baseVersion == "3.4.0"
                     && complete?.syncScript == "/Users/me/vorssaint/Tools/fork-maintenance/sync-upstream.py",
                     "a stamped build reads its checkout, base release and sync script")
        suite.expect(ForkSource(info: [:]) == nil && ForkSource(info: nil) == nil,
                     "an official build without the stamp is not a fork build")
        suite.expect(ForkSource(info: stamp(["Checkout": "vorssaint", "Branch": "b", "Commit": "c"])) == nil,
                     "a relative checkout path is refused")
        let beta = ForkSource(info: stamp(["Checkout": "/r", "Branch": "b", "Commit": "c", "BaseTag": "v3.4.1-beta.1"]))
        suite.expect(beta != nil && beta?.baseTag == nil && beta?.baseVersion == nil,
                     "a beta tag is not a release base, so no base version is claimed")

        suite.expect(ForkSyncSupport.isReleaseTag("v3.4.0") && ForkSyncSupport.isReleaseTag("v10.0.12"),
                     "stable release tags are accepted")
        suite.expect(!ForkSyncSupport.isReleaseTag("v3.4.1-beta.1") && !ForkSyncSupport.isReleaseTag("3.4.0")
                     && !ForkSyncSupport.isReleaseTag("v3.4") && !ForkSyncSupport.isReleaseTag("v3.4.0; rm -rf ~"),
                     "prereleases, bare versions and anything else are refused")
        let arguments = ForkSyncSupport.syncArguments(script: "/r/s.py", tag: "v3.4.1", log: "/l/sync.log")
        suite.expect(arguments == ["-u", "/r/s.py", "v3.4.1", "--push", "--build", "--auto-worktree",
                                   "--events", "--log", "/l/sync.log"],
                     "the app runs the full sync in a worktree of its own, reporting events to the log")
    }

    private static func events(_ suite: TestSuite) {
        let marker = ForkSyncSupport.eventMarker
        suite.expect(ForkSyncSupport.event(from: marker + #"{"type": "stage", "stage": "verify"}"#) == .stage(.verify),
                     "a stage event names the step that started")
        let conflict = ForkSyncSupport.event(from: marker + """
            {"type": "conflict", "worktree": "/r-omar-custom", "baseTag": "v3.4.0", "targetTag": "v3.4.1",
             "files": ["build.sh", "Sources/A.swift"], "commitSubject": "feat: x"}
            """.replacingOccurrences(of: "\n", with: ""))
        suite.expect(conflict == .conflict(.init(worktree: "/r-omar-custom", baseTag: "v3.4.0", targetTag: "v3.4.1",
                                                 files: ["build.sh", "Sources/A.swift"], commitSubject: "feat: x")),
                     "a conflict event carries the worktree, both tags and the files")
        suite.expect(ForkSyncSupport.event(from: marker + #"{"type": "failed", "stage": null, "message": "no tag"}"#)
                     == .failed(stage: nil, message: "no tag"),
                     "a failure before any step still reports its message")
        suite.expect(ForkSyncSupport.event(from: marker + #"{"type": "done", "checkout": "/r", "app": "/r/a"}"#)
                     == .done(checkout: "/r"),
                     "a done event names the checkout to install from")

        suite.expect(ForkSyncSupport.event(from: "$ ./build.sh --test") == nil,
                     "ordinary build output is not an event")
        suite.expect(ForkSyncSupport.event(from: marker + "{not json") == nil
                     && ForkSyncSupport.event(from: marker + #"{"type": "stage", "stage": "deploy"}"#) == nil,
                     "a malformed event or an unknown step is ignored")
        suite.expect(ForkSyncSupport.event(from: marker + #"{"type": "conflict", "worktree": "/r", "baseTag": "main", "targetTag": "v3.4.1"}"#) == nil,
                     "a conflict naming something other than release tags is ignored")

        var buffer = ForkSyncSupport.LineBuffer()
        let first = buffer.append(Data("one\ntw".utf8))
        let second = buffer.append(Data("o\n".utf8))
        suite.expect(first == ["one"] && second == ["two"],
                     "a line still being written waits for its newline")
    }

    private static func installResults(_ suite: TestSuite) {
        let installed = ForkSyncSupport.installResult(
            from: Data(#"{"status":"installed","commit":"abc1234","baseTag":"v3.4.1","log":"/l"}"#.utf8))
        suite.expect(installed == .init(installed: true, commit: "abc1234", baseTag: "v3.4.1"),
                     "an installed result reports the new base and commit")
        suite.expect(ForkSyncSupport.installResult(from: Data(#"{"status":"failed"}"#.utf8))?.installed == false,
                     "a failed install is reported as failed")
        suite.expect(ForkSyncSupport.installResult(from: Data(#"{"status":"maybe"}"#.utf8)) == nil
                     && ForkSyncSupport.installResult(from: Data("garbage".utf8)) == nil,
                     "an unknown or unreadable result is ignored")
    }

    private static func conflictHandOff(_ suite: TestSuite) {
        let conflict = ForkSyncSupport.Conflict(worktree: "/Users/me/it's here", baseTag: "v3.4.0",
                                                targetTag: "v3.4.1", files: ["build.sh"], commitSubject: "feat: y")
        let prompt = ForkSyncSupport.resolvePrompt(for: conflict)
        suite.expect(prompt.contains("git rebase --onto v3.4.1 v3.4.0 omar/custom")
                     && prompt.contains("build.sh") && prompt.contains("feat: y")
                     && prompt.contains("./build.sh --test") && prompt.contains("Do not push"),
                     "Claude is handed the exact rebase, the files, the tests and no push")
        let command = ForkSyncSupport.resolveCommand(worktree: conflict.worktree, promptPath: "/tmp/p.txt")
        suite.expect(command.hasPrefix("#!/bin/zsh -l\n") && command.contains("cd '/Users/me/it'\\''s here'")
                     && command.contains(#"exec claude "$(cat '/tmp/p.txt')""#),
                     "the Terminal script quotes the worktree path and passes the prompt from its file")
        let dollar = ForkSyncSupport.resolveCommand(worktree: "/w", promptPath: "/tmp/$HOME/`id`.txt")
        suite.expect(!dollar.contains("\"/tmp/$HOME") && dollar.contains("echo '/tmp/$HOME/`id`.txt'"),
                     "no path reaches the shell inside double quotes, where $ and backticks expand")
    }
}
