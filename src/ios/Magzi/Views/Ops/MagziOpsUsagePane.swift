import SwiftUI

/// Usage: headline cards, by-model / by-provider share bars, recent turns.
struct MagziOpsUsagePane: View {
    @ObservedObject var store: MagziOpsStore

    private let columns = [GridItem(.flexible(), spacing: MagziDesign.Spacing.m), GridItem(.flexible(), spacing: MagziDesign.Spacing.m)]

    var body: some View {
        MagziOpsPane(refresh: { await store.loadUsage() }) {
            if let error = store.usageError, store.usage == nil {
                MagziOpsErrorCard(message: error, retry: { await store.loadUsage() })
            } else if let usage = store.usage {
                if let error = store.usageError {
                    MagziOpsErrorCard(message: error, retry: { await store.loadUsage() })
                }
                content(usage)
            } else {
                content(Self.placeholder)
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
            }
        }
        .task { if store.usage == nil { await store.loadUsage() } }
    }

    @ViewBuilder
    private func content(_ usage: MagziUsageResponse) -> some View {
        let summary = usage.summary ?? MagziUsageSummary()
        let recent = usage.recent ?? summary.recent ?? []

        LazyVGrid(columns: columns, spacing: MagziDesign.Spacing.m) {
            MagziMetricCard(title: "Tokens", value: MagziOpsFormat.tokens(summary.totalTokens), systemImage: "number", tint: MagziDesign.blue,
                            caption: "\(summary.turns ?? 0) turns")
            MagziMetricCard(title: "Cost", value: MagziOpsFormat.cost(summary.costTotal), systemImage: "dollarsign.circle",
                            caption: "Avg ctx \(MagziOpsFormat.tokens(summary.avgContextTokens))")
        }

        MagziSectionHeader("By model")
        tallyCard(summary.byModel ?? [], tint: MagziDesign.mint, empty: "No model usage yet.")

        if let providers = summary.byProvider, providers.count > 1 {
            MagziSectionHeader("By provider")
            tallyCard(providers, tint: MagziDesign.blue, empty: "")
        }

        if let households = summary.byHousehold, !households.isEmpty {
            MagziSectionHeader("By household")
            VStack(spacing: MagziDesign.Spacing.m) {
                ForEach(households) { h in
                    MagziOpsKeyValue(
                        label: h.household ?? "–",
                        value: "\(MagziOpsFormat.tokens(h.totalTokens)) · \(h.turns ?? 0) turns · \(MagziOpsFormat.cost(h.costTotal))"
                    )
                }
            }
            .magziCard()
        }

        MagziSectionHeader("Recent turns")
        if recent.isEmpty {
            MagziEmptyState(systemImage: "clock", title: "No turns yet", message: "Turns appear here as Magzi replies.")
                .magziCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(recent.sorted { ($0.at ?? 0) > ($1.at ?? 0) }.enumerated()), id: \.offset) { index, record in
                    if index > 0 { MagziOpsDivider() }
                    MagziOpsTurnRow(record: record)
                }
            }
            .magziCard(padding: MagziDesign.Spacing.m)
        }
    }

    @ViewBuilder
    private func tallyCard(_ tallies: [MagziTally], tint: Color, empty: String) -> some View {
        let total = max(1, tallies.reduce(Int64(0)) { $0 + $1.totalTokens })
        if tallies.isEmpty {
            Text(empty)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .magziCard()
        } else {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.l) {
                ForEach(tallies.sorted { $0.totalTokens > $1.totalTokens }) { tally in
                    VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(tally.name)
                                .font(MagziDesign.Typography.mono)
                                .foregroundStyle(MagziDesign.label)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: MagziDesign.Spacing.s)
                            Text("\(MagziOpsFormat.tokens(tally.totalTokens)) · \(tally.turns)")
                                .font(MagziDesign.Typography.footnote)
                                .foregroundStyle(MagziDesign.labelSecondary)
                                .monospacedDigit()
                        }
                        MagziOpsShareBar(fraction: Double(tally.totalTokens) / Double(total), tint: tint)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .magziCard()
        }
    }

    private static let placeholder = MagziUsageResponse(
        summary: MagziUsageSummary(
            turns: 120, totalTokens: 980_000, avgContextTokens: 12_000, maxContextTokens: 48_000,
            costTotal: 1.23
        ),
        recent: [],
        host: nil
    )
}

/// One `UsageRecord`: channel, provider/model, tokens, iterations, status, cost.
struct MagziOpsTurnRow: View {
    let record: MagziUsageRecord

    var body: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziStatusDot(MagziOpsStatusMap.dot(record.status ?? (record.errorKind == nil ? "ok" : "error")))
                if let channel = record.channel {
                    MagziPill(title: channel, tint: MagziDesign.violet)
                }
                Text([record.provider, record.model].compactMap { $0 }.joined(separator: "/"))
                    .font(MagziDesign.Typography.mono)
                    .foregroundStyle(MagziDesign.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: MagziDesign.Spacing.xs)
                Text(MagziOpsFormat.relative(ms: record.at))
                    .font(MagziDesign.Typography.caption)
                    .foregroundStyle(MagziDesign.labelTertiary)
            }
            HStack(spacing: MagziDesign.Spacing.m) {
                stat("number", MagziOpsFormat.tokens(record.totalTokens))
                stat("arrow.triangle.2.circlepath", "\(record.iterations ?? 0) it")
                stat("dollarsign.circle", MagziOpsFormat.cost(record.costTotal))
                if let status = record.status { stat("info.circle", MagziOpsFormat.humanize(status)) }
            }
            if let message = record.errorMessage ?? record.errorKind {
                Text(message)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.rose)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, MagziDesign.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(MagziDesign.labelTertiary)
            Text(text)
                .font(MagziDesign.Typography.footnote)
                .foregroundStyle(MagziDesign.labelSecondary)
                .monospacedDigit()
        }
    }
}
