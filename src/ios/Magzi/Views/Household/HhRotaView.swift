import SwiftUI

/// Rota: 7 days, swap to member / skip.
struct HhRotaView: View {
    let householdId: String

    private struct Entry: Identifiable, Hashable {
        var person: String
        var chore: MagziRota.Chore
        var id: Int64 { chore.itemId }
    }

    @State private var rota: MagziRota?
    @State private var error: String?
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var swapEntry: Entry?
    @State private var toast: HhToast?
    @State private var completed: Set<String> = []
    /// Recurring chores repeat the same itemId on several days; done state is per slot.
    private func doneKey(_ e: Entry) -> String { "\(e.id)|\(e.chore.due ?? 0)" }

    private var days: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        List {
            Section {
                dayPicker
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if let error, rota == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let rota {
                content(rota)
            } else {
                Section {
                    ForEach(0..<4, id: \.self) { _ in
                        MagziRow(title: "Take out the bins", systemImage: "arrow.triangle.2.circlepath", detail: "Sara")
                    }
                }
                .redacted(reason: .placeholder)
            }
        }
        .hhListChrome()
        .navigationTitle("Rota")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .hhOnHouseholdChange(householdId) { await load() }
        .sheet(item: $swapEntry) { entry in
            HhMemberPicker(title: "Swap \(entry.chore.title ?? "chore")", householdId: householdId) { name in
                Task { await swap(entry, to: name) }
            }
        }
        .hhToast($toast)
    }

    private var dayPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MagziDesign.Spacing.s) {
                ForEach(days, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: selectedDay)
                    Button {
                        HhHaptics.selection()
                        withAnimation(MagziDesign.Motion.quick) { selectedDay = day }
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                .font(MagziDesign.Typography.eyebrow)
                            Text(day.formatted(.dateTime.day()))
                                .font(MagziDesign.Typography.headline)
                        }
                        .foregroundStyle(selected ? MagziDesign.onAccent : MagziDesign.label)
                        .frame(width: 48, height: 56)
                        .background(Capsule(style: .continuous).fill(selected ? MagziDesign.mint : MagziDesign.surface))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func content(_ rota: MagziRota) -> some View {
        let entries = entries(for: selectedDay, in: rota)
        Section {
            if entries.isEmpty {
                Text("No chores on \(selectedDay.formatted(.dateTime.weekday(.wide))).")
                    .font(MagziDesign.Typography.subheadline)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, MagziDesign.Spacing.l)
            }
            ForEach(entries) { entry in row(entry) }
        }
        if let waiting = rota.waiting, !waiting.isEmpty {
            Section("Waiting") {
                ForEach(waiting) { w in
                    MagziRow(
                        title: w.title ?? "Chore",
                        subtitle: [w.by.map { "By \($0)" }, w.at.map { HhFormat.time($0) }].compactMap { $0 }.joined(separator: " · "),
                        systemImage: "hourglass",
                        tint: MagziDesign.amber
                    )
                }
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        let mine = HhIdentity.isMe(entry.person)
        let isDone = completed.contains(doneKey(entry))
        return HStack(spacing: MagziDesign.Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.chore.title ?? "Chore")
                    .font(MagziDesign.Typography.body)
                    .foregroundStyle(isDone ? MagziDesign.labelTertiary : MagziDesign.label)
                    .strikethrough(isDone)
                if let due = entry.chore.due, Calendar.current.component(.hour, from: due.magziDate) != 0 {
                    Text(due.magziDate.formatted(date: .omitted, time: .shortened))
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
            Spacer(minLength: MagziDesign.Spacing.s)
            HhAvatar(name: entry.person, size: 26, tint: HhPalette.color(for: entry.person, in: rota?.people ?? []))
            Text(mine ? "You" : entry.person)
                .font(MagziDesign.Typography.subheadline)
                .foregroundStyle(MagziDesign.labelSecondary)
            if mine {
                Button {
                    Task { await markDone(entry) }
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isDone ? MagziDesign.mint : MagziDesign.labelTertiary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(isDone)
                .accessibilityLabel(isDone ? "Done" : "Mark done")
            }
        }
        .swipeActions(edge: .trailing) {
            Button { Task { await skip(entry) } } label: { Label("Skip", systemImage: "forward") }
                .tint(.gray)
            Button { swapEntry = entry } label: { Label("Swap…", systemImage: "arrow.left.arrow.right") }
                .tint(MagziDesign.blue)
        }
        .contextMenu {
            Button { swapEntry = entry } label: { Label("Swap…", systemImage: "arrow.left.arrow.right") }
            Button { Task { await skip(entry) } } label: { Label("Skip", systemImage: "forward") }
        }
    }

    private func entries(for day: Date, in rota: MagziRota) -> [Entry] {
        let cal = Calendar.current
        return (rota.week ?? []).flatMap { week in
            (week.chores ?? [])
                .filter { $0.due.map { cal.isDate($0.magziDate, inSameDayAs: day) } ?? false }
                .map { Entry(person: week.person ?? "", chore: $0) }
        }
        .sorted { ($0.chore.due ?? 0) < ($1.chore.due ?? 0) }
    }

    // MARK: Actions

    private func load() async {
        do {
            let r = try await MagziAPI.shared.rota(householdId: householdId)
            withAnimation(MagziDesign.Motion.standard) { rota = r }
            error = nil
        } catch {
            if HhErrors.isCancellation(error) { return }
            self.error = HhErrors.message(error)
        }
    }

    private func markDone(_ entry: Entry) async {
        do {
            _ = try await HhItemActions.update(entry.id, householdId: householdId, action: "done")
            HhHaptics.success()
            withAnimation(MagziDesign.Motion.standard) { _ = completed.insert(doneKey(entry)) }
            // Rota chores always repeat: the server rolls them forward and keeps them open,
            // so /reopen would 409 ("still open"). No undo.
            toast = HhToast(text: "Done: \(entry.chore.title ?? "chore")")
        } catch { fail(error) }
    }

    private func swap(_ entry: Entry, to name: String) async {
        do {
            let r = try await MagziAPI.shared.swapChore(id: entry.id, householdId: householdId, to: name)
            HhHaptics.success()
            toast = HhToast(text: r.message?.magziNonEmpty ?? "Swapped to \(name)")
            await load()
        } catch { fail(error) }
    }

    private func skip(_ entry: Entry) async {
        do {
            let r = try await MagziAPI.shared.skipChore(id: entry.id, householdId: householdId)
            HhHaptics.success()
            let day = Calendar.current.isDateInToday(selectedDay) ? "today" : selectedDay.formatted(.dateTime.weekday(.wide))
            toast = HhToast(text: r.message?.magziNonEmpty ?? "Skipped \(entry.chore.title ?? "chore") \(day)")
            await load()
        } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        HhHaptics.error()
        toast = HhToast(text: HhErrors.message(error))
    }
}
