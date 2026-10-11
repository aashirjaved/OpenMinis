import Combine
import SwiftUI
import UIKit

/// Home tab: calm landing page — is Magzi OK, what needs me today, how is the house doing.
struct MagziHomeView: View {
    @ObservedObject private var hub = MagziHub.shared
    @ObservedObject private var auth = MagziAuthStore.shared
    @ObservedObject private var router = MagziRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var today: MagziToday?
    @State private var presence: [MagziPresence] = []
    @State private var reality: MagziReality?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var lastLoadedAt: Date?
    @State private var busyIds: Set<String> = []
    @State private var doneIds: Set<Int64> = []
    @State private var actionError: String?
    @State private var undo: ShellUndo?
    @State private var showConnect = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.section) {
                header
                if auth.isPaired {
                    pairedSections
                } else {
                    connectCard
                }
                if !hub.isMinor { adhocCard }
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.top, MagziDesign.Spacing.s)
            .padding(.bottom, 32)
        }
        .magziScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await reload(full: true) }
        .task { await reload(full: false) }
        .onReceive(hub.householdChanged.receive(on: RunLoop.main)) { id in
            guard id == currentHouseholdId else { return }
            Task { await reload(full: false) }
        }
        .onChange(of: hub.selectedHouseholdId) { _ in Task { await reload(full: false) } }
        .onChange(of: auth.isPaired) { paired in
            if paired {
                showConnect = false
                Task { await hub.refresh(); await reload(full: false) }
            } else {
                today = nil; presence = []; reality = nil; loadError = nil
            }
        }
        .sheet(isPresented: $showConnect) {
            NavigationStack {
                MagziConnectView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showConnect = false }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .overlay(alignment: .bottom) { undoToast }
    }

    private var currentHouseholdId: String? { hub.selectedHousehold?.id }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                Text(greeting)
                    .font(MagziDesign.Typography.display)
                    .foregroundStyle(MagziDesign.label)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    MagziStatusDot(statusLine.status)
                    Text(statusLine.text)
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
            if auth.isPaired {
                NavigationLink {
                    MagziMeView()
                } label: {
                    Text(initial)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(MagziDesign.label)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(MagziDesign.surfaceSecondary))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Me")
            }
        }
        .padding(.top, MagziDesign.Spacing.s)
    }

    private var firstName: String? {
        guard hub.isPaired else { return nil } // no stale name after sign-out
        let raw = hub.person?.displayName ?? hub.user?.displayName ?? ""
        return raw.split(separator: " ").first.map(String.init)
    }

    private var initial: String {
        (firstName ?? hub.user?.name ?? "M").prefix(1).uppercased()
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        if let firstName { return "Good \(part), \(firstName)" }
        return "Good \(part)"
    }

    private var statusLine: (status: MagziStatus, text: String) {
        switch hub.status {
        case .unpaired:
            return (.off, "Not connected to Magzi")
        case .connecting:
            return (.attention, "Reconnecting…")
        case .offline:
            return (.off, "Magzi is offline · showing last update")
        case .online:
            let n = hub.pendingApprovalsCount
            if n > 0 { return (.attention, "Magzi is here · \(n) \(n == 1 ? "thing needs" : "things need") you") }
            return (.live, "Magzi is here · all quiet")
        }
    }

    // MARK: Paired

    @ViewBuilder
    private var pairedSections: some View {
        askEntry
        if let loadError, today == nil {
            ShellErrorCard(message: loadError) { Task { await reload(full: true) } }
        } else if !isLoading, today == nil, hub.households.isEmpty, hub.status.isOnline {
            MagziEmptyState(
                systemImage: "house",
                title: "No household yet",
                message: "Ask your admin to add you to a household, or accept an invite in Household."
            )
            .magziCard()
        } else {
            todaySection
            presenceSection
            realitySection
        }
        if !hub.isMinor { capabilitiesStrip } // the starter questions are adult capabilities
        if let lastLoadedAt, case .offline = hub.status {
            Text("Updated \(lastLoadedAt.formatted(.relative(presentation: .named)))")
                .font(MagziDesign.Typography.footnote)
                .foregroundStyle(MagziDesign.labelTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private var askEntry: some View {
        HStack(spacing: MagziDesign.Spacing.m) {
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                router.startDictation = true // focuses the Magzi composer
                router.tab = .magzi
            } label: {
                HStack(spacing: MagziDesign.Spacing.m) {
                    Image(systemName: "sparkle")
                        .font(.system(.body, design: .default, weight: .semibold))
                        .foregroundStyle(MagziDesign.mint)
                    Text("Ask Magzi anything…")
                        .font(MagziDesign.Typography.body)
                        .foregroundStyle(MagziDesign.labelTertiary)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ask Magzi anything")

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                router.startDictation = true
                router.tab = .magzi
            } label: {
                Image(systemName: "mic")
                    .font(.system(.body))
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dictate to Magzi")
        }
        .padding(.leading, MagziDesign.Spacing.l)
        .padding(.trailing, MagziDesign.Spacing.xs)
        .frame(height: 52)
        .magziCard(padding: 0)
    }

    // MARK: Today

    private enum TodayRow: Identifiable {
        case approval(MagziApproval)
        case chore(MagziToday.RotaEntry)
        case item(MagziItem)
        case likely(MagziItem)
        case bill(MagziBill)

        var id: String {
            switch self {
            case .likely(let i): return "l\(i.id)"
            case .approval(let a): return "a\(a.id)"
            case .chore(let c): return "c\(c.id)"
            case .item(let i): return "i\(i.id)"
            case .bill(let b): return "b\(b.id)"
            }
        }
    }

    private var myNames: Set<String> {
        Set([hub.person?.displayName, hub.user?.displayName, firstName].compactMap { $0?.lowercased() }.filter { !$0.isEmpty })
    }

    private func isMine(_ name: String?) -> Bool {
        guard let name = name?.lowercased(), !name.isEmpty else { return false }
        return myNames.contains(name) || myNames.contains(where: { name.hasPrefix($0) })
    }

    private var todayRows: [TodayRow] {
        guard let today else { return [] }
        var rows: [TodayRow] = hub.canDecide ? today.approvals.map { .approval($0) } : []
        let chores = today.rotaToday.filter { !doneIds.contains($0.chore.itemId) }
        let mine = chores.filter { isMine($0.person) }
        rows += (myNames.isEmpty ? chores : mine).map { .chore($0) }
        let items = today.dueToday.filter { !doneIds.contains($0.id) && ($0.owner == nil || isMine($0.owner)) }
        let choreIds = Set(chores.map(\.chore.itemId))
        rows += items.filter { !choreIds.contains($0.id) }.map { .item($0) }
        // Said done, not confirmed: a kid sees it's waiting on a grown-up; a grown-up can confirm.
        let likely = today.likely.filter { !doneIds.contains($0.id) }
        rows += (hub.isMinor ? likely.filter { isMine($0.owner) } : likely.filter { !isMine($0.owner) }).map { .likely($0) }
        let soon = Date().addingTimeInterval(3 * 86_400).magziMs
        rows += today.billsDueSoon.filter { ($0.due ?? .max) <= soon }.map { .bill($0) }
        return rows
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            MagziSectionHeader("Today", actionTitle: "Household") { router.tab = .household }
            Group {
                if today == nil {
                    todaySkeleton
                } else {
                    todayCard
                }
            }
            if let actionError {
                Text(actionError)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.rose)
                    .padding(.horizontal, MagziDesign.Spacing.xs)
            }
        }
    }

    private var todaySkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                if index > 0 { insetDivider }
                MagziRow(title: "Placeholder chore title", subtitle: "Today · you", systemImage: "checklist", tint: MagziDesign.labelTertiary)
                    .padding(.horizontal, MagziDesign.Spacing.l)
            }
        }
        .magziCard(padding: 0)
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading today")
    }

    private var todayCard: some View {
        let rows = todayRows
        let visible = Array(rows.prefix(5))
        return VStack(spacing: 0) {
            if rows.isEmpty {
                VStack(spacing: MagziDesign.Spacing.s) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(.title2))
                        .foregroundStyle(MagziDesign.mint)
                    Text("Nothing needs you today.")
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(MagziDesign.Spacing.xl)
                // A quiet day still shows what's next, so Home is never a dead end.
                let next = (today?.upcoming ?? []).filter { isMine($0.owner) }.prefix(3)
                if !next.isEmpty {
                    insetDivider
                    Text("Next up")
                        .font(MagziDesign.Typography.eyebrow)
                        .foregroundStyle(MagziDesign.labelTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, MagziDesign.Spacing.l)
                        .padding(.top, MagziDesign.Spacing.s)
                    ForEach(Array(next), id: \.id) { item in
                        todayRow(.item(item))
                            .padding(.horizontal, MagziDesign.Spacing.l)
                    }
                }
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { insetDivider }
                    todayRow(row)
                        .padding(.horizontal, MagziDesign.Spacing.l)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
                if rows.count > visible.count {
                    insetDivider
                    Button { router.tab = .household } label: {
                        MagziRow(title: "\(rows.count - visible.count) more in Household", showsChevron: true)
                            .padding(.horizontal, MagziDesign.Spacing.l)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .magziCard(padding: 0)
        .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: rows.map(\.id))
    }

    private var insetDivider: some View {
        Rectangle()
            .fill(MagziDesign.hairline)
            .frame(height: 1)
            .padding(.leading, 58)
    }

    @ViewBuilder
    private func todayRow(_ row: TodayRow) -> some View {
        switch row {
        case .approval(let approval):
            MagziRow(
                title: approval.summary?.magziNonEmpty ?? approval.kind ?? "Approval",
                subtitle: hub.canDecide ? "Needs your OK" : "Waiting for a grown-up",
                systemImage: "checkmark.shield",
                tint: MagziDesign.amber
            ) {
                if hub.canDecide {
                    HStack(spacing: 6) {
                        Button("Deny") { Task { await decide(approval, approve: false) } }
                            .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.labelSecondary))
                        Button("Approve") { Task { await decide(approval, approve: true) } }
                            .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.mint, prominent: true))
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .disabled(busyIds.contains(row.id))
                }
            }
        case .chore(let entry):
            MagziRow(
                title: entry.chore.title ?? "Chore",
                subtitle: isMine(entry.person) ? "Today · you" : "Today · \(entry.person)",
                systemImage: "arrow.triangle.2.circlepath",
                tint: MagziDesign.mint
            ) {
                ShellCheckButton(done: doneIds.contains(entry.chore.itemId)) {
                    Task { await complete(itemId: entry.chore.itemId, rowId: row.id, title: entry.chore.title ?? "Chore", undoable: false) }
                }
                .disabled(busyIds.contains(row.id))
            }
        case .item(let item):
            MagziRow(
                title: item.title ?? "Item",
                subtitle: item.owner == nil ? "Unclaimed" : dueText(item.dueDate, overdue: item.isOverdue),
                systemImage: "checklist",
                tint: MagziDesign.blue
            )
            .contextMenu {
                Button { Task { await complete(itemId: item.id, rowId: row.id, title: item.title ?? "Item", undoable: (item.repeat ?? "").isEmpty) } } label: {
                    Label("Done", systemImage: "checkmark")
                }
                if item.owner == nil {
                    Button { Task { await claim(item, rowId: row.id) } } label: {
                        Label("Claim", systemImage: "hand.raised")
                    }
                }
            }
        case .likely(let item):
            MagziRow(
                title: item.title ?? "Item",
                subtitle: hub.isMinor ? "You said it's done · a grown-up confirms" : "\(item.owner?.magziNonEmpty ?? "Someone") says it's done",
                systemImage: "hourglass",
                tint: MagziDesign.amber
            ) {
                if !hub.isMinor {
                    Button("Confirm") { Task { await complete(itemId: item.id, rowId: row.id, title: item.title ?? "Item", undoable: false) } }
                        .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.mint, prominent: true))
                        .lineLimit(1)
                        .fixedSize()
                        .disabled(busyIds.contains(row.id))
                }
            }
        case .bill(let bill):
            MagziRow(
                title: bill.title ?? "Bill",
                systemImage: "creditcard",
                tint: MagziDesign.amber,
                detail: [bill.amount?.magziNonEmpty, bill.dueDate.map { $0.formatted(.dateTime.weekday(.abbreviated)) }]
                    .compactMap { $0 }.joined(separator: " · ")
            )
        }
    }

    private func dueText(_ date: Date?, overdue: Bool) -> String {
        guard let date else { return "No due date" }
        if overdue { return "Overdue" }
        if Calendar.current.isDateInToday(date) { return "Due today" }
        if Calendar.current.isDateInTomorrow(date) { return "Due tomorrow" }
        // A bare weekday is only unambiguous inside the coming week.
        if date.timeIntervalSinceNow > 6 * 86_400 {
            return "Due \(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
        }
        return "Due \(date.formatted(.dateTime.weekday(.abbreviated)))"
    }

    // MARK: Presence

    @ViewBuilder
    private var presenceSection: some View {
        if presence.count > 1 {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("At home")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MagziDesign.Spacing.l) {
                        ForEach(presence) { member in
                            ShellPresenceChip(member: member)
                        }
                    }
                    .padding(.horizontal, MagziDesign.Spacing.xs)
                }
            }
        }
    }

    // MARK: Reality

    @ViewBuilder
    private var realitySection: some View {
        if let totals = reality?.household, (totals.planned ?? 0) > 0 {
            let planned = totals.planned ?? 0
            let done = totals.done ?? 0
            let progress = Double(done) / Double(max(planned, 1))
            Button { router.tab = .household } label: {
                HStack(spacing: MagziDesign.Spacing.l) {
                    ZStack {
                        MagziRing(progress: progress)
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(MagziDesign.Typography.headline)
                            .foregroundStyle(MagziDesign.label)
                            .monospacedDigit()
                    }
                    .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: MagziDesign.Spacing.xs) {
                        Text("\(done) of \(planned) done")
                            .font(MagziDesign.Typography.headline)
                            .foregroundStyle(MagziDesign.label)
                        Text("\(totals.slipping ?? reality?.slipping?.count ?? 0) slipping · \(totals.parked ?? reality?.parked?.count ?? 0) parked")
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.labelSecondary)
                        ShellFairLoadBar(shares: reality?.fairLoad?.chores ?? [])
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(MagziDesign.labelTertiary)
                }
                .magziCard()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("This week: \(done) of \(planned) done")
        }
    }

    // MARK: Capabilities

    private var capabilitiesStrip: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                MagziSectionHeader("Ask about")
                NavigationLink("All") { MagziCapabilitiesView().navigationTitle("Capabilities") }
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.mint)
                    .padding(.trailing, MagziDesign.Spacing.xs)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MagziDesign.Spacing.s) {
                    ForEach(ShellQuickTile.all) { tile in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            router.askMagzi(tile.prompt)
                        } label: {
                            VStack(spacing: MagziDesign.Spacing.s) {
                                MagziIconBadge(systemImage: tile.systemImage, tint: tile.tint, size: 36)
                                Text(tile.title)
                                    .font(MagziDesign.Typography.caption)
                                    .foregroundStyle(MagziDesign.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(width: 72, height: 84)
                            .magziCard(padding: 0, radius: MagziDesign.Radius.control + 2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens Magzi chat with a starter question")
                    }
                }
                .padding(.horizontal, MagziDesign.Spacing.xs)
                .padding(.vertical, MagziDesign.Spacing.xs)
            }
        }
    }

    // MARK: Ad-hoc + Connect

    private var adhocCard: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            router.startAdhocTask()
        } label: {
            MagziRow(
                title: "Start a task",
                subtitle: "On-device agent · runs through 9router",
                systemImage: "sparkles",
                tint: MagziDesign.violet,
                showsChevron: true
            )
            .padding(.horizontal, MagziDesign.Spacing.l)
            .magziCard(padding: 0)
        }
        .buttonStyle(.plain)
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                MagziIconBadge(systemImage: "house", size: 44)
                Text("Connect to Magzi")
                    .font(MagziDesign.Typography.title)
                    .foregroundStyle(MagziDesign.label)
                Text("Your household's assistant runs on your home server. Sign in with the email your admin added.")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect") { showConnect = true }
                    .buttonStyle(MagziPrimaryButtonStyle())
                    .padding(.top, MagziDesign.Spacing.xs)
            }
            .magziCard(padding: 20)
            Text("No server? You can still use Ad-hoc below.")
                .font(MagziDesign.Typography.footnote)
                .foregroundStyle(MagziDesign.labelTertiary)
                .padding(.horizontal, MagziDesign.Spacing.xs)
        }
    }

    // MARK: Undo toast

    @ViewBuilder
    private var undoToast: some View {
        if let undo {
            HStack(spacing: MagziDesign.Spacing.m) {
                Text(undo.message)
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.label)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Undo") { Task { await performUndo(undo) } }
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(MagziDesign.mint)
            }
            .padding(.horizontal, MagziDesign.Spacing.l)
            .padding(.vertical, MagziDesign.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(MagziDesign.surfaceElevated)
            )
            .magziShadow(MagziDesign.Shadows.floating)
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.bottom, MagziDesign.Spacing.m)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .task(id: undo.id) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if self.undo?.id == undo.id {
                    withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) { self.undo = nil }
                }
            }
        }
    }

    // MARK: Loading + actions

    private func reload(full: Bool) async {
        guard auth.isPaired else { return }
        if full || hub.households.isEmpty { await hub.refresh() }
        guard let id = currentHouseholdId else {
            if let error = hub.lastError, today == nil { loadError = Self.friendly(error) }
            return
        }
        isLoading = true
        defer { isLoading = false }
        async let todayResult: Result<MagziToday, Error> = {
            do { return .success(try await MagziHub.shared.today(householdId: id)) } catch { return .failure(error) }
        }()
        async let presenceResult = try? MagziAPI.shared.presence(householdId: id)
        async let realityResult = try? MagziAPI.shared.reality(householdId: id)
        let (t, p, r) = await (todayResult, presenceResult, realityResult)
        switch t {
        case .success(let snapshot):
            today = snapshot
            doneIds = []
            loadError = nil
            lastLoadedAt = Date()
        case .failure(let error):
            loadError = Self.friendly(error.localizedDescription)
        }
        if let p { presence = p }
        if let r { reality = r }
        if full { await hub.refreshApprovalsCount() }
    }

    private static func friendly(_ raw: String) -> String {
        "Couldn't reach Magzi. Check you're on the home network or Tailscale."
    }

    private func decide(_ approval: MagziApproval, approve: Bool) async {
        let rowId = "a\(approval.id)"
        busyIds.insert(rowId)
        defer { busyIds.remove(rowId) }
        do {
            if approve { _ = try await MagziAPI.shared.approve(id: approval.id) } else { _ = try await MagziAPI.shared.deny(id: approval.id) }
            if approve {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) {
                today?.approvals.removeAll { $0.id == approval.id }
            }
            actionError = nil
            await hub.refreshApprovalsCount()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            if case .http(let status, _)? = error as? MagziError, status == 403 {
                actionError = "Only an admin can decide this."
            } else {
                actionError = "Couldn't send that. Try again."
            }
        }
    }

    /// `undoable` is false for recurring items: the server rolls them forward and keeps them open, so /reopen 409s.
    private func complete(itemId: Int64, rowId: String, title: String, undoable: Bool) async {
        guard let householdId = currentHouseholdId else { return }
        busyIds.insert(rowId)
        defer { busyIds.remove(rowId) }
        do {
            _ = try await MagziAPI.shared.updateItem(id: itemId, householdId: householdId, action: "done")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) {
                doneIds.insert(itemId)
                if undoable { undo = ShellUndo(message: "Marked “\(title)” done", itemId: itemId, householdId: householdId) }
            }
            actionError = nil
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            actionError = "Couldn't mark that done. Try again."
        }
    }

    private func claim(_ item: MagziItem, rowId: String) async {
        guard let householdId = currentHouseholdId else { return }
        busyIds.insert(rowId)
        defer { busyIds.remove(rowId) }
        do {
            _ = try await MagziAPI.shared.updateItem(id: item.id, householdId: householdId, action: "claim")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            actionError = nil
            await reload(full: false)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            actionError = "Couldn't claim that. Try again."
        }
    }

    private func performUndo(_ pending: ShellUndo) async {
        withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) { undo = nil }
        do {
            _ = try await MagziAPI.shared.reopenItem(id: pending.itemId, householdId: pending.householdId)
            withAnimation(reduceMotion ? nil : MagziDesign.Motion.standard) { _ = doneIds.remove(pending.itemId) }
            await reload(full: false)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            actionError = "Couldn't undo. Try again."
        }
    }
}

// MARK: - Shell helpers

private struct ShellUndo: Equatable {
    let id = UUID()
    let message: String
    let itemId: Int64
    let householdId: String
}

/// 28pt circular check: circle → checkmark.circle.fill with a small spring.
private struct ShellCheckButton: View {
    let done: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(done ? MagziDesign.mint : MagziDesign.labelTertiary)
                .scaleEffect(done ? 1 : 0.95)
                .animation(reduceMotion ? nil : MagziDesign.Motion.standard, value: done)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "Done" : "Mark done")
    }
}

private struct ShellPresenceChip: View {
    let member: MagziPresence

    private var dotColor: Color? {
        switch member.state?.lowercased() {
        case "home": return MagziDesign.mint
        case "away": return MagziDesign.amber
        case nil, "", "unknown": return nil
        default: return MagziDesign.labelTertiary
        }
    }

    private var stateLabel: String {
        switch member.state?.lowercased() {
        case "home": return "home"
        case "away": return "away"
        case nil, "", "unknown": return "unknown"
        default: return "out"
        }
    }

    var body: some View {
        VStack(spacing: MagziDesign.Spacing.xs) {
            Text((member.name ?? "?").prefix(1).uppercased())
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(MagziDesign.label)
                .frame(width: 40, height: 40)
                .background(Circle().fill(MagziDesign.surfaceSecondary))
                .overlay(alignment: .bottomTrailing) {
                    if let dotColor {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(MagziDesign.background, lineWidth: 2))
                    }
                }
            Text(member.name ?? "Someone")
                .font(MagziDesign.Typography.caption)
                .foregroundStyle(MagziDesign.labelSecondary)
                .lineLimit(1)
        }
        .frame(minWidth: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(member.name ?? "Someone"), \(stateLabel)")
    }
}

/// One 6pt capsule per member, widths proportional to their share of chores.
private struct ShellFairLoadBar: View {
    let shares: [MagziNamedCount]
    private static let palette: [Color] = [MagziDesign.mint, MagziDesign.blue, MagziDesign.violet, MagziDesign.amber]

    var body: some View {
        let total = shares.reduce(0) { $0 + max($1.count, 0) }
        if total > 0 {
            GeometryReader { proxy in
                let spacing: CGFloat = 3
                let usable = max(proxy.size.width - spacing * CGFloat(max(shares.count - 1, 0)), 0)
                HStack(spacing: spacing) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                        Capsule(style: .continuous)
                            .fill(Self.palette[index % Self.palette.count])
                            .frame(width: usable * CGFloat(max(share.count, 0) / total))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Fair load: " + shares.map { "\($0.name) \(Int($0.count))" }.joined(separator: ", "))
        }
    }
}

/// Inline error card used by Shell screens.
struct ShellErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            MagziStatusDot(.problem)
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                Text(message)
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.label)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: retry)
                    .buttonStyle(MagziCompactButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .magziCard()
    }
}

/// Home quick strip — six starters from the Capabilities catalogue (spec §4.7).
private struct ShellQuickTile: Identifiable {
    let title: String
    let systemImage: String
    let tint: Color
    let prompt: String
    var id: String { title }

    static let all: [ShellQuickTile] = [
        .init(title: "Agenda", systemImage: "calendar", tint: MagziDesign.blue,
              prompt: "What's on my agenda today? Include calendar events, reminders, chores and anything due."),
        .init(title: "Weather", systemImage: "cloud.sun", tint: MagziDesign.blue,
              prompt: "What's the weather today and tomorrow where I am? Anything I should plan around?"),
        .init(title: "Portfolio", systemImage: "chart.line.uptrend.xyaxis", tint: MagziDesign.mint,
              prompt: "Give me a quick portfolio check: total value, today's move, and anything unusual."),
        .init(title: "Research", systemImage: "magnifyingglass", tint: MagziDesign.violet,
              prompt: "Research this for me and come back with a short brief and sources: "),
        .init(title: "Gmail", systemImage: "envelope", tint: MagziDesign.rose,
              prompt: "Summarise my unread email. Flag anything that needs a reply today."),
        .init(title: "Home", systemImage: "lightbulb", tint: MagziDesign.amber,
              prompt: "What's the state of the house right now? Lights, heating, doors."),
    ]
}
