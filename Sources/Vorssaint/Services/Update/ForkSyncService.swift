// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin
import SwiftUI

/// "Sync & update" for a fork build. Runs Tools/fork-maintenance/sync-upstream.py
/// detached (so quitting the app never strands a half-done rebase), follows its
/// log for progress, and installs the result through install-local-build.sh,
/// which waits for this app to quit, installs and reopens it.
final class ForkSyncService: ObservableObject {
    static let shared = ForkSyncService()

    typealias Stage = ForkSyncSupport.Stage

    enum Phase: Equatable {
        case idle
        case running(Stage?)
        case conflict(ForkSyncSupport.Conflict)
        case failed(stage: Stage?, message: String)
        case ready(checkout: String)
        case installing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var targetTag: String?

    private static let pollInterval: TimeInterval = 0.5
    private var pid: pid_t = 0
    private var cancelling = false
    private var pollTimer: Timer?
    private var log: FileHandle?
    private var lines = ForkSyncSupport.LineBuffer()
    private var window: NSWindow?

    private init() {}

    private var strings: ForkSyncFeatureStrings { FeatureStrings.forkSync(L10n.shared.language) }

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Vorssaint/ForkSync", isDirectory: true)
    }
    static var logURL: URL { directory.appendingPathComponent("sync.log") }
    private static var resultURL: URL { directory.appendingPathComponent("install-result.json") }
    /// "<pid> <tag>" of the sync in progress, so a relaunch can follow it again.
    private static var runningURL: URL { directory.appendingPathComponent("sync.running") }

    var isActive: Bool { phase != .idle }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    // MARK: - Sync

    func start(tag: String) {
        guard let source = ForkSource.current, ForkSyncSupport.isReleaseTag(tag) else { return }
        if isRunning || phase == .installing {
            showWindow()
            return
        }
        targetTag = tag
        showWindow()
        guard FileManager.default.fileExists(atPath: source.syncScript) else {
            phase = .failed(stage: nil, message: strings.scriptMissing)
            return
        }
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try Data().write(to: Self.logURL)
            log = try FileHandle(forReadingFrom: Self.logURL)
            pid = try DetachedProcess.spawn("/usr/bin/python3",
                                            ForkSyncSupport.syncArguments(script: source.syncScript, tag: tag,
                                                                          log: Self.logURL.path))
            try "\(pid) \(tag)".write(to: Self.runningURL, atomically: true, encoding: .utf8)
        } catch {
            phase = .failed(stage: nil, message: error.localizedDescription)
            return
        }
        follow()
    }

    func retry() {
        guard let targetTag else { return }
        start(tag: targetTag)
    }

    /// SIGTERM to the whole group: the script aborts a rebase in progress, and
    /// the git or build it is waiting on stops with it.
    func cancel() {
        guard isRunning, pid > 0 else { return }
        cancelling = true
        kill(-pid, SIGTERM)
    }

    private func follow() {
        lines = ForkSyncSupport.LineBuffer()
        cancelling = false
        phase = .running(nil)
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Follows the log until the process is gone, reaping it (a finished child
    /// otherwise stays a zombie until the app quits).
    private func poll() {
        readLog()
        var status: Int32 = 0
        let reaped = waitpid(pid, &status, WNOHANG)
        // -1 (ECHILD): a sync followed again after a relaunch is not our child.
        guard reaped == pid || (reaped == -1 && kill(pid, 0) != 0) else { return }
        readLog()
        stopFollowing()
        if cancelling {
            phase = .idle
            window?.close()
        } else if case let .running(stage) = phase {
            phase = .failed(stage: stage, message: "sync-upstream.py exited with status \((status >> 8) & 0xff)")
        }
    }

    private func readLog() {
        guard let data = try? log?.readToEnd(), !data.isEmpty else { return }
        for line in lines.append(data) {
            guard let event = ForkSyncSupport.event(from: line) else { continue }
            apply(event)
        }
    }

    private func apply(_ event: ForkSyncSupport.Event) {
        switch event {
        case let .stage(stage):
            phase = .running(stage)
        case let .conflict(conflict):
            phase = .conflict(conflict)
        case let .failed(stage, message):
            phase = .failed(stage: stage, message: message)
        case let .done(checkout):
            phase = .ready(checkout: checkout)
            Notifier.post(title: strings.readyTitle, body: strings.readyBody)
        }
    }

    private func stopFollowing() {
        pollTimer?.invalidate()
        pollTimer = nil
        try? log?.close()
        log = nil
        pid = 0
        try? FileManager.default.removeItem(at: Self.runningURL)
    }

    // MARK: - Install

    func install() {
        guard case let .ready(checkout) = phase else { return }
        let script = "\(checkout)/Tools/fork-maintenance/install-local-build.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            phase = .failed(stage: nil, message: strings.scriptMissing)
            return
        }
        do {
            try DetachedProcess.spawn("/bin/zsh", [script, checkout, "\(getpid())",
                                                   Self.resultURL.path, Self.logURL.path])
        } catch {
            phase = .failed(stage: nil, message: error.localizedDescription)
            return
        }
        phase = .installing
        // Quit so the installer can replace the bundle; it reopens the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Launch

    /// At launch of a fork build: report what the last install did, once, and
    /// follow a sync a previous run left going.
    func resumeAtLaunch() {
        guard ForkSource.current != nil else { return }
        consumeInstallResult()
        followLeftoverSync()
    }

    private func consumeInstallResult() {
        guard let data = try? Data(contentsOf: Self.resultURL) else { return }
        try? FileManager.default.removeItem(at: Self.resultURL)
        guard let result = ForkSyncSupport.installResult(from: data) else { return }
        if result.installed {
            Notifier.post(title: strings.installedTitle, body: "\(result.baseTag) · \(result.commit)")
        } else {
            // The checkout is already on the new tag, so Retry only verifies, builds and installs.
            targetTag = ForkSyncSupport.isReleaseTag(result.baseTag) ? result.baseTag : nil
            phase = .failed(stage: nil, message: strings.installFailed)
            Notifier.post(title: strings.title, body: strings.installFailed)
        }
    }

    private func followLeftoverSync() {
        guard let record = try? String(contentsOf: Self.runningURL, encoding: .utf8) else { return }
        let fields = record.split(separator: " ")
        guard fields.count == 2, let leftover = pid_t(fields[0]), leftover > 0,
              ForkSyncSupport.isReleaseTag(String(fields[1])),
              kill(leftover, 0) == 0, Self.isPython(leftover),
              let handle = try? FileHandle(forReadingFrom: Self.logURL)
        else {
            try? FileManager.default.removeItem(at: Self.runningURL)
            return
        }
        pid = leftover
        targetTag = String(fields[1])
        log = handle
        follow()
    }

    /// A recycled pid must not be mistaken for the sync.
    private static func isPython(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        return String(cString: buffer).lowercased().hasPrefix("python")
    }

    // MARK: - Conflict and log

    /// Opens Claude Code in the worktree, in Terminal, with the rebase to redo.
    func resolveWithAI() {
        guard case let .conflict(conflict) = phase else { return }
        let prompt = Self.directory.appendingPathComponent("resolve-prompt.txt")
        let command = Self.directory.appendingPathComponent("resolve-conflict.command")
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try ForkSyncSupport.resolvePrompt(for: conflict).write(to: prompt, atomically: true, encoding: .utf8)
            try ForkSyncSupport.resolveCommand(worktree: conflict.worktree, promptPath: prompt.path)
                .write(to: command, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
        } catch {
            phase = .failed(stage: nil, message: error.localizedDescription)
            return
        }
        NSWorkspace.shared.open(command)
    }

    func showLog() {
        NSWorkspace.shared.open(Self.logURL)
    }

    // MARK: - Window

    /// Brings up the progress window when a sync has something to show;
    /// false when there is none, so the caller shows its own offer instead.
    @discardableResult
    func showWindowIfActive() -> Bool {
        guard isActive else { return false }
        showWindow()
        return true
    }

    func dismiss() {
        window?.close()
        switch phase {
        case .conflict, .failed:
            phase = .idle
        default:
            break
        }
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: ForkSyncView())
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = strings.title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
