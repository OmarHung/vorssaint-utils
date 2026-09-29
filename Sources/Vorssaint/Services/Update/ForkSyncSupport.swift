// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Where a build made from this fork came from, stamped into Info.plist by
/// Tools/fork-maintenance/stamp-fork-source.sh. A stamped build syncs with
/// upstream and rebuilds instead of installing official releases, which would
/// drop the fork's own changes.
struct ForkSource: Equatable {
    static let infoKey = "VorssaintForkSource"
    /// nil in an official or Developer build.
    static let current = ForkSource(info: Bundle.main.infoDictionary)

    let checkout: String
    let branch: String
    let commit: String
    /// The upstream release under the fork's commits, e.g. "v3.4.0"; nil when
    /// the build found none.
    let baseTag: String?

    init?(info: [String: Any]?) {
        guard let stamp = info?[Self.infoKey] as? [String: Any],
              let checkout = stamp["Checkout"] as? String, checkout.hasPrefix("/"),
              let branch = stamp["Branch"] as? String,
              let commit = stamp["Commit"] as? String
        else { return nil }
        self.checkout = checkout
        self.branch = branch
        self.commit = commit
        baseTag = (stamp["BaseTag"] as? String).flatMap { ForkSyncSupport.isReleaseTag($0) ? $0 : nil }
    }

    /// "3.4.0", comparable with upstream release versions.
    var baseVersion: String? { baseTag.map { String($0.dropFirst()) } }

    var syncScript: String { "\(checkout)/Tools/fork-maintenance/sync-upstream.py" }
}

/// The contract with Tools/fork-maintenance: the event lines sync-upstream.py
/// prints, the result install-local-build.sh leaves, and the prompt that hands
/// a rebase conflict to Claude Code.
enum ForkSyncSupport {
    static let eventMarker = "VORSSAINT_SYNC_EVENT "

    enum Stage: String, CaseIterable {
        case fetch, rebase, verify, push, build
    }

    struct Conflict: Equatable {
        let worktree: String
        let baseTag: String
        let targetTag: String
        let files: [String]
        let commitSubject: String?
    }

    enum Event: Equatable {
        case stage(Stage)
        case conflict(Conflict)
        case failed(stage: Stage?, message: String)
        case done(checkout: String)
    }

    struct InstallResult: Equatable {
        let installed: Bool
        let commit: String
        let baseTag: String
    }

    static func isReleaseTag(_ tag: String) -> Bool {
        tag.range(of: #"^v\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
    }

    static func syncArguments(script: String, tag: String, log: String) -> [String] {
        ["-u", script, tag, "--push", "--build", "--auto-worktree", "--events", "--log", log]
    }

    /// One log line; anything that is not a well-formed event is ordinary output.
    static func event(from line: String) -> Event? {
        guard line.hasPrefix(eventMarker),
              let data = line.dropFirst(eventMarker.count).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "stage":
            return (object["stage"] as? String).flatMap(Stage.init(rawValue:)).map(Event.stage)
        case "conflict":
            guard let worktree = object["worktree"] as? String,
                  let baseTag = object["baseTag"] as? String, isReleaseTag(baseTag),
                  let targetTag = object["targetTag"] as? String, isReleaseTag(targetTag)
            else { return nil }
            return .conflict(Conflict(worktree: worktree, baseTag: baseTag, targetTag: targetTag,
                                      files: object["files"] as? [String] ?? [],
                                      commitSubject: object["commitSubject"] as? String))
        case "failed":
            return .failed(stage: (object["stage"] as? String).flatMap(Stage.init(rawValue:)),
                           message: object["message"] as? String ?? "")
        case "done":
            return (object["checkout"] as? String).map { .done(checkout: $0) }
        default:
            return nil
        }
    }

    static func installResult(from data: Data) -> InstallResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String, status == "installed" || status == "failed"
        else { return nil }
        return InstallResult(installed: status == "installed",
                             commit: object["commit"] as? String ?? "",
                             baseTag: object["baseTag"] as? String ?? "")
    }

    /// What Claude Code is asked to do in the worktree: redo the exact rebase
    /// the app aborted, resolve it keeping both sides, test, and stop there.
    static func resolvePrompt(for conflict: Conflict) -> String {
        var lines = [
            "This is my fork of Vorssaint. Re-stack my branch omar/custom onto upstream release \(conflict.targetTag).",
            "Run exactly: git rebase --onto \(conflict.targetTag) \(conflict.baseTag) omar/custom",
            "Vorssaint's Sync & update stopped on conflicts and aborted, so the branch is unchanged.",
        ]
        if let subject = conflict.commitSubject {
            lines.append("It stopped while applying: \(subject)")
        }
        if !conflict.files.isEmpty {
            lines.append("Conflicted files: \(conflict.files.joined(separator: ", "))")
        }
        lines += [
            "Resolve every conflict keeping upstream's changes and my fork's features, then git add and",
            "git rebase --continue until the rebase finishes. Localization files must keep every language.",
            "Then run ./build.sh --test and fix what fails. Do not push. When it passes, tell me to press",
            "Retry in Vorssaint, which tests, pushes, builds and installs.",
        ]
        return lines.joined(separator: "\n")
    }

    /// The Terminal script that opens Claude Code in the worktree with that prompt.
    static func resolveCommand(worktree: String, promptPath: String) -> String {
        """
        #!/bin/zsh -l
        cd \(shellQuoted(worktree)) || exit 1
        if ! command -v claude >/dev/null 2>&1; then
            echo 'Claude Code (claude) is not on PATH. The task is in:'
            echo \(shellQuoted(promptPath))
            exec zsh -l
        fi
        exec claude "$(cat \(shellQuoted(promptPath)))"

        """
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Splits a growing log into whole lines; a line still being written waits
    /// for its newline.
    struct LineBuffer {
        private var pending = Data()

        mutating func append(_ data: Data) -> [String] {
            pending.append(data)
            var lines: [String] = []
            while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
                pending.removeSubrange(pending.startIndex...newline)
            }
            return lines
        }
    }
}
