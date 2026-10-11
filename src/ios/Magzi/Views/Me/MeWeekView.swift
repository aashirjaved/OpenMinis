import SwiftUI

/// Me → My week: time by category, actual vs planned, with a week selector.
struct MeWeekView: View {
    @State private var offset = 0
    @State private var report: MagziTimeReport?
    @State private var error: Error?
    @State private var loading = false

    private var weekStart: Date {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return cal.date(byAdding: .weekOfYear, value: offset, to: start) ?? start
    }

    private var weekKey: String {
        let cal = Calendar(identifier: .iso8601)
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    private var weekTitle: String {
        if offset == 0 { return "This week" }
        if offset == -1 { return "Last week" }
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    var body: some View {
        MeAreaScroll(refresh: load) {
            selector
            if let error, report == nil {
                MeAreaErrorCard(error: error) { Task { await load() } }
            } else {
                let shown = report ?? MeWeekSummary.placeholder
                Group {
                    totals(shown)
                    MeWeekSummary(report: shown)
                    categories(title: "By category", lines: shown.lines ?? [])
                    if let household = shown.household, !(household.lines ?? []).isEmpty {
                        householdBlock(household)
                    }
                }
                .redacted(reason: report == nil ? .placeholder : [])
            }
        }
        .navigationTitle("My week")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: offset) { await load() }
    }

    private var selector: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(weekTitle).font(MagziDesign.Typography.headline)
                Text(weekKey).font(MagziDesign.Typography.caption.monospacedDigit()).foregroundStyle(MagziDesign.labelTertiary)
            }
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(offset >= 0)
                .accessibilityLabel("Next week")
        }
        .foregroundStyle(MagziDesign.mint)
        .magziCard(padding: MagziDesign.Spacing.xs)
    }

    private func step(_ delta: Int) {
        MeAreaHaptics.selection()
        offset += delta
        report = nil
        error = nil
    }

    private func totals(_ r: MagziTimeReport) -> some View {
        HStack(spacing: MagziDesign.Spacing.m) {
            MagziMetricCard(title: "Tracked", value: MeAreaFormat.minutes(r.actualMin), systemImage: "clock", tint: MagziDesign.mint)
            MagziMetricCard(title: "Planned", value: MeAreaFormat.minutes(r.plannedMin), systemImage: "calendar", tint: MagziDesign.blue,
                            caption: r.share == true ? "Shared with household" : nil)
        }
    }

    private func categories(title: String, lines: [MagziTimeLine]) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            MagziSectionHeader(title)
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.l) {
                if lines.isEmpty {
                    Text("Nothing tracked this week yet.")
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.labelSecondary)
                } else {
                    let scale = max(1, lines.map { max($0.actualMin ?? 0, $0.plannedMin ?? 0) }.max() ?? 1)
                    ForEach(lines) { MeWeekLineRow(line: $0, scale: scale) }
                }
            }
            .magziCard()
        }
    }

    private func householdBlock(_ h: MagziTimeReport.Household) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            categories(title: "Household", lines: h.lines ?? [])
            if let members = h.members, !members.isEmpty {
                Text("Includes \(members.joined(separator: ", ")).")
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .padding(.horizontal, MagziDesign.Spacing.xs)
            }
        }
    }

    private func load() async {
        let key = offset == 0 ? nil : weekKey
        loading = true
        defer { loading = false }
        do {
            let r = try await MagziAPI.shared.time(week: key)
            guard !Task.isCancelled else { return }
            report = r
            error = nil
        } catch is CancellationError {
        } catch {
            // No ledger yet (404) is an empty week, not a failure.
            if HhErrors.status(error) == 404 { report = MagziTimeReport(); self.error = nil } else { self.error = error }
        }
    }
}

private struct MeWeekLineRow: View {
    let line: MagziTimeLine
    let scale: Double

    var body: some View {
        let tint = MeAreaCategory.tint(line.key ?? line.label)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.label ?? line.key ?? "Other")
                    .font(MagziDesign.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(MagziDesign.label)
                Spacer()
                Text("\(MeAreaFormat.minutes(line.actualMin)) / \(MeAreaFormat.minutes(line.plannedMin))")
                    .font(MagziDesign.Typography.footnote.monospacedDigit())
                    .foregroundStyle(MagziDesign.labelSecondary)
                if let change = line.changeMin, change != 0 {
                    Text((change > 0 ? "+" : "") + MeAreaFormat.minutes(change))
                        .font(MagziDesign.Typography.caption.monospacedDigit())
                        .foregroundStyle(change > 0 ? MagziDesign.mint : MagziDesign.amber)
                }
            }
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(tint)
                        .frame(width: max(4, geo.size.width * CGFloat((line.actualMin ?? 0) / scale)), height: 8)
                    Capsule().fill(tint.opacity(0.25))
                        .frame(width: max(4, geo.size.width * CGFloat((line.plannedMin ?? 0) / scale)), height: 5)
                }
                .animation(MagziDesign.Motion.gentle, value: line.actualMin)
            }
            .frame(height: 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.label ?? "Other"): \(MeAreaFormat.minutes(line.actualMin)) actual, \(MeAreaFormat.minutes(line.plannedMin)) planned")
    }
}
