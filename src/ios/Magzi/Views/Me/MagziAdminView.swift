import SwiftUI

/// Admin (spec 4.8). Pushed from More (admins only) — relies on the caller's NavigationStack.
struct MagziAdminView: View {
    @State private var status: MagziAdminStatus?
    @State private var error: Error?
    @State private var updatedAt: Date?

    @State private var pauseHours = 12
    @State private var pauseResult: MagziPauseResponse?
    @State private var pausing = false
    @State private var pauseError: String?
    @State private var confirmPause = false

    var body: some View {
        MeAreaScroll(refresh: load) {
            statusSection
            if let s = status?.status {
                metrics(s)
            }
            helperGroups
            linksCard
        }
        .navigationTitle("Admin")
        .navigationBarTitleDisplayMode(.large)
        .task {
            // Refresh every 30 s while visible; `.task` is cancelled on disappear.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        .confirmationDialog("Pause helper groups for \(pauseHours) h?", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("Pause for \(pauseHours) h", role: .destructive) { Task { await pause(on: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Magzi stops posting in household WhatsApp groups. Direct chats keep working.")
        }
    }

    // MARK: Status

    private var overall: (MagziStatus, String) {
        guard let s = status?.status else { return (.off, "Unknown") }
        let wa = (s.whatsappState ?? "").lowercased()
        if wa.contains("error") || wa.contains("down") || wa.contains("logged") || wa.contains("closed") { return (.problem, "Down") }
        if s.pairingQrPending == true || (s.deadLettersToday ?? 0) > 0 || !(wa.contains("open") || wa.contains("connected")) {
            return (.attention, "Degraded")
        }
        return (.ok, "OK")
    }

    @ViewBuilder
    private var statusSection: some View {
        if let error, status == nil {
            MeAreaErrorCard(error: error) { Task { await load() } }
        } else {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                HStack(spacing: MagziDesign.Spacing.s) {
                    MagziStatusDot(overall.0, size: 10)
                    Text(overall.1)
                        .font(MagziDesign.Typography.headline)
                        .foregroundStyle(MagziDesign.label)
                    Spacer()
                    if let updatedAt {
                        Text("Updated \(updatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(MagziDesign.Typography.caption)
                            .foregroundStyle(MagziDesign.labelTertiary)
                    }
                }
                if let error {
                    MeAreaBanner(text: MeAreaFailure.message(error), tint: MagziDesign.amber)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(status?.text?.magziNonEmpty ?? (status == nil ? String(repeating: "status line placeholder\n", count: 6) : "No status text."))
                        .font(MagziDesign.Typography.mono)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(MagziDesign.Spacing.m)
                }
                .background(RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous).fill(MagziDesign.surfaceSecondary))
                Text("Refreshes every 30 s · pull to refresh")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelTertiary)
            }
            .magziCard()
            .redacted(reason: status == nil ? .placeholder : [])
        }
    }

    private func metrics(_ s: MagziAdminStatus.Status) -> some View {
        let columns = [GridItem(.flexible(), spacing: MagziDesign.Spacing.m), GridItem(.flexible(), spacing: MagziDesign.Spacing.m)]
        return VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            MagziSectionHeader("Vitals")
            LazyVGrid(columns: columns, spacing: MagziDesign.Spacing.m) {
                if let up = s.uptimeMs {
                    MagziMetricCard(title: "Uptime", value: MeAreaFormat.duration(ms: up), systemImage: "clock", tint: MagziDesign.mint)
                }
                if let wa = s.whatsappState?.magziNonEmpty {
                    MagziMetricCard(title: "WhatsApp", value: MeAreaFormat.humanize(wa), systemImage: "message",
                                    tint: overall.0 == .ok ? MagziDesign.mint : MagziDesign.amber,
                                    caption: s.whatsappConnectedSince.map { "since \(MeAreaFormat.relative($0))" })
                }
                if let llm = s.llmProvider?.magziNonEmpty {
                    MagziMetricCard(title: "LLM", value: llm, systemImage: "cpu", tint: MagziDesign.violet)
                }
                if let dead = s.deadLettersToday {
                    MagziMetricCard(title: "Dead letters today", value: "\(dead)", systemImage: "tray.full",
                                    tint: dead > 0 ? MagziDesign.rose : MagziDesign.mint)
                }
                if s.lastInboundAt != nil || s.lastOutboundAt != nil {
                    MagziMetricCard(title: "Last inbound", value: MeAreaFormat.relative(s.lastInboundAt), systemImage: "arrow.down.left",
                                    tint: MagziDesign.blue, caption: "Out \(MeAreaFormat.relative(s.lastOutboundAt))")
                }
                if s.lastBackupOkAt != nil {
                    MagziMetricCard(title: "Last backup", value: MeAreaFormat.relative(s.lastBackupOkAt), systemImage: "externaldrive",
                                    tint: MagziDesign.blue)
                }
            }
            if let households = s.households, !households.isEmpty {
                VStack(spacing: MagziDesign.Spacing.m) {
                    ForEach(households) { h in
                        let used = Double(h.tokensToday ?? 0)
                        let budget = Double(max(1, h.budget ?? 0))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(h.name?.magziNonEmpty ?? "Household").font(MagziDesign.Typography.subheadline)
                                Spacer()
                                Text("\(h.tokensToday ?? 0) / \(h.budget ?? 0) tokens")
                                    .font(MagziDesign.Typography.caption.monospacedDigit())
                                    .foregroundStyle(MagziDesign.labelSecondary)
                            }
                            ProgressView(value: min(used / budget, 1))
                                .tint(used / budget > 0.9 ? MagziDesign.rose : MagziDesign.mint)
                        }
                    }
                }
                .magziCard()
            }
            if let latency = s.latency, !latency.isEmpty {
                VStack(spacing: 0) {
                    ForEach(latency) { l in
                        let over = (l.totalP95Ms ?? 0) > (l.budgetMs ?? .infinity)
                        MagziRow(title: l.path?.magziNonEmpty ?? "path",
                                 subtitle: "\(l.turns ?? 0) turns · queue \(Int(l.queueP95Ms ?? 0)) ms · ready \(Int(l.readyP95Ms ?? 0)) ms",
                                 systemImage: "speedometer", tint: over ? MagziDesign.rose : MagziDesign.mint,
                                 detail: "p95 \(Int(l.totalP95Ms ?? 0)) ms")
                    }
                }
                .magziCard(padding: MagziDesign.Spacing.m)
            }
        }
    }

    // MARK: Helper groups

    private var helperGroups: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            MagziSectionHeader("Helper groups")
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                HStack(spacing: MagziDesign.Spacing.m) {
                    MagziIconBadge(systemImage: "pause.circle", tint: MagziDesign.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pauseTitle).font(MagziDesign.Typography.body).foregroundStyle(MagziDesign.label)
                        if let groups = pauseResult?.groups, !groups.isEmpty {
                            Text("\(groups.count) group\(groups.count == 1 ? "" : "s")")
                                .font(MagziDesign.Typography.footnote)
                                .foregroundStyle(MagziDesign.labelSecondary)
                        }
                    }
                }
                Stepper(value: $pauseHours, in: 1...336) {
                    Text("Pause for \(pauseHours) h").monospacedDigit()
                }
                HStack(spacing: MagziDesign.Spacing.s) {
                    Button("Pause") { confirmPause = true }
                        .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.amber, prominent: true))
                    Button("Resume") { Task { await pause(on: false) } }
                        .buttonStyle(MagziCompactButtonStyle())
                    if pausing { ProgressView() }
                }
                .disabled(pausing)
                if let pauseError { MeAreaBanner(text: pauseError) { self.pauseError = nil } }
                Text("Pausing stops Magzi posting in household WhatsApp groups. Direct chats keep working.")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
            }
            .magziCard()
        }
    }

    private var pauseTitle: String {
        guard let r = pauseResult else { return "Helper groups" }
        if r.paused == true, let until = r.until, until > 0 { return "Paused until \(MeAreaFormat.dateTime(until))" }
        return "Helper groups active"
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            NavigationLink(destination: MeAdminPairingView()) {
                MagziRow(title: "WhatsApp pairing", subtitle: status?.status?.pairingQrPending == true ? "A pairing code is waiting" : nil,
                         systemImage: "qrcode", tint: MagziDesign.mint, showsChevron: true)
            }
            .buttonStyle(.plain)
            Rectangle().fill(MagziDesign.hairline).frame(height: 1).padding(.leading, 42)
            NavigationLink(destination: MeAdminUsersView()) {
                MagziRow(title: "Users", systemImage: "person.3", tint: MagziDesign.blue, showsChevron: true)
            }
            .buttonStyle(.plain)
        }
        .magziCard(padding: MagziDesign.Spacing.m)
    }

    // MARK: Actions

    private func load() async {
        do {
            let s = try await MagziAPI.shared.adminStatus()
            withAnimation(MagziDesign.Motion.standard) { status = s }
            updatedAt = Date()
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    private func pause(on: Bool) async {
        pausing = true
        defer { pausing = false }
        do {
            pauseResult = try await MagziAPI.shared.adminPause(on: on, hours: Double(pauseHours))
            pauseError = nil
            on ? MeAreaHaptics.medium() : MeAreaHaptics.success()
        } catch {
            MeAreaHaptics.error()
            pauseError = MeAreaFailure.message(error)
        }
    }
}
