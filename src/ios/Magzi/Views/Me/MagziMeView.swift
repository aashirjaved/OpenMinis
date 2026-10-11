import SwiftUI

/// Me (spec 4.6). Pushed from More — relies on the caller's NavigationStack.
struct MagziMeView: View {
    @ObservedObject private var hub = MagziHub.shared

    @State private var week: MagziTimeReport?
    @State private var weekError: Error?
    @State private var memoryCount: Int?
    @State private var loaded = false

    private var user: MagziUser? { hub.user }
    private var firstName: String {
        let name = hub.person?.displayName?.magziNonEmpty ?? user?.displayName?.magziNonEmpty ?? "Me"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    var body: some View {
        MeAreaScroll(refresh: load) {
            header
            weekCard
            rowsCard
        }
        .navigationTitle(firstName)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() } // refresh counts after returning from a subscreen
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: MagziDesign.Spacing.m) {
            Text(initials)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(MagziDesign.mint)
                .frame(width: 52, height: 52)
                .background(Circle().fill(MagziDesign.mintSoft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(user?.name ?? "Your account")
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                if let email = user?.email?.magziNonEmpty {
                    Text(email)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: MagziDesign.Spacing.xs) {
                    MagziPill(title: MeAreaFormat.humanize(user?.role ?? "user"),
                              tint: user?.isAdmin == true ? MagziDesign.amber : MagziDesign.labelSecondary)
                    if let person = hub.person {
                        MagziPill(title: "Linked · \(person.displayName?.magziNonEmpty ?? person.personId)",
                                  systemImage: "link", tint: MagziDesign.mint)
                    } else {
                        MagziPill(title: "Not linked", systemImage: "link", tint: MagziDesign.amber)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .magziCard()
        .redacted(reason: user == nil ? .placeholder : [])
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        let parts = (user?.name ?? "?").split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    // MARK: My week

    @ViewBuilder
    private var weekCard: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            MagziSectionHeader("My week")
            if let weekError, week == nil {
                MeAreaErrorCard(error: weekError) { Task { await load() } }
            } else {
                NavigationLink(destination: MeWeekView()) {
                    MeWeekSummary(report: week ?? (loaded ? MagziTimeReport() : MeWeekSummary.placeholder))
                        .redacted(reason: loaded ? [] : .placeholder)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Rows

    private var rowsCard: some View {
        VStack(spacing: 0) {
            link("Memory", "brain", MagziDesign.violet, memoryCount.map { "\($0) things" }) { MeMemoryView() }
            divider
            link("Timeline", "calendar.day.timeline.left", MagziDesign.blue) { MeTimelineView() }
            divider
            link("My week", "chart.bar.xaxis", MagziDesign.mint) { MeWeekView() }
            divider
            link("Places", "mappin.and.ellipse", MagziDesign.rose) { MePlacesView() }
            divider
            link("Activity", "list.bullet.rectangle", MagziDesign.labelSecondary) { MeActivityView() }
            divider
            link("Preferences", "slider.horizontal.3", MagziDesign.amber) { MePreferencesView() }
            divider
            link("Privacy", "hand.raised", MagziDesign.mint) { MePrivacyView() }
            divider
            link("Devices", "iphone", MagziDesign.blue) { MeDevicesView() }
        }
        .magziCard(padding: MagziDesign.Spacing.m)
    }

    private var divider: some View {
        Rectangle().fill(MagziDesign.hairline).frame(height: 1).padding(.leading, 42)
    }

    private func link<D: View>(_ title: String, _ symbol: String, _ tint: Color, _ detail: String? = nil,
                               @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink(destination: destination()) {
            MagziRow(title: title, systemImage: symbol, tint: tint, detail: detail, showsChevron: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: Load

    private func load() async {
        if hub.me == nil { await hub.refresh() }
        async let w: Result<MagziTimeReport, Error> = capture { try await MagziAPI.shared.time() }
        async let m: Result<MagziMemory, Error> = capture { try await MagziAPI.shared.memory() }
        let (wr, mr) = await (w, m)
        switch wr {
        case .success(let r): week = r; weekError = nil
        case .failure(let e) where HhErrors.status(e) == 404: week = MagziTimeReport(); weekError = nil // no ledger yet = empty week
        case .failure(let e): weekError = e
        }
        if case .success(let mem) = mr { memoryCount = (mem.notes?.count ?? 0) + (mem.facts?.count ?? 0) }
        loaded = true
    }

    private func capture<T>(_ body: @MainActor () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }
}

/// Stacked bar + legend for the week (used on Me and My week).
struct MeWeekSummary: View {
    let report: MagziTimeReport

    static let placeholder = MagziTimeReport(
        lines: [
            MagziTimeLine(key: "work", label: "Work", actualMin: 1800, plannedMin: 1900),
            MagziTimeLine(key: "home", label: "Home", actualMin: 600, plannedMin: 500),
            MagziTimeLine(key: "family", label: "Family", actualMin: 400, plannedMin: 400),
        ],
        actualMin: 2800
    )

    private var lines: [MagziTimeLine] { (report.lines ?? []).filter { ($0.actualMin ?? 0) > 0 } }
    private var total: Double { max(1, lines.reduce(0) { $0 + ($1.actualMin ?? 0) }) }

    var body: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            if lines.isEmpty {
                Text("Magzi will learn your week as you share context.")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(lines) { line in
                            Capsule(style: .continuous)
                                .fill(MeAreaCategory.tint(line.key ?? line.label))
                                .frame(width: max(4, (geo.size.width - CGFloat(lines.count * 2)) * CGFloat((line.actualMin ?? 0) / total)))
                        }
                    }
                }
                .frame(height: 12)
                .accessibilityHidden(true)
                ForEach(lines.prefix(5)) { line in
                    HStack(spacing: MagziDesign.Spacing.s) {
                        Circle().fill(MeAreaCategory.tint(line.key ?? line.label)).frame(width: 8, height: 8)
                        Text(line.label ?? line.key ?? "Other")
                            .font(MagziDesign.Typography.subheadline)
                            .foregroundStyle(MagziDesign.label)
                        Spacer()
                        Text(MeAreaFormat.minutes(line.actualMin))
                            .font(MagziDesign.Typography.subheadline.monospacedDigit())
                            .foregroundStyle(MagziDesign.labelSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .magziCard()
    }
}
