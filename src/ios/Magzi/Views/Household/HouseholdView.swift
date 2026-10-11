import SwiftUI

/// Root of the Household tab (spec 4.3). Owns its NavigationStack.
struct HouseholdView: View {
    @ObservedObject private var hub = MagziHub.shared
    @ObservedObject private var auth = MagziAuthStore.shared
    @ObservedObject private var router = MagziRouter.shared
    @State private var path = NavigationPath()
    @State private var showConnect = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: HhRoute.self) { route in
                    if let id = hub.selectedHousehold?.id {
                        HhRouteView(route: route, householdId: id)
                    }
                }
        }
        .sheet(isPresented: $showConnect) {
            NavigationStack {
                MagziConnectView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showConnect = false } }
                    }
            }
        }
        .sheet(isPresented: $showJoin) { HhJoinSheet() }
        .onChange(of: hub.selectedHouseholdId) { _ in path = NavigationPath() }
        .onAppear { consumeApprovalsLink() }
        .onChange(of: router.showHouseholdApprovals) { _ in consumeApprovalsLink() }
        .onChange(of: hub.selectedHousehold?.id) { _ in consumeApprovalsLink() }
        .onChange(of: auth.isPaired) { paired in
            if paired { showConnect = false }
        }
    }

    /// `magzi://household/approvals` and the chat approvals banner land here.
    private func consumeApprovalsLink() {
        guard router.showHouseholdApprovals, auth.isPaired, hub.selectedHousehold != nil else { return }
        router.showHouseholdApprovals = false
        path = NavigationPath([HhRoute.approvals])
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isPaired {
            MagziEmptyState(
                systemImage: "link",
                title: "Not connected",
                message: "Connect to your home server to see your household.",
                actionTitle: "Connect"
            ) { showConnect = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .magziScreenBackground()
                .navigationTitle("Household")
        } else if let household = hub.selectedHousehold {
            HhOverview(household: household, path: $path)
                .id(household.id)
                .navigationTitle(household.title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar { picker }
        } else if hub.isRefreshing || hub.bootstrap == nil && hub.lastError == nil {
            HhOverviewSkeleton()
                .navigationTitle("Household")
                .task { await hub.start() }
        } else if let error = hub.lastError {
            ScrollView {
                HhErrorCard(message: error) { Task { await hub.refresh() } }
                    .padding(MagziDesign.Spacing.gutter)
            }
            .magziScreenBackground()
            .refreshable { await hub.refresh() }
            .navigationTitle("Household")
        } else {
            ScrollView {
                MagziEmptyState(
                    systemImage: "house",
                    title: "No household yet",
                    message: "Ask someone in your household for an invite code, then join here.",
                    actionTitle: "Join with a code"
                ) { showJoin = true }
                    .padding(.top, MagziDesign.Spacing.xxxl)
            }
            .magziScreenBackground()
            .refreshable { await hub.refresh() }
            .navigationTitle("Household")
        }
    }

    @ToolbarContentBuilder
    private var picker: some ToolbarContent {
        if hub.households.count > 1 {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Picker("Household", selection: Binding(
                        get: { hub.selectedHousehold?.id ?? "" },
                        set: { id in
                            HhHaptics.selection()
                            hub.selectedHouseholdId = id
                        }
                    )) {
                        ForEach(hub.households) { h in
                            Text(h.title).tag(h.id)
                        }
                    }
                } label: {
                    Label("Switch household", systemImage: "chevron.down.circle")
                }
            }
        }
    }
}

/// Maps a route to its screen.
struct HhRouteView: View {
    let route: HhRoute
    let householdId: String

    var body: some View {
        switch route {
        case .items: HhItemsView(householdId: householdId)
        case .item(let item): HhItemDetailView(householdId: householdId, item: item)
        case .rota: HhRotaView(householdId: householdId)
        case .meals: HhMealsView(householdId: householdId)
        case .bills: HhBillsView(householdId: householdId)
        case .approvals: HhApprovalsView(householdId: householdId)
        case .reality: HhRealityView(householdId: householdId)
        case .thread: HhThreadView(householdId: householdId)
        case .facts: HhFactsView(householdId: householdId)
        case .activity: HhActivityView(householdId: householdId)
        case .summary: HhSummaryView(householdId: householdId)
        case .members: HhMembersView(householdId: householdId)
        }
    }
}

// MARK: - Overview

private struct HhOverviewData {
    var reality: MagziReality?
    var items: [MagziItem]?
    var approvals: [MagziApproval]?
    var bills: MagziBills?
    var meals: MagziMeals?
    var rota: MagziRota?
    var presence: [MagziPresence]?
    var errors: [String] = []
}

private struct HhOverview: View {
    let household: MagziHousehold
    @Binding var path: NavigationPath

    @ObservedObject private var hub = MagziHub.shared
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var data: HhOverviewData?
    @State private var loading = false
    @State private var loadError: String?
    @State private var captureText = ""
    @State private var capturing = false
    @State private var captureKey = UUID().uuidString
    @State private var showCapture = false
    @State private var toast: HhToast?
    @State private var decidingId: Int64?
    @State private var approvalNote: String?
    @FocusState private var captureFocused: Bool

    private var hid: String { household.id }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.section) {
                captureField
                if let loadError, data == nil {
                    HhErrorCard(message: loadError) { Task { await load() } }
                } else if let data {
                    loaded(data)
                } else {
                    HhOverviewSkeletonContent()
                }
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.top, MagziDesign.Spacing.s)
            .padding(.bottom, MagziDesign.Spacing.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .magziScreenBackground()
        .refreshable { await load() }
        .task { await load() } // re-runs on every appear, so counts are fresh after popping back
        .hhOnHouseholdChange(hid) { await load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCapture = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add item")
            }
        }
        .sheet(isPresented: $showCapture) {
            HhCaptureSheet(householdId: hid) { _ in Task { await load() } }
        }
        .hhToast($toast)
    }

    // MARK: Sections

    private var captureField: some View {
        HStack(spacing: MagziDesign.Spacing.m) {
            Image(systemName: "plus.circle")
                .foregroundStyle(MagziDesign.mint)
                .font(.system(.body, design: .default, weight: .semibold))
            TextField("Add something for the house…", text: $captureText)
                .focused($captureFocused)
                .submitLabel(.done)
                .onSubmit { Task { await capture() } }
                .disabled(capturing)
            if capturing { ProgressView() }
        }
        .magziCard(padding: 12)
    }

    @ViewBuilder
    private func loaded(_ d: HhOverviewData) -> some View {
        if !d.errors.isEmpty {
            Text(d.errors.joined(separator: "\n"))
                .font(MagziDesign.Typography.footnote)
                .foregroundStyle(MagziDesign.labelSecondary)
        }
        let pending = (d.approvals ?? []).filter(\.isPending)
        if !pending.isEmpty, hub.isAdmin { needsYou(pending) } // only people who can decide get "Needs you"
        if let reality = d.reality { realityCard(reality) }
        grid(d)
        presenceRow(d.presence ?? [])
        sectionLinks(d)
    }

    private func needsYou(_ approvals: [MagziApproval]) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            MagziSectionHeader("Needs you", actionTitle: "See all") { path.append(HhRoute.approvals) }
            VStack(spacing: 0) {
                ForEach(Array(approvals.prefix(3).enumerated()), id: \.element.id) { index, approval in
                    if index > 0 { Divider().padding(.leading, 58) }
                    MagziRow(
                        title: approval.summary?.magziNonEmpty ?? "Approval",
                        subtitle: hub.isAdmin ? "Needs your OK" : "Waiting for an admin",
                        systemImage: "checkmark.shield",
                        tint: MagziDesign.amber
                    ) {
                        if hub.isAdmin {
                            HStack(spacing: 6) {
                                Button("Deny") { Task { await decide(approval, approve: false) } }
                                    .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.labelSecondary))
                                Button("Approve") { Task { await decide(approval, approve: true) } }
                                    .buttonStyle(MagziCompactButtonStyle(prominent: true))
                            }
                            .disabled(decidingId == approval.id)
                        }
                    }
                    .padding(.horizontal, MagziDesign.Spacing.l)
                }
                if let approvalNote {
                    Text(approvalNote)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .padding(MagziDesign.Spacing.l)
                }
            }
            .magziCard(padding: 0)
        }
    }

    private func realityCard(_ r: MagziReality) -> some View {
        let planned = r.household?.planned ?? 0
        let done = r.household?.done ?? 0
        let progress = planned > 0 ? Double(done) / Double(planned) : 0
        let chores = r.fairLoad?.chores ?? []
        let total = chores.reduce(0) { $0 + $1.count }
        return Button { path.append(HhRoute.reality) } label: {
            HStack(spacing: MagziDesign.Spacing.l) {
                ZStack {
                    MagziRing(progress: progress)
                    Text(planned > 0 ? HhFormat.percent(progress) : "—")
                        .font(MagziDesign.Typography.headline)
                        .foregroundStyle(MagziDesign.label)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(planned > 0 ? "\(done) of \(planned) done" : "Nothing planned yet")
                        .font(MagziDesign.Typography.headline)
                        .foregroundStyle(MagziDesign.label)
                    Text("\(r.household?.slipping ?? 0) slipping · \(r.household?.parked ?? 0) parked")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                    if total > 0 {
                        GeometryReader { geo in
                            HStack(spacing: 3) {
                                ForEach(Array(chores.enumerated()), id: \.offset) { i, c in
                                    Capsule()
                                        .fill(HhPalette.color(for: i))
                                        .frame(width: max(4, (geo.size.width - CGFloat(chores.count - 1) * 3) * c.count / total))
                                }
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(MagziDesign.labelTertiary)
            }
            .magziCard()
        }
        .buttonStyle(.plain)
    }

    private func grid(_ d: HhOverviewData) -> some View {
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: MagziDesign.Spacing.m), GridItem(.flexible())]
        let open = (d.items ?? []).filter(\.isOpen)
        let unclaimed = open.filter { ($0.owner ?? "").isEmpty }.count
        let planned = d.reality?.household?.planned ?? 0
        let done = d.reality?.household?.done ?? 0
        let horizon = Date().addingTimeInterval(30 * 86_400).magziMs
        let dueBills = (d.bills?.bills ?? []).filter { ($0.due ?? .max) <= horizon }.sorted { ($0.due ?? 0) < ($1.due ?? 0) }
        let tonight = Self.tonightMeal(d.meals)
        return LazyVGrid(columns: columns, spacing: MagziDesign.Spacing.m) {
            gridLink(.items, MagziMetricCard(
                title: "Open items", value: d.items == nil ? "—" : "\(open.count)",
                systemImage: "checklist", tint: MagziDesign.blue,
                caption: d.items == nil ? "Unavailable" : "\(unclaimed) unclaimed"))
            gridLink(.reality, MagziMetricCard(
                title: "This week",
                value: planned > 0 ? HhFormat.percent(Double(done) / Double(planned)) : "—",
                systemImage: "chart.pie", tint: MagziDesign.mint,
                caption: planned > 0 ? "\(done) of \(planned)" : "Nothing planned"))
            gridLink(.bills, MagziMetricCard(
                title: "Bills", value: d.bills == nil ? "—" : "\(dueBills.count)",
                systemImage: "creditcard", tint: MagziDesign.amber,
                caption: dueBills.first?.due.map { "Next: \(HhFormat.relativeDay($0.magziDate))" } ?? "None due"))
            gridLink(.meals, MagziMetricCard(
                title: "Dinner", value: tonight ?? "—",
                systemImage: "fork.knife", tint: MagziDesign.violet,
                caption: "Tonight"))
        }
    }

    private func gridLink(_ route: HhRoute, _ card: MagziMetricCard) -> some View {
        Button { path.append(route) } label: { card.lineLimit(1).minimumScaleFactor(0.6) }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private func presenceRow(_ presence: [MagziPresence]) -> some View {
        if presence.count > 1 {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("At home")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MagziDesign.Spacing.l) {
                        ForEach(presence) { p in
                            VStack(spacing: 4) {
                                HhAvatar(name: p.name ?? "?", size: 40)
                                if let status = HhPalette.presenceStatus(p.state) {
                                    MagziStatusDot(status, size: 7)
                                } else {
                                    Color.clear.frame(width: 7, height: 7)
                                }
                                Text(p.name ?? "")
                                    .font(MagziDesign.Typography.caption)
                                    .foregroundStyle(MagziDesign.labelSecondary)
                                    .lineLimit(1)
                            }
                            .frame(minWidth: 52)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(p.name ?? ""), \(p.state ?? "unknown")")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func sectionLinks(_ d: HhOverviewData) -> some View {
        let myChore = Self.myChoreToday(d.rota)
        let members = Set((d.rota?.people ?? []) + (d.presence ?? []).compactMap(\.name)).count
        let pending = (d.approvals ?? []).filter(\.isPending).count
        let rows: [(HhRoute, String, String, Color, String?)] = [
            (.items, "Items", "checklist", MagziDesign.blue, d.items.map { "\($0.filter(\.isOpen).count)" }),
            (.rota, "Rota", "arrow.triangle.2.circlepath", MagziDesign.mint, myChore.map { "You: \($0)" }),
            (.meals, "Meals", "fork.knife", MagziDesign.violet, nil),
            (.bills, "Bills", "creditcard", MagziDesign.amber, nil),
            (.approvals, "Approvals", "checkmark.shield", MagziDesign.amber, pending > 0 ? "\(pending)" : nil),
            (.reality, "This week", "chart.pie", MagziDesign.mint, nil),
            (.thread, "Group chat", "bubble.left.and.bubble.right", MagziDesign.blue, nil),
            (.facts, "Facts", "book.closed", MagziDesign.labelSecondary, nil),
            (.activity, "Activity", "clock.arrow.circlepath", MagziDesign.labelSecondary, nil),
            (.summary, "Weekly summary", "doc.richtext", MagziDesign.labelSecondary, "Week \(HhFormat.weekNumber(Date()))"),
            (.members, "Members", "person.2", MagziDesign.labelSecondary, members > 0 ? "\(members)" : nil),
        ]
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider().padding(.leading, 58) }
                Button { path.append(row.0) } label: {
                    MagziRow(title: row.1, systemImage: row.2, tint: row.3, detail: row.4, showsChevron: true)
                        .padding(.horizontal, MagziDesign.Spacing.l)
                }
                .buttonStyle(.plain)
            }
        }
        .magziCard(padding: 0)
    }

    // MARK: Data

    private static func tonightMeal(_ meals: MagziMeals?) -> String? {
        guard let plan = meals?.plan, !plan.isEmpty else { return nil }
        let full = Date().formatted(.dateTime.weekday(.wide)).lowercased()
        let short = Date().formatted(.dateTime.weekday(.abbreviated)).lowercased()
        let match = plan.first { entry in
            let day = (entry.day ?? "").lowercased()
            return day == full || day == short || day.hasPrefix(short) || day == "today" || day == "tonight"
        }
        return match?.meal?.magziNonEmpty
    }

    private static func myChoreToday(_ rota: MagziRota?) -> String? {
        guard let rota else { return nil }
        let cal = Calendar.current
        for week in rota.week ?? [] where HhIdentity.isMe(week.person) {
            if let chore = (week.chores ?? []).first(where: { $0.due.map { cal.isDateInToday($0.magziDate) } ?? false }) {
                return (chore.title ?? "chore") + " today"
            }
        }
        return nil
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let api = MagziAPI.shared
        let id = hid
        async let reality = Self.capture { try await api.reality(householdId: id) }
        async let items = Self.capture { try await api.items(householdId: id) }
        async let approvals = Self.capture { try await api.approvals(householdId: id) }
        async let bills = Self.capture { try await api.bills(householdId: id) }
        async let meals = Self.capture { try await api.meals(householdId: id) }
        async let rota = Self.capture { try await api.rota(householdId: id) }
        async let presence = Self.capture { try await api.presence(householdId: id) }
        let r = await (reality, items, approvals, bills, meals, rota, presence)
        if Task.isCancelled { return }
        var d = HhOverviewData()
        var errors: [Error] = []
        func take<T>(_ result: Result<T, Error>) -> T? {
            switch result {
            case .success(let v): return v
            case .failure(let e): errors.append(e); return nil
            }
        }
        d.reality = take(r.0)
        d.items = take(r.1)
        d.approvals = take(r.2)
        d.bills = take(r.3)
        d.meals = take(r.4)
        d.rota = take(r.5)
        d.presence = take(r.6)
        let real = errors.filter { !HhErrors.isCancellation($0) }
        if real.count == 7 || real.contains(where: { HhErrors.status($0) == 401 }) {
            if data == nil { loadError = HhErrors.message(real[0]) }
            return
        }
        // Only surface failures that aren't plain permission gaps (e.g. presence 409 when unlinked).
        let transport = real.filter { HhErrors.status($0) == nil }
        if let first = transport.first { d.errors = [HhErrors.message(first)] }
        loadError = nil
        withAnimation(MagziDesign.Motion.standard) { data = d }
    }

    private static func capture<T>(_ body: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    private func capture() async {
        let title = captureText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !capturing else { return }
        capturing = true
        defer { capturing = false }
        do {
            _ = try await MagziAPI.shared.captureItem(householdId: hid, title: title, idempotencyKey: captureKey)
            HhHaptics.success()
            captureText = ""
            captureKey = UUID().uuidString
            toast = HhToast(text: "Added “\(title)”")
            await load()
        } catch {
            HhHaptics.error()
            toast = HhToast(text: HhErrors.message(error))
        }
    }

    private func decide(_ approval: MagziApproval, approve: Bool) async {
        decidingId = approval.id
        defer { decidingId = nil }
        do {
            _ = approve ? try await MagziAPI.shared.approve(id: approval.id) : try await MagziAPI.shared.deny(id: approval.id)
            approve ? HhHaptics.success() : HhHaptics.medium()
            approvalNote = nil
            await load()
            await hub.refreshApprovalsCount()
        } catch {
            HhHaptics.error()
            approvalNote = HhErrors.status(error) == 403
                ? "Only household admins can decide approvals. \(HhErrors.message(error))"
                : HhErrors.message(error)
        }
    }
}

// MARK: - Skeleton

private struct HhOverviewSkeleton: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.section) {
                HhOverviewSkeletonContent()
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
        }
        .magziScreenBackground()
    }
}

private struct HhOverviewSkeletonContent: View {
    var body: some View {
        Group {
            HStack(spacing: MagziDesign.Spacing.l) {
                MagziRing(progress: 0.6).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("17 of 25 done").font(MagziDesign.Typography.headline)
                    Text("3 slipping · 2 parked").font(MagziDesign.Typography.footnote)
                }
                Spacer()
            }
            .magziCard()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: MagziDesign.Spacing.m), GridItem(.flexible())], spacing: MagziDesign.Spacing.m) {
                ForEach(0..<4, id: \.self) { _ in
                    MagziMetricCard(title: "Open items", value: "12", systemImage: "checklist", caption: "3 unclaimed")
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    MagziRow(title: "Section row", systemImage: "circle", detail: "4", showsChevron: true)
                        .padding(.horizontal, MagziDesign.Spacing.l)
                }
            }
            .magziCard(padding: 0)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
