// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Progress of a fork build's "Sync & update": the five steps of
/// sync-upstream.py, then a conflict to resolve, a failure to retry, or a
/// build to install.
struct ForkSyncView: View {
    @ObservedObject private var sync = ForkSyncService.shared
    @ObservedObject private var l10n = L10n.shared

    private var text: ForkSyncFeatureStrings { FeatureStrings.forkSync(l10n.language) }
    private typealias Stage = ForkSyncSupport.Stage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            stageList
            outcome
            actions
        }
        .padding(20)
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(text.title).font(.title3.bold())
            if let source = ForkSource.current {
                Text("\(source.branch) · \(source.baseTag ?? "?") → \(sync.targetTag ?? "?")")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stageList: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Stage.allCases, id: \.self) { stage in
                HStack(spacing: 8) {
                    stageIcon(stage).frame(width: 16)
                    Text(title(stage))
                        .foregroundStyle(isDone(stage) || isCurrent(stage) ? .primary : .secondary)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func stageIcon(_ stage: Stage) -> some View {
        if isCurrent(stage), case .running = sync.phase {
            ProgressView().controlSize(.small)
        } else if isCurrent(stage) {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
        } else if isDone(stage) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var outcome: some View {
        switch sync.phase {
        case let .conflict(conflict):
            message(text.conflictTitle, body: text.conflictBody, tint: .orange,
                    details: conflict.files.joined(separator: "\n"))
        case let .failed(_, reason):
            message(text.failedTitle, body: reason, tint: .orange, details: nil)
        case .ready:
            message(text.readyTitle, body: text.readyBody, tint: .green, details: nil)
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text.installing)
            }
        case .idle, .running:
            EmptyView()
        }
    }

    private func message(_ title: String, body: String, tint: Color, details: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(tint)
            Text(body).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let details, !details.isEmpty {
                Text(details)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(8)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(text.showLog) { sync.showLog() }
            Spacer()
            switch sync.phase {
            case .conflict:
                Button(text.resolveWithAI) { sync.resolveWithAI() }
                Button(text.retry) { sync.retry() }.buttonStyle(.borderedProminent)
            case .failed where sync.targetTag != nil:
                Button(text.retry) { sync.retry() }.buttonStyle(.borderedProminent)
            case .ready:
                Button(text.close) { sync.dismiss() }
                Button(text.restartToInstall) { sync.install() }.buttonStyle(.borderedProminent)
            case .running:
                Button(text.cancel) { sync.cancel() }
                Button(text.close) { sync.dismiss() }
            default:
                Button(text.close) { sync.dismiss() }
            }
        }
    }

    // MARK: - Stage state

    private var currentStage: Stage? {
        switch sync.phase {
        case let .running(stage): return stage
        case let .failed(stage, _): return stage
        case .conflict: return .rebase
        default: return nil
        }
    }

    private func isCurrent(_ stage: Stage) -> Bool { stage == currentStage }

    private func isDone(_ stage: Stage) -> Bool {
        switch sync.phase {
        case .ready, .installing:
            return true
        default:
            guard let current = currentStage,
                  let index = Stage.allCases.firstIndex(of: current),
                  let position = Stage.allCases.firstIndex(of: stage) else { return false }
            return position < index
        }
    }

    private func title(_ stage: Stage) -> String {
        switch stage {
        case .fetch: return text.stageFetch
        case .rebase: return text.stageRebase
        case .verify: return text.stageVerify
        case .push: return text.stagePush
        case .build: return text.stageBuild
        }
    }
}
