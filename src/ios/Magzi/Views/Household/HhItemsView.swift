import SwiftUI

// MARK: - Item actions

/// Shared mutation logic for item rows / detail / reality.
@MainActor
enum HhItemActions {
    /// done | drop | claim (PATCH /items/:id).
    static func update(_ id: Int64, householdId: String, action: String) async throws -> MagziItem? {
        try await MagziAPI.shared.updateItem(id: id, householdId: householdId, action: action)
    }

    /// drop | park | schedule(when) | delegate(to) | reopen (POST /items/:id/progress).
    static func progress(_ id: Int64, householdId: String, action: String, to: String? = nil, when: Date? = nil) async throws -> MagziItem? {
        try await MagziAPI.shared.progressItem(
            id: id, householdId: householdId, action: action,
            to: to, when: when.map(HhFormat.whenString)
        )
    }

    /// `/reopen` targets inferred closures; falls back to `progress {action: reopen}`.
    static func reopen(_ id: Int64, householdId: String) async throws {
        do {
            _ = try await MagziAPI.shared.reopenItem(id: id, householdId: householdId)
        } catch {
            if HhErrors.isCancellation(error) { throw error }
            _ = try await MagziAPI.shared.progressItem(id: id, householdId: householdId, action: "reopen")
        }
    }

    static func subtitle(_ item: MagziItem) -> String? {
        var parts: [String] = []
        if let owner = item.owner?.magziNonEmpty {
            parts.append(item.isOpen ? "Claimed by \(owner)" : owner)
        } else if item.isOpen {
            parts.append("Unclaimed")
        }
        if let due = HhFormat.due(item.dueAt, hasTime: item.dueHasTime ?? false) {
            parts.append(item.isOverdue ? "overdue \(due)" : "due \(due)")
        }
        if let kind = item.kind, kind != "task" { parts.append(kind) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Items list

struct HhItemsView: View {
    @ObservedObject private var hub = MagziHub.shared
    let householdId: String

    private enum Filter: String, CaseIterable, Identifiable {
        case open = "Open", mine = "Mine", shopping = "Shopping", decisions = "Decisions"
        var id: String { rawValue }
        var view: MagziItemsView {
            switch self {
            case .open: return .open
            case .mine: return .mine
            case .shopping: return .shopping
            case .decisions: return .decisions
            }
        }
    }

    @State private var filter: Filter = .open
    @State private var items: [MagziItem]?
    @State private var recentlyDone: [MagziItem] = []
    @State private var error: String?
    @State private var search = ""
    @State private var toast: HhToast?
    @State private var moreItem: MagziItem?
    @State private var scheduleItem: MagziItem?
    @State private var delegateItem: MagziItem?
    @State private var showCapture = false

    var body: some View {
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let error, items == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let items {
                content(items)
            } else {
                Section {
                    ForEach(0..<6, id: \.self) { _ in
                        MagziRow(title: "Loading item title", subtitle: "Unclaimed · due Fri", systemImage: "circle")
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .hhListChrome()
        .searchable(text: $search, prompt: "Search items")
        .navigationTitle("Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCapture = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add item")
            }
        }
        .refreshable { await load() }
        .task(id: filter) { await load() }
        .onChange(of: filter) { _ in HhHaptics.selection() }
        .hhOnHouseholdChange(householdId) { await load() }
        .confirmationDialog(moreItem?.title ?? "Item", isPresented: Binding(get: { moreItem != nil }, set: { if !$0 { moreItem = nil } }), titleVisibility: .visible, presenting: moreItem) { item in
            Button("Park") { Task { await progress(item, "park") } }
            Button("Schedule…") { scheduleItem = item }
            if !hub.isChild { Button("Delegate…") { delegateItem = item } }
            Button("Drop", role: .destructive) { Task { await progress(item, "drop") } }
        } message: { _ in
            Text("Drop stops Magzi tracking it.")
        }
        .sheet(item: $scheduleItem) { item in
            HhDateSheet(title: "Schedule") { date in Task { await progress(item, "schedule", when: date) } }
        }
        .sheet(item: $delegateItem) { item in
            HhMemberPicker(title: "Delegate to", householdId: householdId) { name in
                Task { await progress(item, "delegate", to: name) }
            }
        }
        .sheet(isPresented: $showCapture) {
            HhCaptureSheet(householdId: householdId) { _ in Task { await load() } }
        }
        .hhToast($toast)
    }

    @ViewBuilder
    private func content(_ items: [MagziItem]) -> some View {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let visible = q.isEmpty ? items : items.filter {
            ($0.title ?? "").lowercased().contains(q) || ($0.owner ?? "").lowercased().contains(q)
        }
        let groups = Self.group(visible)
        if groups.isEmpty && recentlyDone.isEmpty {
            Section {
                MagziEmptyState(
                    systemImage: "checkmark.circle",
                    title: q.isEmpty ? "All clear" : "No matches",
                    message: q.isEmpty ? emptyMessage : "Nothing matches “\(search)”."
                )
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        }
        ForEach(groups, id: \.title) { group in
            Section(group.title) {
                ForEach(group.items) { item in row(item) }
            }
        }
        if !recentlyDone.isEmpty {
            Section("Done just now") {
                ForEach(recentlyDone) { item in
                    MagziRow(title: item.title ?? "Item", subtitle: "Done", systemImage: "checkmark.circle.fill", tint: MagziDesign.mint)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .swipeActions(edge: .trailing) {
                            Button("Reopen") { Task { await reopen(item) } }
                                .tint(MagziDesign.blue)
                        }
                }
            }
        }
    }

    private var emptyMessage: String {
        switch filter {
        case .open: return "Nothing open for the house."
        case .mine: return "Nothing on your plate."
        case .shopping: return "The shopping list is empty."
        case .decisions: return "No decisions waiting."
        }
    }

    private func row(_ item: MagziItem) -> some View {
        NavigationLink(value: HhRoute.item(item)) {
            HStack(spacing: MagziDesign.Spacing.m) {
                Button {
                    Task { await done(item) }
                } label: {
                    Image(systemName: canAct(item) ? "circle" : "lock.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(item.isOverdue ? MagziDesign.amber : MagziDesign.labelTertiary)
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!canAct(item))
                .accessibilityLabel(canAct(item) ? "Mark done" : "A grown-up finishes this one")
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Untitled")
                        .font(MagziDesign.Typography.body)
                        .foregroundStyle(MagziDesign.label)
                    if let subtitle = HhItemActions.subtitle(item) {
                        Text(subtitle)
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(item.isOverdue ? MagziDesign.amber : MagziDesign.labelSecondary)
                    }
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if canAct(item) {
                Button { Task { await done(item) } } label: { Label("Done", systemImage: "checkmark") }
                    .tint(MagziDesign.mint)
            }
        }
        .swipeActions(edge: .trailing) {
            if canAct(item) {
                Button { moreItem = item } label: { Label("More", systemImage: "ellipsis") }
                    .tint(.gray)
            }
            if (item.owner ?? "").isEmpty {
                Button { Task { await claim(item) } } label: { Label("Claim", systemImage: "hand.raised") }
                    .tint(MagziDesign.blue)
            }
        }
        .contextMenu {
            if canAct(item) {
                Button { Task { await done(item) } } label: { Label("Done", systemImage: "checkmark") }
            }
            if (item.owner ?? "").isEmpty {
                Button { Task { await claim(item) } } label: { Label("Claim", systemImage: "hand.raised") }
            }
            if canAct(item) {
                Button { Task { await progress(item, "park") } } label: { Label("Park", systemImage: "parkingsign") }
                Button { scheduleItem = item } label: { Label("Schedule…", systemImage: "calendar") }
                if !hub.isChild {
                    Button { delegateItem = item } label: { Label("Delegate…", systemImage: "person.crop.circle.badge.plus") }
                }
                Button(role: .destructive) { Task { await progress(item, "drop") } } label: { Label("Drop", systemImage: "trash") }
            }
        }
    }

    /// A child can only change unclaimed items and their own (the daemon refuses the rest).
    private func canAct(_ item: MagziItem) -> Bool {
        guard hub.isChild else { return true }
        let owner = (item.owner ?? "").lowercased()
        return owner.isEmpty || hub.myNames.contains(owner) || hub.myNames.contains { owner.hasPrefix($0) }
    }

    // MARK: Grouping

    private struct ItemGroup { var title: String; var items: [MagziItem] }

    private static func group(_ items: [MagziItem]) -> [ItemGroup] {
        var unclaimed: [MagziItem] = [], claimed: [MagziItem] = [], parked: [MagziItem] = []
        var other: [String: [MagziItem]] = [:]
        for item in items {
            switch item.status ?? "open" {
            case "open":
                if (item.owner ?? "").isEmpty { unclaimed.append(item) } else { claimed.append(item) }
            case "someday", "parked":
                parked.append(item)
            case let s:
                other[HhFormat.capitalized(s), default: []].append(item)
            }
        }
        let byDue: (MagziItem, MagziItem) -> Bool = { ($0.dueAt ?? .max) < ($1.dueAt ?? .max) }
        var groups: [ItemGroup] = []
        if !unclaimed.isEmpty { groups.append(ItemGroup(title: "Unclaimed", items: unclaimed.sorted(by: byDue))) }
        if !claimed.isEmpty { groups.append(ItemGroup(title: "Claimed", items: claimed.sorted(by: byDue))) }
        if !parked.isEmpty { groups.append(ItemGroup(title: "Parked", items: parked)) }
        for key in other.keys.sorted() { groups.append(ItemGroup(title: key, items: other[key] ?? [])) }
        return groups
    }

    // MARK: Actions

    private func load() async {
        do {
            let list = try await MagziAPI.shared.items(householdId: householdId, view: filter.view)
            withAnimation(MagziDesign.Motion.standard) { items = list }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }

    private func remove(_ item: MagziItem) {
        withAnimation(MagziDesign.Motion.standard) { items?.removeAll { $0.id == item.id } }
    }

    private func done(_ item: MagziItem) async {
        do {
            _ = try await HhItemActions.update(item.id, householdId: householdId, action: "done")
            HhHaptics.success()
            remove(item)
            withAnimation(MagziDesign.Motion.standard) {
                recentlyDone.removeAll { $0.id == item.id }
                recentlyDone.insert(item, at: 0)
            }
            // Recurring items roll forward and stay open; /reopen would 409, so no undo for them.
            toast = HhToast(text: "Done: \(item.title ?? "item")", undo: (item.repeat ?? "").isEmpty ? { await reopen(item) } : nil)
        } catch {
            fail(error)
        }
    }

    private func reopen(_ item: MagziItem) async {
        do {
            try await HhItemActions.reopen(item.id, householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) { recentlyDone.removeAll { $0.id == item.id } }
            await load()
        } catch {
            fail(error)
        }
    }

    private func claim(_ item: MagziItem) async {
        do {
            _ = try await HhItemActions.update(item.id, householdId: householdId, action: "claim")
            HhHaptics.success()
            await load()
        } catch {
            fail(error)
        }
    }

    private func progress(_ item: MagziItem, _ action: String, to: String? = nil, when: Date? = nil) async {
        do {
            _ = try await HhItemActions.progress(item.id, householdId: householdId, action: action, to: to, when: when)
            action == "drop" ? HhHaptics.medium() : HhHaptics.success()
            let title = item.title ?? "item"
            let text: String
            switch action {
            case "drop": text = "Dropped \(title)"
            case "park": text = "Parked \(title)"
            case "schedule": text = "Scheduled \(title)" + (when.map { " for \(HhFormat.relativeDay($0))" } ?? "")
            case "delegate": text = "Handed \(title) to \(to ?? "them")"
            default: text = "Updated \(title)"
            }
            let reversible = action == "drop" || action == "park"
            toast = HhToast(text: text, undo: reversible ? {
                do {
                    _ = try await HhItemActions.progress(item.id, householdId: householdId, action: "reopen")
                    await load()
                } catch { fail(error) }
            } : nil)
            await load()
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        HhHaptics.error()
        toast = HhToast(text: HhErrors.message(error))
    }
}

// MARK: - Capture sheet

struct HhCaptureSheet: View {
    let householdId: String
    let onSaved: (MagziItem?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var kind = "task"
    @State private var saving = false
    @State private var error: String?
    @State private var idempotencyKey = UUID().uuidString
    @FocusState private var focused: Bool

    private let kinds: [(String, String)] = [("task", "Task"), ("shopping", "Shopping"), ("decision", "Decision"), ("idea", "Idea")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Add something for the house…", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                }
                Section("Kind") {
                    Picker("Kind", selection: $kind) {
                        ForEach(kinds, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                }
                if let error {
                    Section { Text(error).foregroundStyle(MagziDesign.rose) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MagziDesign.background.ignoresSafeArea())
            .navigationTitle("New item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Add") { Task { await save() } }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let item = try await MagziAPI.shared.captureItem(householdId: householdId, title: text, kind: kind, idempotencyKey: idempotencyKey)
            HhHaptics.success()
            onSaved(item)
            dismiss()
        } catch {
            HhHaptics.error()
            self.error = HhErrors.message(error)
        }
    }
}

// MARK: - Item detail

struct HhItemDetailView: View {
    let householdId: String
    @State var item: MagziItem

    @State private var working = false
    @State private var error: String?
    @State private var toast: HhToast?
    @State private var confirmDrop = false
    @State private var showSchedule = false
    @State private var showDelegate = false

    init(householdId: String, item: MagziItem) {
        self.householdId = householdId
        _item = State(initialValue: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.section) {
                header
                details
                if let error { HhErrorCard(message: error) }
                actions
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.vertical, MagziDesign.Spacing.l)
        }
        .magziScreenBackground()
        .navigationTitle(item.title ?? "Item")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .confirmationDialog("Drop this item? Magzi will stop tracking it.", isPresented: $confirmDrop, titleVisibility: .visible) {
            Button("Drop", role: .destructive) { Task { await progress("drop") } }
        }
        .sheet(isPresented: $showSchedule) {
            HhDateSheet(title: "Schedule") { date in Task { await progress("schedule", when: date) } }
        }
        .sheet(isPresented: $showDelegate) {
            HhMemberPicker(title: "Delegate to", householdId: householdId) { name in
                Task { await progress("delegate", to: name) }
            }
        }
        .hhToast($toast)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            Text(item.title ?? "Untitled")
                .font(MagziDesign.Typography.title)
                .foregroundStyle(MagziDesign.label)
            HStack(spacing: 6) {
                MagziPill(title: HhFormat.capitalized(item.status ?? "open"), tint: statusTint)
                if let owner = item.owner?.magziNonEmpty {
                    MagziPill(title: owner, systemImage: "person", tint: MagziDesign.blue)
                }
                if let due = HhFormat.due(item.dueAt, hasTime: item.dueHasTime ?? false) {
                    MagziPill(title: due, systemImage: "calendar", tint: item.isOverdue ? MagziDesign.amber : MagziDesign.labelSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .magziCard()
    }

    private var statusTint: Color {
        switch item.status ?? "open" {
        case "open": return item.isOverdue ? MagziDesign.amber : MagziDesign.mint
        case "done", "likely": return MagziDesign.mint
        case "dropped": return MagziDesign.rose
        default: return MagziDesign.labelSecondary
        }
    }

    private var details: some View {
        let rows: [(String, String?)] = [
            ("Kind", HhFormat.capitalized(item.kind)),
            ("Created by", item.createdBy),
            ("Created", item.createdAt.map { HhFormat.shortDate($0) }),
            ("Area", item.area),
            ("First step", item.firstStep),
            ("Estimate", item.estimateMin.map { "\($0) min" }),
            ("Repeats", item.repeat),
            ("Done", item.doneAt.map { HhFormat.time($0) }),
            ("Notes", item.notes),
        ]
        let shown = rows.filter { ($0.1 ?? "").isEmpty == false }
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, row in
                if index > 0 { Divider() }
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.labelSecondary)
                    Spacer(minLength: MagziDesign.Spacing.l)
                    Text(row.1 ?? "")
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.label)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, MagziDesign.Spacing.l)
        .magziCard(padding: 0)
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: MagziDesign.Spacing.m) {
            if item.isOpen {
                Button {
                    Task { await update("done") }
                } label: {
                    Label("Mark done", systemImage: "checkmark")
                }
                .buttonStyle(MagziPrimaryButtonStyle())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MagziDesign.Spacing.s) {
                        if (item.owner ?? "").isEmpty {
                            Button("Claim") { Task { await update("claim") } }
                                .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.blue))
                        }
                        Button("Park") { Task { await progress("park") } }
                            .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.labelSecondary))
                        Button("Schedule") { showSchedule = true }
                            .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.mint))
                        Button("Delegate") { showDelegate = true }
                            .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.violet))
                    }
                }
                Button("Drop", role: .destructive) { confirmDrop = true }
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.rose)
                    .frame(minHeight: 44)
            } else {
                Button {
                    Task { await reopen() }
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(MagziSecondaryButtonStyle())
            }
            if working { ProgressView() }
        }
    }

    // MARK: Actions

    private func apply(_ updated: MagziItem?, fallbackStatus: String? = nil) {
        withAnimation(MagziDesign.Motion.standard) {
            if let updated { item = updated } else if let fallbackStatus { item.status = fallbackStatus }
        }
    }

    private func update(_ action: String) async {
        working = true
        defer { working = false }
        do {
            let updated = try await HhItemActions.update(item.id, householdId: householdId, action: action)
            HhHaptics.success()
            error = nil
            apply(updated, fallbackStatus: action == "done" ? "done" : nil)
            if action == "done" {
                toast = HhToast(text: "Marked done", undo: (item.repeat ?? "").isEmpty ? { await reopen() } : nil)
            }
        } catch {
            HhHaptics.error()
            self.error = HhErrors.message(error)
        }
    }

    private func progress(_ action: String, to: String? = nil, when: Date? = nil) async {
        working = true
        defer { working = false }
        do {
            let updated = try await HhItemActions.progress(item.id, householdId: householdId, action: action, to: to, when: when)
            action == "drop" ? HhHaptics.medium() : HhHaptics.success()
            error = nil
            apply(updated, fallbackStatus: action == "drop" ? "dropped" : action == "park" ? "someday" : nil)
            if action == "drop" || action == "park" {
                toast = HhToast(text: action == "drop" ? "Dropped" : "Parked") {
                    await progress("reopen")
                }
            } else if action == "delegate" {
                toast = HhToast(text: "Handed to \(to ?? "them")")
            } else if action == "schedule", let when {
                toast = HhToast(text: "Scheduled for \(HhFormat.relativeDay(when))")
            }
        } catch {
            HhHaptics.error()
            self.error = HhErrors.message(error)
        }
    }

    private func reopen() async {
        working = true
        defer { working = false }
        do {
            try await HhItemActions.reopen(item.id, householdId: householdId)
            error = nil
            apply(nil, fallbackStatus: "open")
        } catch {
            HhHaptics.error()
            self.error = HhErrors.message(error)
        }
    }
}
