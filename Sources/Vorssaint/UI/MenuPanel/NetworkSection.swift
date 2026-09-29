// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The "Network" card: live download/upload speed, a history graph and the
/// totals moved this session.
struct NetworkSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var speed = SpeedTest.shared
    @StateObject private var addresses = NetworkAddressService()
    @Environment(\.colorScheme) private var colorScheme
    var collapsible = true
    @AppStorage(DefaultsKey.monitorGraphNetwork) private var showGraph = true
    @AppStorage(DefaultsKey.monitorNetSpeed) private var netSpeed = true
    @AppStorage(DefaultsKey.monitorNetApps) private var netApps = true
    @AppStorage(DefaultsKey.monitorNetTotals) private var netTotals = true
    @AppStorage(DefaultsKey.monitorNetTest) private var netTest = true
    @AppStorage(DefaultsKey.monitorNetAddresses) private var netAddresses = true
    @AppStorage(DefaultsKey.panelNetworkOrder) private var networkOrderRaw = ""
    @AppStorage(DefaultsKey.networkSpeedUnit) private var speedUnit = NetworkSpeedUnit.bytes
    @State private var draggingBlock: Block?
    @State private var appRows: [ProcessUsage] = []
    @State private var appRowsLoading = false
    @State private var lastAppRefresh = Date.distantPast
    @State private var appRefreshSerial = 0
    @State private var networkMonitoringActive = false
    private let appLimit = 6

    var body: some View {
        PanelSection(.network, title: l10n.s.networkSection, collapsible: collapsible,
                     supportsEditing: true,
                     resetAction: resetPanelDefaults) { editing in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks(editing: editing).enumerated()), id: \.element) { index, block in
                    if index > 0 { Divider() }
                    PanelReorderableItem(item: block,
                                         isEnabled: editing,
                                         order: blockOrderBinding,
                                         dragging: $draggingBlock) {
                        HStack(alignment: .top, spacing: 8) {
                            if editing {
                                PanelDragHandle()
                            }
                            blockContent(block, editing: editing)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .panelCard()
        }
        .onAppear {
            if netApps {
                startNetworkMonitoringIfNeeded()
            }
            refreshAppRows(force: true, delay: 0.2)
        }
        .onReceive(monitor.$snapshot) { _ in
            refreshAppRows(force: false, delay: 0.2)
        }
        .onChange(of: netApps) { _, visible in
            if visible {
                startNetworkMonitoringIfNeeded()
                refreshAppRows(force: true, delay: 0.2)
            } else {
                appRefreshSerial &+= 1
                appRows = []
                appRowsLoading = false
                stopNetworkMonitoringIfNeeded()
            }
        }
        .onChange(of: netAddresses) { _, visible in
            // A hidden block keeps no public address and waits on no request.
            if !visible { PublicAddressLookup.shared.cancel() }
        }
        .onDisappear {
            appRefreshSerial &+= 1
            appRows = []
            appRowsLoading = false
            stopNetworkMonitoringIfNeeded()
        }
    }

    private enum Block: String, PanelOrderItem { case speed, apps, totals, addresses, test }

    private var visibleBlocks: [Block] {
        orderedBlocks.filter(isVisible)
    }

    private func blocks(editing: Bool) -> [Block] {
        editing ? orderedBlocks : visibleBlocks
    }

    private var orderedBlocks: [Block] {
        _ = networkOrderRaw
        return PanelLayout.itemOrder(Block.self, key: DefaultsKey.panelNetworkOrder)
    }

    private var blockOrderBinding: Binding<[Block]> {
        Binding {
            orderedBlocks
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelNetworkOrder)
        }
    }

    private func isVisible(_ block: Block) -> Bool {
        switch block {
        case .speed: return netSpeed
        case .apps: return netApps
        case .totals: return netTotals
        case .addresses: return netAddresses
        case .test: return netTest
        }
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelNetworkOrder)
        networkOrderRaw = ""
        netSpeed = true
        netApps = true
        netTotals = true
        netAddresses = true
        netTest = true
    }

    @ViewBuilder
    private func blockContent(_ block: Block, editing: Bool) -> some View {
        switch block {
        case .speed: speedBlock(editing: editing)
        case .apps: appUsageBlock(editing: editing)
        case .totals: totalsRow(editing: editing)
        case .addresses: NetworkAddressBlock(service: addresses, isVisible: $netAddresses, editing: editing)
        case .test: speedTestRow(editing: editing)
        }
    }

    @ViewBuilder
    private func appUsageBlock(editing: Bool) -> some View {
        if !netApps {
            PanelHiddenItemRow(title: l10n.s.networkApps,
                               systemImage: "list.bullet.rectangle",
                               isVisible: $netApps)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(l10n.s.networkApps)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    if editing {
                        PanelInlineHideButton(isVisible: $netApps)
                    }
                }
                if appRows.isEmpty {
                    Text(appRowsLoading ? l10n.s.breakdownMeasuring : l10n.s.networkAppsIdle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(appRows) { row in
                        ProcessUsageRow(row: row,
                                        value: networkValue(row),
                                        iconSize: 14)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func speedBlock(editing: Bool) -> some View {
        if !netSpeed {
            PanelHiddenItemRow(title: l10n.s.monitorItemNetSpeed,
                               systemImage: "arrow.down",
                               isVisible: $netSpeed)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if editing {
                    HStack {
                        Spacer(minLength: 0)
                        PanelInlineHideButton(isVisible: $netSpeed)
                    }
                }
                HStack(spacing: 10) {
                    rateColumn(icon: "arrow.down",
                               label: l10n.s.networkDownload,
                               value: monitor.snapshot.netDownBytesPerSec,
                               color: .accentColor)
                    Divider().frame(height: 28)
                    rateColumn(icon: "arrow.up",
                               label: l10n.s.networkUpload,
                               value: monitor.snapshot.netUpBytesPerSec,
                               color: PanelMetricColor.green(for: colorScheme))
                    speedUnitToggle
                }
                if showGraph, monitor.snapshot.netDownHistory.count >= 2 {
                    graph
                }
            }
        }
    }

    private var speedInBits: Bool { speedUnit == .bits }

    /// Flips every live network speed (panel, menu bar, island) between
    /// bits and bytes per second. The label shows the unit in use. Its
    /// symbol alone would not tell VoiceOver or a hover what it changes.
    private var speedUnitToggle: some View {
        let title = FeatureStrings.monitorLayout(l10n.language).networkSpeedUnit
        let symbol = speedInBits ? "bit/s" : "B/s"
        return Button {
            speedUnit = speedInBits ? .bytes : .bits
        } label: {
            Text(symbol)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("\(title) · \(speedInBits ? "bit/s → B/s" : "B/s → bit/s")")
        .accessibilityLabel(title)
        .accessibilityValue(symbol)
    }

    private func rateColumn(icon: String, label: String, value: Double?, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.map { MetricFormat.networkRate($0, inBits: speedInBits) } ?? l10n.s.networkMeasuring)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Download (filled) and upload (line) share one scale so they compare fairly.
    private var graph: some View {
        let down = monitor.snapshot.netDownHistory
        let up = monitor.snapshot.netUpHistory
        let peak = MetricFormat.networkGraphCeiling(max(down.max() ?? 0, up.max() ?? 0, 1),
                                                    inBits: speedInBits)
        return ZStack {
            Sparkline(values: down, color: .accentColor, maxValue: peak, showsZeroBaseline: true)
            Sparkline(values: up,
                      color: PanelMetricColor.green(for: colorScheme),
                      maxValue: peak,
                      fillOpacity: 0.08)
        }
        .frame(height: 30)
        .graphCeilingLabel(MetricFormat.networkRate(peak, inBits: speedInBits))
    }

    @ViewBuilder
    private func totalsRow(editing: Bool) -> some View {
        if !netTotals {
            PanelHiddenItemRow(title: l10n.s.monitorItemNetTotals,
                               systemImage: "sum",
                               isVisible: $netTotals)
        } else {
            HStack(spacing: 6) {
                Text(l10n.s.networkThisSession)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                if let down = monitor.snapshot.netTotalDown, let up = monitor.snapshot.netTotalUp {
                    Text("↓\(MetricFormat.bytes(down))  ↑\(MetricFormat.bytes(up))")
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if editing {
                    PanelInlineHideButton(isVisible: $netTotals)
                }
            }
        }
    }

    /// On-demand internet speed test (latency, download, upload).
    @ViewBuilder
    private func speedTestRow(editing: Bool) -> some View {
        if !netTest {
            PanelHiddenItemRow(title: l10n.s.monitorItemNetTest,
                               systemImage: "gauge.with.dots.needle.67percent",
                               isVisible: $netTest)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if speed.isRunning {
                        ProgressView().controlSize(.small)
                        Text(l10n.s.speedTestTesting)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            speed.start()
                        } label: {
                            Label(speed.downloadMbps == nil ? l10n.s.speedTestRun : l10n.s.speedTestAgain,
                                  systemImage: "gauge.with.dots.needle.67percent")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                    if let down = speed.downloadMbps, let up = speed.uploadMbps {
                        Text("↓\(mbps(down)) ↑\(mbps(up)) Mbps")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    if editing {
                        PanelInlineHideButton(isVisible: $netTest)
                    }
                }
                if case .failed = speed.phase {
                    Text(l10n.s.speedTestFailed)
                        .font(.system(size: 10))
                        .foregroundStyle(PanelMetricColor.orange(for: colorScheme))
                } else if let latency = speed.latencyMs {
                    Text("\(l10n.s.speedTestLatency): \(Int(latency.rounded())) ms")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func mbps(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", locale: MetricFormat.locale, value)
                     : String(format: "%.1f", locale: MetricFormat.locale, value)
    }

    private func startNetworkMonitoringIfNeeded() {
        guard !networkMonitoringActive else { return }
        networkMonitoringActive = true
        ProcessUsageService.shared.startNetworkMonitoring()
    }

    private func stopNetworkMonitoringIfNeeded() {
        guard networkMonitoringActive else { return }
        networkMonitoringActive = false
        ProcessUsageService.shared.stopNetworkMonitoring()
    }

    private func refreshAppRows(force: Bool, delay: TimeInterval = 0) {
        guard netApps else { return }
        if force {
            if let cached = ProcessUsageService.shared.cachedTop(.network, limit: appLimit) {
                appRows = cached
                appRowsLoading = false
            } else {
                appRows = []
                appRowsLoading = true
            }
        }
        guard force || Date().timeIntervalSince(lastAppRefresh) > 2 else { return }
        lastAppRefresh = Date()

        appRefreshSerial &+= 1
        let serial = appRefreshSerial
        let run = {
            guard self.appRefreshSerial == serial, self.netApps else { return }
            self.appRowsLoading = self.appRows.isEmpty
            DispatchQueue.global(qos: .utility).async {
                let rows = ProcessUsageService.shared.top(.network, limit: appLimit)
                let isWarmingUp = ProcessUsageService.shared.networkMonitoringIsWarmingUp
                DispatchQueue.main.async {
                    guard self.appRefreshSerial == serial, self.netApps else { return }
                    self.appRowsLoading = rows.isEmpty && isWarmingUp
                    if !rows.isEmpty || self.appRows.isEmpty {
                        self.appRows = rows
                    }
                    if rows.isEmpty && isWarmingUp {
                        self.refreshAppRows(force: true, delay: 1.0)
                    }
                }
            }
        }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run)
        } else {
            run()
        }
    }

    private func networkValue(_ row: ProcessUsage) -> String {
        let down = row.networkDownBytesPerSec ?? 0
        let up = row.networkUpBytesPerSec ?? 0
        return "↓\(MetricFormat.networkRateCompact(down, inBits: speedInBits)) ↑\(MetricFormat.networkRateCompact(up, inBits: speedInBits))"
    }
}

/// The address block. The local addresses never leave the machine; the public
/// one is asked of Cloudflare only when the user presses Check.
private struct NetworkAddressBlock: View {
    @ObservedObject var service: NetworkAddressService
    @Binding var isVisible: Bool
    var editing: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var lookup = PublicAddressLookup.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    private static let copiedFeedback: Duration = .seconds(1.5)

    var body: some View {
        if !isVisible {
            PanelHiddenItemRow(title: l10n.s.networkIPAddresses,
                               systemImage: "network", isVisible: $isVisible)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(l10n.s.networkLocalIP)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    // Nothing connected: the value is left out, like the totals block.
                    if !service.localAddresses.isEmpty {
                        Text(service.localAddresses.joined(separator: "\n"))
                            .font(.system(size: 10.5, weight: .medium))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if editing { PanelInlineHideButton(isVisible: $isVisible) }
                }
                publicAddressRow
            }
            // The interfaces are read only while this line is on screen: a
            // hidden block or a collapsed card costs nothing per snapshot.
            .onAppear(perform: readLocalAddresses)
            .onReceive(SystemMonitor.shared.$snapshot) { _ in readLocalAddresses() }
            .onDisappear { service.cancel() }
        }
    }

    private func readLocalAddresses() {
        service.refreshLocalAddresses()
        lookup.forgetIfNetworkChanged(service.localAddresses)
    }

    private var publicAddressRow: some View {
        HStack(spacing: 6) {
            Text(l10n.s.networkPublicIP)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 6)
            switch lookup.phase {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView().controlSize(.mini)
            case .failed:
                Text(l10n.s.networkPublicIPFailed)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelMetricColor.orange(for: colorScheme))
            case .loaded(let address):
                Text(address)
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help(address)
                copyButton(address)
            }
            checkButton
        }
    }

    private func copyButton(_ address: String) -> some View {
        let label = copied ? l10n.s.networkPublicIPCopied : l10n.s.networkPublicIPCopy
        return Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            copied = pasteboard.setString(address, forType: .string)
            if !copied { NSSound.beep() }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .help(label)
        .accessibilityLabel(label)
        .task(id: copied) {
            guard copied else { return }
            // Cancelled when the row goes away, which drops the tick anyway.
            try? await Task.sleep(for: Self.copiedFeedback)
            copied = false
        }
    }

    /// Worded before the first answer, an icon beside one: the same action.
    @ViewBuilder
    private var checkButton: some View {
        if lookup.phase == .idle {
            Button(l10n.s.networkPublicIPCheck, action: checkPublicAddress)
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                .controlSize(.mini)
        } else {
            Button(action: checkPublicAddress) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(lookup.isLoading)
            .help(l10n.s.networkPublicIPCheckAgain)
            .accessibilityLabel(l10n.s.networkPublicIPCheckAgain)
        }
    }

    private func checkPublicAddress() {
        copied = false
        lookup.refresh(network: service.localAddresses)
    }
}
