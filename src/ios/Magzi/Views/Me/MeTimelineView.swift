import SwiftUI

/// Me → Timeline: a day of episodes and visits; confirm or correct each episode.
struct MeTimelineView: View {
    static let episodeKinds = ["gym", "eating_out", "at_work", "at_school", "school_run", "errand", "commute", "home", "away", "sensitive"]

    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var timeline: MagziTimeline?
    @State private var error: Error?
    @State private var actionError: String?
    @State private var correcting: MagziEpisode?
    @State private var busy: Set<Int64> = []

    private var days: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: today) }
    }

    private var dayKey: String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    var body: some View {
        MeAreaScroll(refresh: load) {
            dayPicker
            if let actionError {
                MeAreaBanner(text: actionError) { self.actionError = nil }
            }
            if let error, timeline == nil {
                MeAreaErrorCard(error: error) { Task { await load() } }
            } else if let timeline {
                episodesSection(timeline.episodes ?? [])
                visitsSection(timeline.visits ?? [])
            } else {
                episodesSection((0..<4).map { MagziEpisode(id: -Int64($0) - 1, kind: "at_work", label: "At work", startedAt: Date().magziMs, endedAt: Date().magziMs, place: "Office") })
                    .redacted(reason: .placeholder)
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dayKey) { await load() }
        .sheet(item: $correcting) { episode in
            MeEpisodeCorrectSheet(episode: episode) { kind, place in await correct(episode, kind: kind, place: place) }
        }
    }

    private var dayPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MagziDesign.Spacing.s) {
                    ForEach(days, id: \.self) { d in
                        let selected = Calendar.current.isDate(d, inSameDayAs: day)
                        Button {
                            MeAreaHaptics.selection()
                            day = d
                            timeline = nil
                            error = nil
                        } label: {
                            VStack(spacing: 2) {
                                Text(d.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(MagziDesign.Typography.caption)
                                Text(d.formatted(.dateTime.day()))
                                    .font(.system(.headline, design: .rounded, weight: .semibold).monospacedDigit())
                            }
                            .foregroundStyle(selected ? MagziDesign.onAccent : MagziDesign.label)
                            .frame(width: 48, height: 56)
                            .background(RoundedRectangle(cornerRadius: MagziDesign.Radius.control, style: .continuous)
                                .fill(selected ? MagziDesign.mint : MagziDesign.surface))
                        }
                        .buttonStyle(.plain)
                        .id(d)
                        .accessibilityLabel(d.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .onAppear { proxy.scrollTo(days.last, anchor: .trailing) }
        }
    }

    @ViewBuilder
    private func episodesSection(_ episodes: [MagziEpisode]) -> some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            MagziSectionHeader("Episodes")
            if episodes.isEmpty {
                MagziEmptyState(systemImage: "calendar.day.timeline.left", title: "Nothing for this day",
                                message: "Magzi builds your timeline from places and activity you share.")
                    .magziCard()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(episodes.sorted { ($0.startedAt ?? 0) < ($1.startedAt ?? 0) }) { episode in
                        episodeRow(episode)
                    }
                }
            }
        }
    }

    private func episodeRow(_ e: MagziEpisode) -> some View {
        let tint = MeAreaCategory.tint(e.kind)
        return HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
            Text(MeAreaFormat.time(e.startedAt))
                .font(MagziDesign.Typography.caption.monospacedDigit())
                .foregroundStyle(MagziDesign.labelSecondary)
                .frame(width: 52, alignment: .leading)
                .padding(.top, MagziDesign.Spacing.l)
            ZStack(alignment: .top) {
                Rectangle().fill(MagziDesign.hairlineStrong).frame(width: 2)
                Circle().fill(tint).frame(width: 8, height: 8).padding(.top, MagziDesign.Spacing.l + 3)
            }
            .frame(width: 8)
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title(e))
                        .font(MagziDesign.Typography.headline)
                        .foregroundStyle(MagziDesign.label)
                    Spacer(minLength: 0)
                    if e.confirmed == true {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(MagziDesign.labelTertiary)
                            .accessibilityLabel("Confirmed")
                    }
                }
                let subtitle = [e.place?.magziNonEmpty, (e.with ?? []).isEmpty ? nil : "with \((e.with ?? []).joined(separator: ", "))"]
                    .compactMap { $0 }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                if e.confirmed != true && e.id > 0 {
                    HStack(spacing: MagziDesign.Spacing.s) {
                        Button("Right") { Task { await confirm(e) } }
                            .buttonStyle(MagziCompactButtonStyle())
                        Button("Fix…") { correcting = e }
                            .buttonStyle(MagziCompactButtonStyle(tint: MagziDesign.labelSecondary))
                        if let c = e.confidence, c > 0 {
                            Text("\(Int((c * 100).rounded()))% sure")
                                .font(MagziDesign.Typography.caption)
                                .foregroundStyle(MagziDesign.labelTertiary)
                        }
                    }
                    .disabled(busy.contains(e.id))
                }
            }
            .magziCard(padding: MagziDesign.Spacing.m)
            .padding(.vertical, MagziDesign.Spacing.xs)
        }
    }

    private func title(_ e: MagziEpisode) -> String {
        let name = e.label?.magziNonEmpty ?? MeAreaFormat.humanize(e.kind ?? "episode")
        guard let start = e.startedAt, let end = e.endedAt, end > start else { return name }
        return "\(name) · \(MeAreaFormat.minutes(Double(end - start) / 60_000))"
    }

    @ViewBuilder
    private func visitsSection(_ visits: [MagziTimeline.Visit]) -> some View {
        if !visits.isEmpty {
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                MagziSectionHeader("Visits")
                VStack(spacing: 0) {
                    ForEach(visits.sorted { ($0.arrivedAt ?? 0) < ($1.arrivedAt ?? 0) }) { v in
                        MagziRow(title: v.place?.magziNonEmpty ?? "Unnamed place",
                                 subtitle: "\(MeAreaFormat.time(v.arrivedAt)) – \(v.departedAt == nil ? "now" : MeAreaFormat.time(v.departedAt))",
                                 systemImage: MeAreaCategory.placeSymbol(v.placeKind),
                                 tint: MeAreaCategory.tint(v.placeKind))
                    }
                }
                .magziCard(padding: MagziDesign.Spacing.m)
            }
        }
    }

    private func load() async {
        do {
            let t = try await MagziAPI.shared.timeline(day: dayKey)
            guard !Task.isCancelled else { return }
            timeline = t
            error = nil
        } catch is CancellationError {
        } catch {
            self.error = error
        }
    }

    private func confirm(_ e: MagziEpisode) async {
        busy.insert(e.id)
        defer { busy.remove(e.id) }
        do {
            try await MagziAPI.shared.confirmEpisode(id: e.id)
            update(e.id) { $0.confirmed = true }
            MeAreaHaptics.success()
        } catch {
            MeAreaHaptics.error()
            actionError = MeAreaFailure.message(error)
        }
    }

    private func correct(_ e: MagziEpisode, kind: String, place: String) async -> Bool {
        do {
            let result = try await MagziAPI.shared.correctEpisode(id: e.id, kind: kind, placeName: place)
            update(e.id) {
                $0.kind = result?.kind ?? kind
                $0.label = MeAreaFormat.humanize(result?.kind ?? kind)
                $0.confirmed = result?.confirmed ?? true
                if !place.isEmpty { $0.place = place }
            }
            MeAreaHaptics.success()
            return true
        } catch {
            MeAreaHaptics.error()
            actionError = MeAreaFailure.message(error)
            return false
        }
    }

    private func update(_ id: Int64, _ change: (inout MagziEpisode) -> Void) {
        guard let i = timeline?.episodes?.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(MagziDesign.Motion.standard) { change(&timeline!.episodes![i]) }
    }
}

private struct MeEpisodeCorrectSheet: View {
    let episode: MagziEpisode
    let save: (String, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var kind: String
    @State private var place: String
    @State private var saving = false

    init(episode: MagziEpisode, save: @escaping (String, String) async -> Bool) {
        self.episode = episode
        self.save = save
        let k = episode.kind ?? ""
        _kind = State(initialValue: MeTimelineView.episodeKinds.contains(k) ? k : "errand")
        _place = State(initialValue: episode.place ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What was it?") {
                    Picker("Kind", selection: $kind) {
                        ForEach(MeTimelineView.episodeKinds, id: \.self) { k in
                            Label(MeAreaFormat.humanize(k), systemImage: symbol(k)).tag(k)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    TextField("Place name (optional)", text: $place)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text(kind == "sensitive" ? "Sensitive episodes stay private and are never shared." : "Naming the place helps Magzi recognise it next time.")
                }
            }
            .navigationTitle("Fix episode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            let ok = await save(kind, place.trimmingCharacters(in: .whitespacesAndNewlines))
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(saving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func symbol(_ kind: String) -> String {
        switch kind {
        case "gym": return "figure.run"
        case "eating_out": return "fork.knife"
        case "at_work": return "briefcase"
        case "at_school": return "graduationcap"
        case "school_run": return "figure.and.child.holdinghands"
        case "errand": return "cart"
        case "commute": return "car"
        case "home": return "house"
        case "away": return "airplane"
        default: return "lock"
        }
    }
}
