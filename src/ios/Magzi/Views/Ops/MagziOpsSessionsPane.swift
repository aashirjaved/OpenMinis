import SwiftUI

/// Sessions list → trace detail.
struct MagziOpsSessionsPane: View {
    @ObservedObject var store: MagziOpsStore

    var body: some View {
        MagziOpsPane(refresh: { await store.loadSessions() }) {
            if let error = store.sessionsError, store.sessions == nil {
                MagziOpsErrorCard(message: error, retry: { await store.loadSessions() })
            } else if let sessions = store.sessions {
                if let error = store.sessionsError {
                    MagziOpsErrorCard(message: error, retry: { await store.loadSessions() })
                }
                if sessions.isEmpty {
                    MagziEmptyState(systemImage: "text.bubble", title: "No sessions", message: "Conversations show up here once Magzi has talked to someone.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sessions.sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }.enumerated()), id: \.element.id) { index, session in
                            if index > 0 { MagziOpsDivider() }
                            NavigationLink {
                                MagziOpsTraceView(store: store, conversation: session.conversation)
                            } label: {
                                MagziOpsSessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .magziCard(padding: MagziDesign.Spacing.m)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        MagziOpsSessionRow(session: MagziCockpitSession(conversation: "whatsapp:+440000000\(i)", lastInput: "Placeholder message text", ts: nil, turns: 3))
                    }
                }
                .magziCard(padding: MagziDesign.Spacing.m)
                .redacted(reason: .placeholder)
            }
        }
        .task { if store.sessions == nil { await store.loadSessions() } }
    }
}

private struct MagziOpsSessionRow: View {
    let session: MagziCockpitSession

    var body: some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                HStack(spacing: MagziDesign.Spacing.s) {
                    if let channel = MagziOpsFormat.channel(of: session.conversation) {
                        MagziPill(title: channel, tint: MagziDesign.violet)
                    }
                    Text(session.conversation)
                        .font(MagziDesign.Typography.mono)
                        .foregroundStyle(MagziDesign.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let input = session.lastInput, !input.isEmpty {
                    Text(input)
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(2)
                }
                Text("\(session.turns ?? 0) turns · \(MagziOpsFormat.relative(ms: session.ts))")
                    .font(MagziDesign.Typography.caption)
                    .foregroundStyle(MagziDesign.labelTertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(MagziDesign.labelTertiary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.vertical, MagziDesign.Spacing.s)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Trace detail: turns, model calls, and an audit-event timeline.
struct MagziOpsTraceView: View {
    @ObservedObject var store: MagziOpsStore
    let conversation: String

    @State private var trace: MagziSessionTrace?
    @State private var error: String?
    @State private var errorsOnly = false

    var body: some View {
        MagziOpsPane(refresh: load) {
            if let error, trace == nil {
                MagziOpsErrorCard(message: error, retry: load)
            } else if let trace {
                content(trace)
            } else {
                content(Self.placeholder)
                    .redacted(reason: .placeholder)
                    .allowsHitTesting(false)
            }
        }
        .magziScreenBackground()
        .navigationTitle("Trace")
        .navigationBarTitleDisplayMode(.inline)
        .task { if trace == nil { await load() } }
    }

    private func load() async {
        do {
            trace = try await store.api.sessionTrace(conversation: conversation, limit: 500)
            error = nil
        } catch {
            if let text = store.message(for: error) { self.error = text }
        }
    }

    @ViewBuilder
    private func content(_ trace: MagziSessionTrace) -> some View {
        let events = (trace.events ?? []).filter { !errorsOnly || $0.isError }
        let usage = trace.usage ?? []
        let pages = trace.pages ?? []

        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            Text(trace.conversation ?? conversation)
                .font(MagziDesign.Typography.mono)
                .foregroundStyle(MagziDesign.label)
                .textSelection(.enabled)
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziPill(title: "\(pages.count) turn\(pages.count == 1 ? "" : "s")", systemImage: "text.bubble", tint: MagziDesign.mint)
                MagziPill(title: "\(usage.count) model call\(usage.count == 1 ? "" : "s")", systemImage: "cpu", tint: MagziDesign.blue)
                MagziPill(title: (trace.events ?? []).filter(\.isError).count == 1 ? "1 error" : "\((trace.events ?? []).filter(\.isError).count) errors", systemImage: "exclamationmark.triangle", tint: MagziDesign.rose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magziCard()

        if !pages.isEmpty {
            MagziSectionHeader("Turns")
            ForEach(pages.sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }) { page in
                pageCard(page)
            }
        }

        if !usage.isEmpty {
            MagziSectionHeader("Model calls")
            VStack(spacing: 0) {
                ForEach(Array(usage.sorted { ($0.at ?? 0) > ($1.at ?? 0) }.enumerated()), id: \.offset) { index, u in
                    if index > 0 { MagziOpsDivider() }
                    usageRow(u)
                }
            }
            .magziCard(padding: MagziDesign.Spacing.m)
        }

        HStack {
            MagziSectionHeader("Timeline")
            Toggle("Errors only", isOn: $errorsOnly)
                .font(MagziDesign.Typography.footnote)
                .fixedSize()
                .tint(MagziDesign.rose)
        }
        if events.isEmpty {
            MagziEmptyState(systemImage: "list.bullet.rectangle", title: errorsOnly ? "No errors" : "No events", message: "Audit events for this conversation appear here.")
                .magziCard()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(events.reversed().enumerated()), id: \.offset) { index, event in
                    MagziOpsTimelineRow(event: event, isLast: index == events.count - 1)
                }
            }
            .magziCard(padding: MagziDesign.Spacing.m)
        }
    }

    private func pageCard(_ page: MagziSessionTrace.Page) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            Text(MagziOpsFormat.relative(ms: page.ts))
                .font(MagziDesign.Typography.caption)
                .foregroundStyle(MagziDesign.labelTertiary)
            if let input = page.input, !input.isEmpty {
                Label { Text(input).foregroundStyle(MagziDesign.label) } icon: {
                    Image(systemName: "person.fill").foregroundStyle(MagziDesign.labelTertiary)
                }
                .font(MagziDesign.Typography.subheadline)
                .textSelection(.enabled)
            }
            if let reply = page.reply, !reply.isEmpty {
                Label { Text(reply).foregroundStyle(MagziDesign.labelSecondary) } icon: {
                    Image(systemName: "sparkle").foregroundStyle(MagziDesign.mint)
                }
                .font(MagziDesign.Typography.subheadline)
                .lineLimit(8)
                .textSelection(.enabled)
            }
            if let summary = page.summary, !summary.isEmpty {
                DisclosureGroup("Summary") {
                    Text(summary)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(MagziDesign.Typography.footnote)
                .tint(MagziDesign.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magziCard()
    }

    private func usageRow(_ u: MagziSessionTrace.Usage) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
            HStack(spacing: MagziDesign.Spacing.s) {
                MagziStatusDot(MagziOpsStatusMap.dot(u.status ?? "ok"))
                MagziPill(title: u.model ?? "model", tint: MagziDesign.blue)
                Spacer(minLength: 0)
                Text(MagziOpsFormat.clock(ms: u.at))
                    .font(MagziDesign.Typography.mono)
                    .foregroundStyle(MagziDesign.labelTertiary)
            }
            Text("\(MagziOpsFormat.tokens(u.totalTokens)) tokens · \(MagziOpsFormat.tokens(u.inputTokens)) in / \(MagziOpsFormat.tokens(u.outputTokens)) out · \(u.iterations ?? 0) it · \(MagziOpsFormat.cost(u.costTotal))")
                .font(MagziDesign.Typography.footnote)
                .foregroundStyle(MagziDesign.labelSecondary)
                .monospacedDigit()
            if let breakdown = u.contextBreakdown, !breakdown.isEmpty {
                DisclosureGroup("Context breakdown") {
                    VStack(spacing: MagziDesign.Spacing.xs) {
                        ForEach(breakdown) { item in
                            MagziOpsKeyValue(label: item.name, value: MagziOpsFormat.tokens(item.count))
                        }
                    }
                }
                .font(MagziDesign.Typography.footnote)
                .tint(MagziDesign.labelSecondary)
            }
        }
        .padding(.vertical, MagziDesign.Spacing.s)
    }

    private static let placeholder = MagziSessionTrace(
        conversation: "whatsapp:+440000000000",
        pages: [.init(input: "Placeholder input message", reply: "Placeholder reply from Magzi", ts: 1, summary: nil)],
        events: [MagziAuditFrame(time: "", scope: "turn", action: "reply", status: "ok", summary: "Placeholder event")],
        usage: []
    )
}

/// Vertical timeline row for an audit frame.
struct MagziOpsTimelineRow: View {
    let event: MagziAuditFrame
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            MagziStatusDot(MagziOpsStatusMap.dot(event.status))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MagziDesign.Spacing.s) {
                    Text(MagziOpsFormat.clock(event.time))
                        .font(MagziDesign.Typography.mono)
                        .foregroundStyle(MagziDesign.labelTertiary)
                    Text([event.scope, event.action].compactMap { $0 }.joined(separator: " · "))
                        .font(MagziDesign.Typography.mono.weight(.semibold))
                        .foregroundStyle(event.isError ? MagziDesign.rose : MagziDesign.label)
                        .lineLimit(1)
                }
                if let summary = event.summary, !summary.isEmpty {
                    Text(summary)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            .padding(.bottom, MagziDesign.Spacing.m)
            Spacer(minLength: 0)
        }
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(MagziDesign.hairlineStrong)
                    .frame(width: 1)
                    .padding(.top, 18)
                    .padding(.leading, 8.3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
