import SwiftUI

/// Overview: agent card (pause/restart), headline usage, host metrics, features.
struct MagziOpsOverviewPane: View {
    @ObservedObject var store: MagziOpsStore

    @State private var pendingPause: Bool?
    @State private var confirmRestart = false
    @State private var isWorking = false
    @State private var restartNote: String?

    private let columns = [GridItem(.flexible(), spacing: MagziDesign.Spacing.m), GridItem(.flexible(), spacing: MagziDesign.Spacing.m)]

    var body: some View {
        MagziOpsPane(refresh: refresh) {
            if let error = store.stateError, store.state == nil {
                MagziOpsErrorCard(message: error, retry: refresh)
            } else if let state = store.state {
                content(state: state, usage: store.usage)
            } else {
                content(state: Self.placeholderState, usage: Self.placeholderUsage)
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
            }
        }
        .task { if store.state == nil || store.usage == nil { await refresh() } }
        .confirmationDialog(
            pendingPause == true ? "Pause Magzi?" : "Resume Magzi?",
            isPresented: Binding(get: { pendingPause != nil }, set: { if !$0 { pendingPause = nil } }),
            titleVisibility: .visible
        ) {
            if let on = pendingPause {
                Button(on ? "Pause agent" : "Resume agent", role: on ? .destructive : nil) {
                    Task { await setPaused(on) }
                }
            }
        } message: {
            Text(pendingPause == true
                 ? "Magzi stops replying and running automations until you resume."
                 : "Magzi starts replying and running automations again.")
        }
        .confirmationDialog("Restart magzid?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart service", role: .destructive) { Task { await restart() } }
        } message: {
            Text("Chats pause for about 20 seconds.")
        }
    }

    private func refresh() async {
        async let a: Void = store.loadState()
        async let b: Void = store.loadUsage()
        _ = await (a, b)
    }

    @ViewBuilder
    private func content(state: MagziCockpitState, usage: MagziUsageResponse?) -> some View {
        if let error = store.stateError {
            MagziOpsErrorCard(message: error, retry: refresh)
        }
        agentCard(state)

        MagziSectionHeader("Usage")
        if let error = store.usageError, usage == nil {
            MagziOpsErrorCard(message: error, retry: { await store.loadUsage() })
        } else {
            usageGrid(usage?.summary ?? Self.placeholderUsage.summary!)
                .redacted(reason: usage == nil ? .placeholder : [])
        }

        if let host = usage?.host {
            MagziSectionHeader("Host")
            hostCard(host)
        }

        if let sends = state.whatsappSends, sends.lastHour != nil || sends.lastDay != nil {
            MagziSectionHeader("WhatsApp sends")
            sendsCard(sends)
        }

        MagziSectionHeader("Features")
        featuresCard(state.features ?? [])
    }

    // MARK: Agent

    private func agentCard(_ state: MagziCockpitState) -> some View {
        let paused = state.paused ?? false
        return VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziStatusDot(paused ? .off : .live)
                Text(paused ? "Paused" : "Running")
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                Spacer()
                if isWorking { ProgressView() }
            }
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziPill(title: MagziOpsFormat.humanize(state.agentProfile), systemImage: "person.crop.circle", tint: MagziDesign.violet)
                MagziPill(title: MagziOpsFormat.humanize(state.mode), systemImage: "shield.lefthalf.filled", tint: modeTint(state.mode))
            }
            if state.ownerId != nil || state.primaryChannel != nil {
                VStack(spacing: MagziDesign.Spacing.s) {
                    if let owner = state.ownerId { MagziOpsKeyValue(label: "Owner", value: owner, mono: true) }
                    if let channel = state.primaryChannel { MagziOpsKeyValue(label: "Primary channel", value: MagziOpsFormat.humanize(channel)) }
                }
            }
            MagziOpsDivider()
            Toggle(isOn: Binding(
                get: { paused },
                set: { pendingPause = $0 }
            )) {
                Label("Pause agent", systemImage: "pause.circle")
                    .font(MagziDesign.Typography.body)
                    .foregroundStyle(MagziDesign.label)
            }
            .tint(MagziDesign.amber)
            .disabled(isWorking)

            Button(role: .destructive) {
                confirmRestart = true
            } label: {
                Label("Restart service", systemImage: "arrow.clockwise")
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(MagziDesign.rose)
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .disabled(isWorking)

            if let restartNote {
                Text(restartNote)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
            }
        }
        .magziCard()
    }

    private func modeTint(_ mode: String?) -> Color {
        switch mode {
        case "ProductionActive": return MagziDesign.mint
        case "StagingActive": return MagziDesign.blue
        default: return MagziDesign.amber
        }
    }

    // MARK: Usage

    private func usageGrid(_ summary: MagziUsageSummary) -> some View {
        LazyVGrid(columns: columns, spacing: MagziDesign.Spacing.m) {
            MagziMetricCard(title: "Turns", value: summary.turns.map(String.init) ?? "–", systemImage: "arrow.triangle.2.circlepath")
            MagziMetricCard(
                title: "Tokens",
                value: MagziOpsFormat.tokens(summary.totalTokens),
                systemImage: "number",
                tint: MagziDesign.blue,
                caption: "\(MagziOpsFormat.tokens(summary.inputTokens)) in · \(MagziOpsFormat.tokens(summary.outputTokens)) out"
            )
            MagziMetricCard(title: "Avg context", value: MagziOpsFormat.tokens(summary.avgContextTokens), systemImage: "text.alignleft", tint: MagziDesign.violet)
            MagziMetricCard(title: "Max context", value: MagziOpsFormat.tokens(summary.maxContextTokens), systemImage: "arrow.up.to.line", tint: MagziDesign.amber)
            MagziMetricCard(title: "Cost", value: MagziOpsFormat.cost(summary.costTotal), systemImage: "dollarsign.circle", tint: MagziDesign.mint, caption: "Recent window")
        }
    }

    private func hostCard(_ host: MagziHostMetrics) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            if let pct = host.memUsedPct {
                VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                    MagziOpsKeyValue(label: "Memory", value: "\(MagziOpsFormat.megabytes(host.memUsedMb)) of \(MagziOpsFormat.megabytes(host.memTotalMb))")
                    MagziOpsShareBar(fraction: pct / 100, tint: pct > 85 ? MagziDesign.rose : (pct > 70 ? MagziDesign.amber : MagziDesign.mint))
                }
            }
            if let cpu = host.cpuLoadPct {
                VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                    MagziOpsKeyValue(label: "CPU load", value: MagziOpsFormat.percent(cpu))
                    MagziOpsShareBar(fraction: cpu / 100, tint: cpu > 85 ? MagziDesign.rose : (cpu > 70 ? MagziDesign.amber : MagziDesign.blue))
                }
            }
            MagziOpsKeyValue(
                label: "Load avg",
                value: [host.load1, host.load5, host.load15].map { $0.map { String(format: "%.2f", $0) } ?? "–" }.joined(separator: " · ")
            )
            if let cores = host.cpuCores { MagziOpsKeyValue(label: "Cores", value: "\(cores)") }
            MagziOpsKeyValue(label: "magzid RSS", value: MagziOpsFormat.megabytes(host.procRssMb))
            MagziOpsKeyValue(label: "Available", value: MagziOpsFormat.megabytes(host.memAvailableMb))
        }
        .magziCard()
    }

    private func sendsCard(_ sends: MagziCockpitState.WhatsAppSends) -> some View {
        VStack(spacing: MagziDesign.Spacing.m) {
            if let hour = sends.lastHour { sendsRow("Last hour", hour) }
            if let day = sends.lastDay { sendsRow("Last day", day) }
        }
        .magziCard()
    }

    private func sendsRow(_ title: String, _ window: MagziCockpitState.Window) -> some View {
        let all = window.all ?? 0
        let ceiling = window.ceiling ?? 0
        let fraction = ceiling > 0 ? Double(all) / Double(ceiling) : 0
        return VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
            MagziOpsKeyValue(label: title, value: "\(all) sent · \(window.proactive ?? 0) proactive · cap \(ceiling)")
            MagziOpsShareBar(fraction: fraction, tint: fraction > 0.8 ? MagziDesign.amber : MagziDesign.mint)
        }
    }

    // MARK: Features

    @ViewBuilder
    private func featuresCard(_ features: [MagziCockpitState.Feature]) -> some View {
        if features.isEmpty {
            MagziEmptyState(systemImage: "switch.2", title: "No features reported", message: "The daemon didn't report any feature state.")
                .magziCard()
        } else {
            LazyVGrid(columns: columns, spacing: MagziDesign.Spacing.m) {
                ForEach(features) { feature in
                    VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                        HStack(spacing: MagziDesign.Spacing.xs) {
                            MagziStatusDot(MagziOpsStatusMap.feature(feature.state))
                            Text(MagziOpsFormat.humanize(feature.state))
                                .font(MagziDesign.Typography.caption)
                                .foregroundStyle(MagziDesign.labelSecondary)
                        }
                        Text(feature.name)
                            .font(MagziDesign.Typography.subheadline.weight(.semibold))
                            .foregroundStyle(MagziDesign.label)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = feature.note, !note.isEmpty {
                            Text(note)
                                .font(MagziDesign.Typography.footnote)
                                .foregroundStyle(MagziDesign.labelSecondary)
                                .lineLimit(3)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .magziCard(padding: 14)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Actions

    private func setPaused(_ on: Bool) async {
        isWorking = true
        defer { isWorking = false }
        await store.act {
            let paused = try await store.api.pause(on: on)
            store.state?.paused = paused
        }
    }

    private func restart() async {
        isWorking = true
        defer { isWorking = false }
        await store.act {
            let result = try await store.api.restart()
            restartNote = result.restarted == true
                ? "Restarting \(result.service ?? "magzid")… you may need to sign in again."
                : "Restart wasn't performed."
        }
    }

    // MARK: Placeholders

    static let placeholderState = MagziCockpitState(
        agentProfile: "personal",
        mode: "ProductionActive",
        ownerId: "owner-placeholder",
        primaryChannel: "whatsapp",
        paused: false,
        features: [
            .init(name: "WhatsApp channel", state: "on", note: "Connected"),
            .init(name: "Telegram channel", state: "off", note: "Not configured"),
            .init(name: "Conversational memory", state: "on", note: "Ready"),
            .init(name: "Knowledge base (RAG)", state: "attention", note: "Index stale"),
        ]
    )

    static let placeholderUsage = MagziUsageResponse(
        summary: MagziUsageSummary(turns: 120, inputTokens: 900_000, outputTokens: 80_000, totalTokens: 980_000, avgContextTokens: 12_000, maxContextTokens: 48_000, costTotal: 1.23),
        recent: nil,
        host: nil
    )
}
