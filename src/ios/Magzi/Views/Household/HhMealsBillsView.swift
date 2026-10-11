import SwiftUI

// MARK: - Meals

struct HhMealsView: View {
    let householdId: String

    @State private var meals: MagziMeals?
    @State private var error: String?

    var body: some View {
        List {
            if let error, meals == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let meals {
                content(meals)
            } else {
                Section("This week") {
                    ForEach(0..<7, id: \.self) { _ in dayRow(day: "MON", meal: "Spaghetti bolognese", cook: nil) }
                }
                .redacted(reason: .placeholder)
            }
            Section {
                Button {
                    MagziRouter.shared.askMagzi("Plan dinners for the rest of this week using our saved meals. Keep it simple on weekdays.")
                } label: {
                    Label("Plan with Magzi", systemImage: "sparkle")
                }
                .buttonStyle(MagziPrimaryButtonStyle())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .hhListChrome()
        .navigationTitle("Meals")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .hhOnHouseholdChange(householdId) { await load() }
    }

    @ViewBuilder
    private func content(_ meals: MagziMeals) -> some View {
        let plan = meals.plan ?? []
        Section("This week") {
            if plan.isEmpty {
                Text("No dinners planned yet.")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
            }
            ForEach(plan) { entry in
                dayRow(day: entry.day ?? "", meal: entry.meal, cook: entry.cook, quick: entry.quick ?? false)
            }
        }
        Section("Saved") {
            let saved = meals.saved ?? []
            if saved.isEmpty {
                Text("No saved meals yet. Tell Magzi a favourite and it will remember it.")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
            }
            ForEach(saved) { s in
                MagziRow(
                    title: s.name ?? "Meal",
                    subtitle: (s.ingredients ?? []).isEmpty ? nil : (s.ingredients ?? []).joined(separator: ", "),
                    systemImage: "bookmark",
                    tint: MagziDesign.violet,
                    detail: (s.quick ?? false) ? "Quick" : nil
                )
            }
        }
    }

    private func dayRow(day: String, meal: String?, cook: String?, quick: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MagziDesign.Spacing.m) {
            Text(String(day.prefix(3)).uppercased())
                .font(MagziDesign.Typography.eyebrow)
                .foregroundStyle(MagziDesign.labelSecondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let meal = meal?.magziNonEmpty {
                    Text(meal).font(MagziDesign.Typography.body).foregroundStyle(MagziDesign.label)
                } else {
                    Text("—").font(MagziDesign.Typography.body).foregroundStyle(MagziDesign.labelTertiary)
                }
                if let cook = cook?.magziNonEmpty {
                    Text("Cook: \(cook)")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
            Spacer(minLength: 0)
            if quick { MagziPill(title: "Quick", systemImage: "bolt", tint: MagziDesign.amber) }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        do {
            let m = try await MagziAPI.shared.meals(householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) { meals = m }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }
}

// MARK: - Bills

struct HhBillsView: View {
    let householdId: String

    private enum Mode: String, CaseIterable, Identifiable {
        case due = "Next 30 days", renewals = "Renewals"
        var id: String { rawValue }
    }

    private struct BillGroup: Identifiable {
        var title: String
        var bills: [MagziBill]
        var id: String { title }
    }

    @State private var bills: MagziBills?
    @State private var error: String?
    @State private var mode: Mode = .due

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if let error, bills == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let bills {
                content(bills)
            } else {
                Section {
                    ForEach(0..<5, id: \.self) { _ in
                        MagziRow(title: "Electricity", subtitle: "Tue 14 Oct", systemImage: "creditcard", detail: "£42.00")
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .hhListChrome()
        .navigationTitle("Bills")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: mode) { _ in HhHaptics.selection() }
        .hhOnHouseholdChange(householdId) { await load() }
    }

    @ViewBuilder
    private func content(_ bills: MagziBills) -> some View {
        let groups = mode == .due ? dueGroups(bills.bills ?? []) : renewalGroups(bills.renewals ?? [])
        let all = groups.flatMap(\.bills)
        let total = all.compactMap { HhFormat.amountValue($0.amount) }.reduce(0, +)
        if all.isEmpty {
            Section {
                MagziEmptyState(
                    systemImage: "creditcard",
                    title: mode == .due ? "Nothing due" : "No renewals",
                    message: mode == .due ? "No bills due in the next 30 days." : "No renewals in the next 12 months."
                )
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(HhFormat.currencyTotal(total, sample: all.first?.amount))
                        .font(MagziDesign.Typography.metric)
                        .monospacedDigit()
                        .foregroundStyle(MagziDesign.label)
                    Text(mode == .due ? "due in the next 30 days" : "in renewals over the next 12 months")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                .padding(.vertical, 4)
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.bills) { bill in row(bill) }
                }
            }
        }
    }

    private func row(_ bill: MagziBill) -> some View {
        let overdue = (bill.due ?? .max) < Date().magziMs
        var subtitleParts: [String] = []
        if let date = bill.dueDate { subtitleParts.append(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) }
        if let payer = bill.payer?.magziNonEmpty { subtitleParts.append(payer) }
        if let rep = bill.repeat?.magziNonEmpty { subtitleParts.append(rep) }
        let yearly = mode == .renewals ? Self.yearly(bill) : nil
        return HStack(spacing: MagziDesign.Spacing.m) {
            MagziIconBadge(systemImage: overdue ? "exclamationmark.circle" : "creditcard", tint: overdue ? MagziDesign.amber : MagziDesign.labelSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.title ?? "Bill")
                    .font(MagziDesign.Typography.body)
                    .foregroundStyle(MagziDesign.label)
                if !subtitleParts.isEmpty {
                    Text(subtitleParts.joined(separator: " · "))
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(overdue ? MagziDesign.amber : MagziDesign.labelSecondary)
                }
            }
            Spacer(minLength: MagziDesign.Spacing.s)
            VStack(alignment: .trailing, spacing: 2) {
                Text(HhFormat.amount(bill.amount) ?? "—")
                    .font(MagziDesign.Typography.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(overdue ? MagziDesign.amber : MagziDesign.label)
                if let yearly {
                    Text("\(yearly)/yr")
                        .font(MagziDesign.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(MagziDesign.labelTertiary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private static func yearly(_ bill: MagziBill) -> String? {
        guard let value = HhFormat.amountValue(bill.amount) else { return nil }
        let rep = (bill.repeat ?? "").lowercased()
        let factor: Double
        if rep.contains("week") { factor = 52 }
        else if rep.contains("month") { factor = 12 }
        else if rep.contains("quarter") { factor = 4 }
        else if rep.contains("year") || rep.contains("annual") { factor = 1 }
        else { return nil }
        return HhFormat.currencyTotal(value * factor, sample: bill.amount)
    }

    private func dueGroups(_ list: [MagziBill]) -> [BillGroup] {
        let cal = Calendar.current
        let now = Date()
        let horizon = now.addingTimeInterval(30 * 86_400).magziMs
        let sorted = list.filter { ($0.due ?? .max) <= horizon }.sorted { ($0.due ?? 0) < ($1.due ?? 0) }
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)
        let nextWeek = thisWeek.flatMap { cal.dateInterval(of: .weekOfYear, for: $0.end.addingTimeInterval(1)) }
        var a: [MagziBill] = [], b: [MagziBill] = [], c: [MagziBill] = []
        for bill in sorted {
            guard let date = bill.dueDate else { continue }
            if let w = thisWeek, date < w.end { a.append(bill) }
            else if let w = nextWeek, date < w.end { b.append(bill) }
            else { c.append(bill) }
        }
        return [BillGroup(title: "This week", bills: a), BillGroup(title: "Next week", bills: b), BillGroup(title: "Later", bills: c)]
            .filter { !$0.bills.isEmpty }
    }

    private func renewalGroups(_ list: [MagziBill]) -> [BillGroup] {
        let horizon = Date().addingTimeInterval(366 * 86_400).magziMs
        let sorted = list.filter { ($0.due ?? 0) <= horizon }.sorted { ($0.due ?? .max) < ($1.due ?? .max) }
        var groups: [BillGroup] = []
        for bill in sorted {
            let title = bill.dueDate.map { $0.formatted(.dateTime.month(.wide).year()) } ?? "No date"
            if groups.last?.title == title {
                groups[groups.count - 1].bills.append(bill)
            } else {
                groups.append(BillGroup(title: title, bills: [bill]))
            }
        }
        return groups
    }

    private func load() async {
        do {
            let b = try await MagziAPI.shared.bills(householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) { bills = b }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }
}
