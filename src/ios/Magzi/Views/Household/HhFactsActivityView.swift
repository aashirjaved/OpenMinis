import SwiftUI

// MARK: - Facts

struct HhFactsView: View {
    let householdId: String

    @State private var facts: [MagziFact]?
    @State private var error: String?
    @State private var search = ""
    @State private var showAdd = false

    var body: some View {
        List {
            if let error, facts == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let facts {
                let q = search.trimmingCharacters(in: .whitespaces).lowercased()
                let shown = q.isEmpty ? facts : facts.filter {
                    ($0.label ?? "").lowercased().contains(q) || ($0.value ?? "").lowercased().contains(q)
                }
                if shown.isEmpty {
                    Section {
                        MagziEmptyState(
                            systemImage: "book.closed",
                            title: q.isEmpty ? "No facts yet" : "No matches",
                            message: q.isEmpty ? "Add things Magzi should know about the house — wifi, bin day, the plumber." : "Nothing matches “\(search)”.",
                            actionTitle: q.isEmpty ? "Add a fact" : nil,
                            action: q.isEmpty ? { showAdd = true } : nil
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(shown) { fact in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fact.label ?? fact.key ?? "Fact")
                                    .font(MagziDesign.Typography.caption)
                                    .foregroundStyle(MagziDesign.labelSecondary)
                                Text(fact.value ?? "")
                                    .font(MagziDesign.Typography.body)
                                    .foregroundStyle(MagziDesign.label)
                                    .textSelection(.enabled)
                                if let at = fact.updatedAt {
                                    Text("Updated \(HhFormat.shortDate(at))")
                                        .font(MagziDesign.Typography.caption)
                                        .foregroundStyle(MagziDesign.labelTertiary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        VStack(alignment: .leading) {
                            Text("Wifi password").font(MagziDesign.Typography.caption)
                            Text("Fact value placeholder").font(MagziDesign.Typography.body)
                        }
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .hhListChrome()
        .searchable(text: $search, prompt: "Search facts")
        .navigationTitle("Facts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add fact")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .hhOnHouseholdChange(householdId) { await load() }
        .sheet(isPresented: $showAdd) {
            HhAddFactSheet(householdId: householdId) { Task { await load() } }
        }
    }

    private func load() async {
        do {
            let list = try await MagziAPI.shared.facts(householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) {
                facts = list.sorted { ($0.label ?? "").localizedCaseInsensitiveCompare($1.label ?? "") == .orderedAscending }
            }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }
}

private struct HhAddFactSheet: View {
    let householdId: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var value = ""
    @State private var saving = false
    @State private var error: String?

    private var valid: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Bin day", text: $label)
                }
                Section("Fact") {
                    TextField("Something Magzi should know about the house", text: $value, axis: .vertical)
                        .lineLimit(3...8)
                }
                if let error {
                    Section { Text(error).foregroundStyle(MagziDesign.rose) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MagziDesign.background.ignoresSafeArea())
            .navigationTitle("New fact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button("Save") { Task { await save() } }.disabled(!valid)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await MagziAPI.shared.putFact(
                householdId: householdId,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                value: value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            HhHaptics.success()
            onSaved()
            dismiss()
        } catch {
            HhHaptics.error()
            self.error = HhErrors.message(error)
        }
    }
}

// MARK: - Activity

struct HhActivityView: View {
    let householdId: String

    private struct DayGroup: Identifiable {
        var day: Date
        var events: [MagziHouseholdEvent]
        var id: Date { day }
    }

    @State private var events: [MagziHouseholdEvent]?
    @State private var error: String?

    var body: some View {
        List {
            if let error, events == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let events {
                if events.isEmpty {
                    Section {
                        MagziEmptyState(systemImage: "clock.arrow.circlepath", title: "No activity yet", message: "Changes to the household's items show up here.")
                            .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(groups(events)) { group in
                    Section(Self.dayTitle(group.day)) {
                        ForEach(group.events) { row($0) }
                    }
                }
            } else {
                Section {
                    ForEach(0..<6, id: \.self) { _ in
                        MagziRow(title: "Sara marked Bins done", systemImage: "checklist", detail: "09:12")
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .hhListChrome()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .hhOnHouseholdChange(householdId) { await load() }
    }

    private func row(_ event: MagziHouseholdEvent) -> some View {
        let (icon, tint) = Self.icon(event.kind)
        return HStack(spacing: MagziDesign.Spacing.m) {
            MagziIconBadge(systemImage: icon, tint: tint)
            Text(Self.summary(event))
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.label)
            Spacer(minLength: MagziDesign.Spacing.s)
            Text(event.at.map { $0.magziDate.formatted(date: .omitted, time: .shortened) } ?? "")
                .font(MagziDesign.Typography.caption)
                .foregroundStyle(MagziDesign.labelTertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func groups(_ events: [MagziHouseholdEvent]) -> [DayGroup] {
        let cal = Calendar.current
        var result: [DayGroup] = []
        for e in events {
            let day = cal.startOfDay(for: (e.at ?? 0).magziDate)
            if result.last?.day == day { result[result.count - 1].events.append(e) } else { result.append(DayGroup(day: day, events: [e])) }
        }
        return result
    }

    private static func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private static func icon(_ kind: String?) -> (String, Color) {
        let k = (kind ?? "").lowercased()
        if k.hasPrefix("item") { return ("checklist", MagziDesign.blue) }
        if k.hasPrefix("approval") { return ("checkmark.shield", MagziDesign.amber) }
        if k.hasPrefix("member") || k.hasPrefix("invite") { return ("person", MagziDesign.violet) }
        if k.hasPrefix("bill") { return ("creditcard", MagziDesign.amber) }
        return ("gearshape", MagziDesign.labelSecondary)
    }

    /// Human sentence from the decoded payload.
    static func summary(_ event: MagziHouseholdEvent) -> String {
        if let item = event.item {
            let title = item.title?.magziNonEmpty.map { "“\($0)”" } ?? "an item"
            let who = item.owner?.magziNonEmpty
            switch item.status ?? "open" {
            case "done": return "\(title) marked done" + (who.map { " by \($0)" } ?? "")
            case "dropped": return "\(title) dropped"
            case "someday", "parked": return "\(title) parked"
            case "likely": return "\(title) looks done"
            case "merged": return "\(title) merged"
            case "open":
                if let due = item.dueAt, (item.updatedAt ?? 0) > (item.createdAt ?? 0), let d = HhFormat.due(due) {
                    return "\(title) " + (who.map { "with \($0), " } ?? "") + "due \(d)"
                }
                if let who { return "\(title) claimed by \(who)" }
                return (item.createdAt ?? 0) >= (item.updatedAt ?? 0) ? "\(title) added" : "\(title) updated"
            case let s:
                return "\(title) is now \(s)"
            }
        }
        if let payload = event.decodedPayload {
            if let text = payload["summary"]?.stringValue ?? payload["text"]?.stringValue ?? payload["message"]?.stringValue {
                return text
            }
            let who = payload["name"]?.stringValue?.magziNonEmpty
            if let title = payload["title"]?.stringValue?.magziNonEmpty {
                return "“\(title)” \(Self.kindWords(event.kind))" + (who.map { " by \($0)" } ?? "")
            }
        }
        return HhFormat.capitalized(Self.kindWords(event.kind))
    }

    /// "bus.ItemDone" → "done", "item.changed" → "changed", "ItemDropped" → "dropped".
    private static func kindWords(_ kind: String?) -> String {
        var k = kind ?? "update"
        if let dot = k.lastIndex(of: ".") { k = String(k[k.index(after: dot)...]) }
        if k.lowercased().hasPrefix("item") { k = String(k.dropFirst(4)) }
        var words = ""
        for c in k {
            if c.isUppercase, !words.isEmpty { words += " " }
            words += c == "_" ? " " : String(c).lowercased()
        }
        return words.trimmingCharacters(in: .whitespaces).magziNonEmpty ?? "updated"
    }

    private func load() async {
        do {
            let list = try await MagziAPI.shared.events(householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) {
                events = Array(list.suffix(300).reversed())
            }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }
}
