import SwiftUI

/// Me → Privacy: every ambient-context sharing switch. Changes PUT the full object immediately.
struct MePrivacyView: View {
    @State private var sharing = MagziSharing()
    @State private var server: MagziSharing?
    @State private var loadError: Error?
    @State private var saveError: String?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: MagziDesign.Spacing.m) {
                    MagziIconBadge(systemImage: "hand.raised", tint: MagziDesign.mint, size: 36)
                    Text("You decide what Magzi can sense. Household members only ever see coarse presence.")
                        .font(MagziDesign.Typography.subheadline)
                        .foregroundStyle(MagziDesign.label)
                }
                .padding(.vertical, 4)
            }
            if let saveError {
                Section { MeAreaBanner(text: saveError) { self.saveError = nil } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if let loadError, server == nil {
                Section { MeAreaErrorCard(error: loadError) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else {
                switches
                    .redacted(reason: server == nil ? .placeholder : [])
                    .disabled(server == nil)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background.ignoresSafeArea())
        .refreshable { await load() }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { if saving { ProgressView() } }
        }
        .task { if server == nil { await load() } }
    }

    @ViewBuilder
    private var switches: some View {
        Section("What Magzi can sense") {
            item("Location visits", "Places you arrive at and leave, used to build your timeline.", \.location)
            item("Live location", "Short, time-limited location you choose to share, e.g. on the way home.", \.liveLocation)
            item("Activities", "Walking, driving and similar motion activity from this phone.", \.activity)
            item("Workouts", "Workouts from Health, so Magzi can count gym time.", \.workouts)
            item("Nearby people", "Whether household members' phones are close by.", \.proximity)
            item("Skip sensitive places", "Visits to places marked sensitive are never stored.", \.skipSensitive)
        }
        Section {
            Picker("Presence visible to", selection: binding(\.presenceVisibleTo)) {
                Text("Nobody").tag("")
                Text("Only me").tag("self")
                Text("Adults").tag("adults")
                Text("Household").tag("household")
            }
        } header: {
            Text("Presence")
        } footer: {
            Text("Who can see whether you're home, away or at work. Never your exact location.")
        }
        Section("What the household sees") {
            item("Place names", "Shared places show by name (\"at the gym\"), never coordinates.", \.sharePlaceNames)
            item("Wins in the group", "Magzi can celebrate your done tasks in the household chat.", \.shareWins)
        }
        Section("Just for me") {
            item("Private wins", "Magzi tells you privately when you've done well.", \.selfWins)
            item("Reflection", "An occasional private look back at your week.", \.reflection)
        }
    }

    private func item(_ title: String, _ explain: String, _ key: WritableKeyPath<MagziSharing, Bool>) -> some View {
        Toggle(isOn: binding(key)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MagziDesign.Typography.body)
                Text(explain)
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
            }
        }
    }

    private func binding<V>(_ key: WritableKeyPath<MagziSharing, V>) -> Binding<V> {
        Binding(
            get: { sharing[keyPath: key] },
            set: { value in
                sharing[keyPath: key] = value
                MeAreaHaptics.selection()
                saveTask?.cancel()
                saveTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    saveTask = nil
                    await save()
                }
            }
        )
    }

    private func save() async {
        saving = true
        defer { saving = false }
        let sent = sharing
        do {
            let result = try await MagziAPI.shared.updateSharing(sent)
            server = result
            if sharing == sent { sharing = result }
            saveError = nil
        } catch {
            MeAreaHaptics.error()
            if let server { withAnimation { sharing = server } }
            saveError = MeAreaFailure.message(error)
        }
    }

    private func load() async {
        do {
            let s = try await MagziAPI.shared.sharing()
            server = s
            sharing = s
            loadError = nil
        } catch {
            loadError = error
        }
    }
}
