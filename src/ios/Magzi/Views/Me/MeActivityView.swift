import SwiftUI

/// Me → Activity: what Magzi did for you and why, grouped by day.
struct MeActivityView: View {
    @State private var entries: [MagziActivityEntry]?
    @State private var error: Error?

    private var days: [(day: Date, items: [MagziActivityEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: entries ?? []) { cal.startOfDay(for: ($0.at ?? 0).magziDate) }
        return grouped.keys.sorted(by: >).map { day in
            (day, (grouped[day] ?? []).sorted { ($0.at ?? 0) > ($1.at ?? 0) })
        }
    }

    var body: some View {
        List {
            if let error, entries == nil {
                MeAreaErrorCard(error: error) { Task { await load() } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if entries == nil {
                Section("Today") {
                    ForEach(0..<6, id: \.self) { _ in
                        row(MagziActivityEntry(at: 0, what: "Reminded the house about bins", why: "It was due tonight", household: "Home"))
                    }
                }
                .redacted(reason: .placeholder)
            } else if days.isEmpty {
                MagziEmptyState(systemImage: "list.bullet.rectangle", title: "No activity yet",
                                message: "When Magzi acts for you, it shows up here with the reason.")
                    .listRowBackground(Color.clear)
            } else {
                ForEach(days, id: \.day) { group in
                    Section(header(group.day)) {
                        ForEach(group.items) { row($0) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background.ignoresSafeArea())
        .refreshable { await load() }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task { if entries == nil { await load() } }
    }

    private func header(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func row(_ entry: MagziActivityEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MagziDesign.Spacing.m) {
            Text(MeAreaFormat.time(entry.at))
                .font(MagziDesign.Typography.caption.monospacedDigit())
                .foregroundStyle(MagziDesign.labelTertiary)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.what ?? "")
                    .font(MagziDesign.Typography.body)
                    .foregroundStyle(MagziDesign.label)
                let sub = [entry.why?.magziNonEmpty, entry.household?.magziNonEmpty].compactMap { $0 }.joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            entries = try await MagziAPI.shared.activity()
            error = nil
        } catch {
            self.error = error
        }
    }
}
