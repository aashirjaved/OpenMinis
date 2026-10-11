import SwiftUI

/// Reality: the week, honestly.
struct HhRealityView: View {
    let householdId: String

    private struct PendingAction: Identifiable {
        let itemId: Int64
        let title: String
        let action: String
        var id: String { "\(itemId)|\(action)" }
    }

    @State private var reality: MagziReality?
    @State private var week: String?
    @State private var error: String?
    @State private var loading = false
    @State private var toast: HhToast?
    @State private var scheduleAction: PendingAction?
    @State private var delegateAction: PendingAction?
    @State private var working: Set<Int64> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MagziDesign.Spacing.section) {
                weekSelector
                if let error, reality == nil {
                    HhErrorCard(message: error) { Task { await load() } }
                } else if let reality {
                    if let error { HhErrorCard(message: error) { Task { await load() } } }
                    content(reality)
                } else {
                    skeleton
                }
            }
            .padding(.horizontal, MagziDesign.Spacing.gutter)
            .padding(.vertical, MagziDesign.Spacing.l)
        }
        .magziScreenBackground()
        .navigationTitle("This week")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: week) { await load() }
        .hhOnHouseholdChange(householdId) { await load() }
        .sheet(item: $scheduleAction) { pending in
            HhDateSheet(title: pending.action == "schedule" ? "Schedule" : "When") { date in
                Task { await perform(pending, when: date) }
            }
        }
        .sheet(item: $delegateAction) { pending in
            HhMemberPicker(title: "Hand to", householdId: householdId) { name in
                Task { await perform(pending, to: name) }
            }
        }
        .hhToast($toast)
    }

    // MARK: Week selector

    private var weekSelector: some View {
        let from = reality?.from?.magziDate
        let to = reality?.to?.magziDate
        let canGoForward = (reality?.to ?? .max) < Date().magziMs
        return HStack {
            Button { shift(-7) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(reality == nil)
            .accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(weekTitle)
                    .font(MagziDesign.Typography.headline)
                    .foregroundStyle(MagziDesign.label)
                if let from, let to {
                    Text("\(from.formatted(.dateTime.day().month(.abbreviated))) – \(to.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated)))")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
            Spacer()
            Button { shift(7) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(reality == nil || !canGoForward)
            .accessibilityLabel("Next week")
        }
        .foregroundStyle(MagziDesign.mint)
        .magziCard(padding: 4)
    }

    private var weekTitle: String {
        guard let w = reality?.week ?? week else { return "This week" }
        if let n = w.split(separator: "W").last.flatMap({ Int($0) }) { return "Week \(n)" }
        return w
    }

    private func shift(_ days: Int) {
        let anchor = reality?.from?.magziDate ?? Date()
        let target = anchor.addingTimeInterval(TimeInterval(days * 86_400) + 86_400)
        HhHaptics.selection()
        week = HhFormat.isoWeek(target)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ r: MagziReality) -> some View {
        let totals = r.household ?? MagziReality.Totals()
        if (totals.planned ?? 0) == 0 && (r.people ?? []).isEmpty && (r.slipping ?? []).isEmpty && (r.inferred ?? []).isEmpty {
            MagziEmptyState(systemImage: "chart.pie", title: "Nothing planned yet this week", message: "As the house plans and does things, Magzi tracks them here.")
                .frame(maxWidth: .infinity)
        } else {
            hero(totals)
            counts(totals)
            people(r.people ?? [])
            fairLoad(r.fairLoad)
            inferred(r.inferred ?? [])
            slipping(r.slipping ?? [])
            parked(r.parked ?? [])
            if let honesty = r.honesty { honestyCard(honesty) }
            if let driver = r.driver { driverCard(driver) }
        }
    }

    private func hero(_ t: MagziReality.Totals) -> some View {
        let planned = t.planned ?? 0
        let done = t.done ?? 0
        let progress = planned > 0 ? Double(done) / Double(planned) : 0
        return HStack(spacing: MagziDesign.Spacing.xl) {
            ZStack {
                MagziRing(progress: progress, lineWidth: 12)
                VStack(spacing: 0) {
                    Text(HhFormat.percent(progress))
                        .font(MagziDesign.Typography.metric)
                        .monospacedDigit()
                    Text("done")
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
            .frame(width: 120, height: 120)
            Text("\(done) of \(planned) planned things got done this week.")
                .font(MagziDesign.Typography.body)
                .foregroundStyle(MagziDesign.label)
            Spacer(minLength: 0)
        }
        .magziCard()
    }

    private func counts(_ t: MagziReality.Totals) -> some View {
        let entries: [(String, Int?)] = [
            ("Confirmed", t.confirmed), ("Likely", t.likely), ("Moved", t.moved), ("Past", t.past),
            ("Unknown", t.unknown), ("Upcoming", t.upcoming), ("Slipping", t.slipping), ("Parked", t.parked), ("Merged", t.merged),
        ]
        let shown = entries.filter { ($0.1 ?? 0) > 0 }
        return VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            MagziSectionHeader("Household")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: MagziDesign.Spacing.s)], spacing: MagziDesign.Spacing.s) {
                ForEach(shown, id: \.0) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.1 ?? 0)")
                            .font(MagziDesign.Typography.headline)
                            .monospacedDigit()
                            .foregroundStyle(MagziDesign.label)
                        Text(e.0)
                            .font(MagziDesign.Typography.caption)
                            .foregroundStyle(MagziDesign.labelSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .magziCard(padding: 12, radius: MagziDesign.Radius.control)
                }
            }
        }
        .opacity(shown.isEmpty ? 0 : 1)
    }

    @ViewBuilder
    private func people(_ people: [MagziReality.PersonTotals]) -> some View {
        if !people.isEmpty {
            let names = people.compactMap(\.name)
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("People")
                VStack(spacing: MagziDesign.Spacing.m) {
                    ForEach(people) { p in
                        let planned = p.planned ?? 0
                        let done = p.done ?? 0
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(p.name ?? "")
                                    .font(MagziDesign.Typography.subheadline)
                                    .foregroundStyle(MagziDesign.label)
                                Spacer()
                                Text("\(done) of \(planned)")
                                    .font(MagziDesign.Typography.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(MagziDesign.labelSecondary)
                            }
                            HhBar(fraction: planned > 0 ? Double(done) / Double(planned) : 0,
                                  tint: HhPalette.color(for: p.name ?? "", in: names))
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .magziCard()
            }
        }
    }

    @ViewBuilder
    private func fairLoad(_ load: MagziReality.FairLoad?) -> some View {
        let chores = load?.chores ?? []
        let runs = load?.runs ?? []
        if !chores.isEmpty || !runs.isEmpty {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("Fair load")
                VStack(alignment: .leading, spacing: MagziDesign.Spacing.l) {
                    if !chores.isEmpty { shareBlock("Chores", chores) }
                    if !runs.isEmpty { shareBlock("Runs", runs) }
                    Text("Share of completed household work this week.")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                .magziCard()
            }
        }
    }

    private func shareBlock(_ title: String, _ counts: [MagziNamedCount]) -> some View {
        let total = counts.reduce(0) { $0 + $1.count }
        let names = counts.map(\.name)
        return VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            Text(title.uppercased())
                .font(MagziDesign.Typography.eyebrow)
                .foregroundStyle(MagziDesign.labelTertiary)
            ForEach(counts) { c in
                let share = total > 0 ? c.count / total : 0
                HStack(spacing: MagziDesign.Spacing.m) {
                    Text(c.name)
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.label)
                        .frame(width: 84, alignment: .leading)
                        .lineLimit(1)
                    HhBar(fraction: share, tint: HhPalette.color(for: c.name, in: names))
                    Text(HhFormat.percent(share))
                        .font(MagziDesign.Typography.footnote)
                        .monospacedDigit()
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func inferred(_ list: [MagziReality.Inferred]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("Magzi closed these")
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, inf in
                        if index > 0 { Divider().padding(.leading, 58) }
                        MagziRow(
                            title: inf.title ?? "Item",
                            subtitle: evidenceLine(inf.evidence),
                            systemImage: "wand.and.stars",
                            tint: MagziDesign.violet
                        ) {
                            Button("Undo") { Task { await undo(inf) } }
                                .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.labelSecondary))
                                .disabled(working.contains(inf.itemId))
                        }
                        .padding(.horizontal, MagziDesign.Spacing.l)
                    }
                }
                .magziCard(padding: 0)
            }
        }
    }

    private func evidenceLine(_ e: MagziReality.Evidence?) -> String? {
        guard let e else { return nil }
        var parts: [String] = []
        if let label = e.label?.magziNonEmpty ?? e.reason?.magziNonEmpty { parts.append(label) }
        if let person = e.person?.magziNonEmpty { parts.append(person) }
        if let at = e.at { parts.append(HhFormat.relativeDay(at.magziDate)) }
        if let strength = e.strength?.magziNonEmpty { parts.append(strength) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func slipping(_ list: [MagziReality.Slipping]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("Slipping")
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, s in
                        if index > 0 { Divider() }
                        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                            MagziRow(
                                title: s.title ?? "Item",
                                subtitle: [s.owner?.magziNonEmpty, s.days.map { "\($0) day\($0 == 1 ? "" : "s") late" }].compactMap { $0 }.joined(separator: " · "),
                                systemImage: "exclamationmark.triangle",
                                tint: MagziDesign.amber
                            )
                            actionButtons(itemId: s.itemId, title: s.title ?? "Item", actions: s.actions, defaults: ["schedule", "delegate", "drop"])
                        }
                        .padding(.horizontal, MagziDesign.Spacing.l)
                        .padding(.bottom, MagziDesign.Spacing.m)
                    }
                }
                .magziCard(padding: 0)
            }
        }
    }

    @ViewBuilder
    private func parked(_ list: [MagziReality.Parked]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("Parked")
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, p in
                        if index > 0 { Divider() }
                        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                            MagziRow(title: p.title ?? "Item", systemImage: "parkingsign", tint: MagziDesign.labelSecondary)
                            actionButtons(itemId: p.itemId, title: p.title ?? "Item", actions: p.actions, defaults: ["schedule", "drop"])
                        }
                        .padding(.horizontal, MagziDesign.Spacing.l)
                        .padding(.bottom, MagziDesign.Spacing.m)
                    }
                }
                .magziCard(padding: 0)
            }
        }
    }

    private func actionButtons(itemId: Int64, title: String, actions: [MagziReality.Action]?, defaults: [String]) -> some View {
        let list: [(name: String, needs: String?)] = {
            let server = (actions ?? []).compactMap { a in a.action.map { (name: $0, needs: a.needs) } }
            return server.isEmpty ? defaults.map { (name: $0, needs: $0 == "schedule" ? "when" : $0 == "delegate" ? "to" : nil) } : server
        }()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MagziDesign.Spacing.s) {
                ForEach(list, id: \.name) { a in
                    Button(Self.actionTitle(a.name)) {
                        trigger(PendingAction(itemId: itemId, title: title, action: a.name), needs: a.needs)
                    }
                    .buttonStyle(MagziCompactButtonStyle(tint: a.name == "drop" ? MagziDesign.rose : MagziDesign.mint))
                }
            }
            .padding(.leading, 42)
        }
        .disabled(working.contains(itemId))
    }

    private static func actionTitle(_ action: String) -> String {
        switch action {
        case "schedule": return "Schedule…"
        case "delegate": return "Delegate…"
        case "drop": return "Drop"
        case "reopen": return "Reopen"
        case "park": return "Park"
        default: return HhFormat.capitalized(action)
        }
    }

    private func honestyCard(_ h: MagziHonesty) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            MagziSectionHeader("Honesty")
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                HStack(spacing: MagziDesign.Spacing.l) {
                    stat("Known", value: h.knownRate.map(HhFormat.percent) ?? "—", detail: "\(h.known ?? 0) of \(h.due ?? 0) due")
                    stat("Wrong guesses", value: h.wrongRate.map(HhFormat.percent) ?? "—", detail: "\(h.wrong ?? 0) of \(h.inferred ?? 0) inferred")
                }
                ForEach(h.kinds ?? []) { k in
                    HStack {
                        Text(HhFormat.capitalized(k.kind))
                            .font(MagziDesign.Typography.subheadline)
                        if k.demoted == true { MagziPill(title: "Demoted", tint: MagziDesign.amber) }
                        Spacer()
                        Text("\(k.wrong ?? 0) wrong of \(k.total ?? 0)")
                            .font(MagziDesign.Typography.footnote)
                            .monospacedDigit()
                            .foregroundStyle(MagziDesign.labelSecondary)
                    }
                }
                Text("How often Magzi knew what happened, and how often its guesses were wrong.")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
            }
            .magziCard()
        }
    }

    private func stat(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(MagziDesign.Typography.metric).monospacedDigit().foregroundStyle(MagziDesign.label)
            Text(title).font(MagziDesign.Typography.caption).foregroundStyle(MagziDesign.labelSecondary)
            Text(detail).font(MagziDesign.Typography.caption).foregroundStyle(MagziDesign.labelTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func driverCard(_ d: MagziReality.Driver) -> some View {
        let m = d.metrics
        let items = d.items ?? []
        if m != nil || !items.isEmpty {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                MagziSectionHeader("Follow-through")
                VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                    if let m {
                        let metrics: [(String, String)] = [
                            ("Nudges", "\(m.pokes ?? 0)"),
                            ("Acted on", "\(m.acted ?? 0)"),
                            ("Rate", m.rate.map(HhFormat.percent) ?? "—"),
                            ("Stuck", "\((m.stuck ?? []).count)"),
                            ("Group today", "\(m.groupToday ?? 0)"),
                            ("Stage 3", "\(m.stage3 ?? 0)"),
                            ("Cap breaches", "\(m.capBreaches ?? 0)"),
                            ("Rescheduled", "\(m.rescheduled ?? 0)"),
                            ("Rotated", "\(m.rotated ?? 0)"),
                            ("Parked", "\(m.parked ?? 0)"),
                        ]
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: MagziDesign.Spacing.s)], alignment: .leading, spacing: MagziDesign.Spacing.s) {
                            ForEach(metrics, id: \.0) { metric in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(metric.1).font(MagziDesign.Typography.headline).monospacedDigit()
                                    Text(metric.0).font(MagziDesign.Typography.caption).foregroundStyle(MagziDesign.labelSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        ForEach(m.people ?? []) { p in
                            HStack {
                                Text(p.name ?? "").font(MagziDesign.Typography.subheadline)
                                Spacer()
                                Text("\(p.today ?? 0) today · cap \(p.cap ?? 0)")
                                    .font(MagziDesign.Typography.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle((p.today ?? 0) > (p.cap ?? .max) ? MagziDesign.amber : MagziDesign.labelSecondary)
                            }
                        }
                    }
                    if !items.isEmpty {
                        Divider()
                        ForEach(items) { item in driverItem(item) }
                    }
                }
                .magziCard()
            }
        }
    }

    private func driverItem(_ item: MagziReality.DriverItem) -> some View {
        HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            Image(systemName: "lightbulb")
                .foregroundStyle(MagziDesign.labelSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title ?? "Item")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.label)
                if let next = item.nextAction?.magziNonEmpty {
                    Text("Next: \(next)")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                let meta = [
                    item.owner?.magziNonEmpty,
                    item.startBy.map { "start by \(HhFormat.due($0, hasTime: true) ?? "")" },
                    item.lead?.why?.magziNonEmpty,
                    (item.pokes ?? 0) > 0 ? "\(item.pokes ?? 0) nudges" : nil,
                    item.noPoke == true ? "no nudges" : nil,
                ].compactMap { $0 }
                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(MagziDesign.Typography.caption)
                        .foregroundStyle(MagziDesign.labelTertiary)
                }
            }
            Spacer(minLength: 0)
            if let stage = item.stage, stage >= 0 {
                MagziPill(title: "Stage \(stage)", tint: stage >= 3 ? MagziDesign.amber : MagziDesign.labelSecondary)
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: MagziDesign.Spacing.section) {
            HStack(spacing: MagziDesign.Spacing.xl) {
                MagziRing(progress: 0.68, lineWidth: 12).frame(width: 120, height: 120)
                Text("17 of 25 planned things got done this week.")
                Spacer()
            }
            .magziCard()
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack { Text("Person name"); Spacer(); Text("3 of 5") }
                    HhBar(fraction: 0.6)
                }
            }
            .magziCard()
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await MagziAPI.shared.reality(householdId: householdId, week: week)
            withAnimation(MagziDesign.Motion.standard) { reality = r }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }

    private func trigger(_ pending: PendingAction, needs: String?) {
        switch needs ?? (pending.action == "schedule" ? "when" : pending.action == "delegate" ? "to" : "") {
        case "when": scheduleAction = pending
        case "to": delegateAction = pending
        default: Task { await perform(pending) }
        }
    }

    private func perform(_ pending: PendingAction, to: String? = nil, when: Date? = nil) async {
        working.insert(pending.itemId)
        defer { working.remove(pending.itemId) }
        do {
            _ = try await HhItemActions.progress(pending.itemId, householdId: householdId, action: pending.action, to: to, when: when)
            pending.action == "drop" ? HhHaptics.medium() : HhHaptics.success()
            let text: String
            switch pending.action {
            case "drop": text = "Dropped \(pending.title)"
            case "schedule": text = "Scheduled \(pending.title)" + (when.map { " for \(HhFormat.relativeDay($0))" } ?? "")
            case "delegate": text = "Handed \(pending.title) to \(to ?? "them")"
            default: text = "Updated \(pending.title)"
            }
            let undo: (() async -> Void)? = pending.action == "drop" ? {
                do {
                    _ = try await HhItemActions.progress(pending.itemId, householdId: householdId, action: "reopen")
                    await load()
                } catch { fail(error) }
            } : nil
            toast = HhToast(text: text, undo: undo)
            await load()
        } catch { fail(error) }
    }

    private func undo(_ inf: MagziReality.Inferred) async {
        working.insert(inf.itemId)
        defer { working.remove(inf.itemId) }
        do {
            let r = try await MagziAPI.shared.reopenItem(id: inf.itemId, householdId: householdId)
            HhHaptics.success()
            toast = HhToast(text: r.wrongInference == true ? "Reopened. Magzi will learn from that." : "Reopened \(inf.title ?? "item")")
            await load()
        } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        HhHaptics.error()
        toast = HhToast(text: HhErrors.message(error))
    }
}
