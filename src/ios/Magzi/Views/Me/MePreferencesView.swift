import SwiftUI

/// Me → Preferences. There is no GET for preferences, so the screen loads by sending an empty
/// `PATCH /me/preferences` (all keys optional) and reading back the current values.
struct MePreferencesView: View {
    private enum BriefMode: String, CaseIterable, Identifiable {
        case standard = "default", on, off
        var id: String { rawValue }
        var title: String { self == .standard ? "Default" : rawValue.capitalized }
    }

    private struct Draft: Equatable {
        var briefMode: BriefMode = .standard
        var briefCustomTime = false
        var briefAt = MeAreaFormat.date(fromHHMM: "", fallbackHour: 7)
        var quietOn = false
        var quietFrom = MeAreaFormat.date(fromHHMM: "", fallbackHour: 22)
        var quietTo = MeAreaFormat.date(fromHHMM: "", fallbackHour: 7)
        var channel = ""
        var timeShare = false
        var pokeStyle = "gentle"
        var pokesPerDay = 3
        var adminRound = false
        var pokeOptionsOnly = false
        var hasPokes = false
        var learnedFormat = ""
        var learnedHour: Int?

        init() {}

        init(_ p: MagziPreferences) {
            let at = p.brief?.at ?? ""
            if p.brief?.enabled == false {
                briefMode = .off
            } else {
                briefMode = at.isEmpty ? .standard : .on
            }
            briefCustomTime = !at.isEmpty
            briefAt = MeAreaFormat.date(fromHHMM: at, fallbackHour: 7)
            let quiet = (p.quietHours ?? "").split(separator: "-").map(String.init)
            quietOn = quiet.count == 2
            if quiet.count == 2 {
                quietFrom = MeAreaFormat.date(fromHHMM: quiet[0], fallbackHour: 22)
                quietTo = MeAreaFormat.date(fromHHMM: quiet[1], fallbackHour: 7)
            }
            channel = p.channel ?? ""
            timeShare = p.timeShare ?? false
            if let pokes = p.pokes {
                hasPokes = true
                pokeStyle = pokes.pokeStyle?.magziNonEmpty ?? "gentle"
                pokesPerDay = pokes.pokesPerDay ?? 3
                adminRound = pokes.adminRound ?? false
                pokeOptionsOnly = pokes.pokeOptionsOnly ?? false
                learnedFormat = pokes.learnedFormat ?? ""
                learnedHour = pokes.learnedHour
            }
        }

        var quietString: String { quietOn ? "\(MeAreaFormat.hhmm(quietFrom))-\(MeAreaFormat.hhmm(quietTo))" : "" }
        var briefValue: String {
            switch briefMode {
            case .off: return "off"
            case .standard: return "default"
            case .on: return briefCustomTime ? MeAreaFormat.hhmm(briefAt) : "on"
            }
        }
    }

    @State private var draft = Draft()
    @State private var server: Draft?
    @State private var loadError: Error?
    @State private var saveError: String?
    @State private var pending: [String: Any] = [:]
    @State private var saveTask: Task<Void, Never>?
    @State private var saving = false

    var body: some View {
        Form {
            if let saveError {
                Section { MeAreaBanner(text: saveError) { self.saveError = nil } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if let loadError, server == nil {
                Section {
                    MeAreaErrorCard(error: loadError) { Task { await load() } }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else {
                content
                    .redacted(reason: server == nil ? .placeholder : [])
                    .disabled(server == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background.ignoresSafeArea())
        .refreshable { await load() }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if saving { ProgressView() }
            }
        }
        .task { if server == nil { await load() } }
        .onDisappear { flushNow() }
    }

    @ViewBuilder
    private var content: some View {
        Section {
            Picker("Morning brief", selection: binding(\.briefMode) { ["brief": $0.briefValue] }) {
                ForEach(BriefMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if draft.briefMode == .on {
                Toggle("Set my own time", isOn: binding(\.briefCustomTime) { ["brief": $0.briefValue] })
                if draft.briefCustomTime {
                    DatePicker("Time", selection: binding(\.briefAt) { ["brief": $0.briefValue] }, displayedComponents: .hourAndMinute)
                }
            }
        } header: {
            Text("Daily brief")
        } footer: {
            Text("Default follows the household's brief time. Off stops the morning message for you.")
        }

        Section {
            Toggle("Quiet hours", isOn: binding(\.quietOn) { ["quietHours": $0.quietString] })
            if draft.quietOn {
                DatePicker("From", selection: binding(\.quietFrom) { ["quietHours": $0.quietString] }, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: binding(\.quietTo) { ["quietHours": $0.quietString] }, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Quiet hours")
        } footer: {
            Text("Magzi holds non-urgent messages during quiet hours.")
        }

        Section("Channel") {
            Picker("Reach me on", selection: binding(\.channel) { ["channel": $0.channel] }) {
                Text("App").tag("app")
                Text("WhatsApp").tag("whatsapp")
                if draft.channel.isEmpty { Text("Default").tag("") }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }

        Section {
            Toggle("Share my week with the household", isOn: binding(\.timeShare) { ["timeShare": $0.timeShare] })
        } footer: {
            Text("Adults see your time totals by category in their week view. Never places or details.")
        }

        Section {
            Picker("Style", selection: binding(\.pokeStyle) { ["pokeStyle": $0.pokeStyle] }) {
                Text("Gentle").tag("gentle")
                Text("Direct").tag("direct")
                Text("Playful").tag("playful")
                Text("Quiet").tag("quiet")
            }
            .pickerStyle(.segmented)
            Stepper(value: binding(\.pokesPerDay) { ["pokesPerDay": $0.pokesPerDay] }, in: 0...5) {
                Text(draft.pokesPerDay == 0 ? "No nudges" : "Up to \(draft.pokesPerDay) nudge\(draft.pokesPerDay == 1 ? "" : "s") a day")
                    .monospacedDigit()
            }
            Toggle("Include me in the admin round", isOn: binding(\.adminRound) { ["adminRound": $0.adminRound] })
            Toggle("Only nudge with options", isOn: binding(\.pokeOptionsOnly) { ["pokeOptionsOnly": $0.pokeOptionsOnly] })
            if draft.hasPokes, !draft.learnedFormat.isEmpty || draft.learnedHour != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("What Magzi has learned")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                    if !draft.learnedFormat.isEmpty {
                        Text("Format: \(MeAreaFormat.humanize(draft.learnedFormat))")
                    }
                    if let hour = draft.learnedHour {
                        Text("Best hour: \(String(format: "%02d:00", hour))").monospacedDigit()
                    }
                }
                .font(MagziDesign.Typography.subheadline)
                .padding(.vertical, 2)
            }
        } header: {
            Text("Nudges")
        } footer: {
            Text("Options-only nudges come with quick replies instead of open questions. The admin round is a daily check-in for admins.")
        }
    }

    /// Binding that updates the draft and queues a debounced PATCH with the given keys.
    private func binding<V>(_ keyPath: WritableKeyPath<Draft, V>, changes: @escaping (Draft) -> [String: Any]) -> Binding<V> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { value in
                draft[keyPath: keyPath] = value
                for (k, v) in changes(draft) { pending[k] = v }
                schedule()
            }
        )
    }

    private func schedule() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveTask = nil
            await flush()
        }
    }

    private func flushNow() {
        guard !pending.isEmpty else { return }
        saveTask?.cancel()
        Task { await flush() }
    }

    private func flush() async {
        let changes = pending
        pending = [:]
        guard !changes.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            let prefs = try await MagziAPI.shared.updatePreferences(changes)
            let fresh = Draft(prefs)
            server = fresh
            if pending.isEmpty { draft = fresh }
            saveError = nil
        } catch {
            MeAreaHaptics.error()
            if let server { withAnimation { draft = server } }
            saveError = MeAreaFailure.message(error)
        }
    }

    private func load() async {
        do {
            let prefs = try await MagziAPI.shared.updatePreferences([:])
            let fresh = Draft(prefs)
            server = fresh
            draft = fresh
            loadError = nil
        } catch {
            loadError = error
        }
    }
}
