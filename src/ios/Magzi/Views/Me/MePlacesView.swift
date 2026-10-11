import SwiftUI

/// Me → Places: places Magzi knows; rename, re-kind, share with the household.
struct MePlacesView: View {
    static let kinds = ["home", "work", "school", "gym", "restaurant", "cafe", "shop", "gp", "family", "other", "sensitive"]

    @State private var places: [MagziPlace]?
    @State private var error: Error?
    @State private var editing: MagziPlace?

    var body: some View {
        List {
            if let error, places == nil {
                MeAreaErrorCard(error: error) { Task { await load() } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let places {
                if places.isEmpty {
                    MagziEmptyState(systemImage: "mappin.and.ellipse", title: "No places yet",
                                    message: "Turn on location visits in Privacy and Magzi will learn the places you go.")
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(places) { place in
                            Button { editing = place } label: { row(place) }
                                .buttonStyle(.plain)
                                .disabled(place.mine == false)
                        }
                    } footer: {
                        Text("Household sees only the place name, never your location.")
                    }
                }
            } else {
                Section {
                    ForEach(0..<5, id: \.self) { i in row(MagziPlace(id: Int64(i), name: "Placeholder place", kind: "home", visits: 12)) }
                }
                .redacted(reason: .placeholder)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background.ignoresSafeArea())
        .refreshable { await load() }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .task { if places == nil { await load() } }
        .sheet(item: $editing) { place in
            MePlaceEditSheet(place: place) { updated in
                if let i = places?.firstIndex(where: { $0.id == updated.id }) { places?[i] = updated }
            }
        }
    }

    private func row(_ p: MagziPlace) -> some View {
        var bits: [String] = []
        if let v = p.visits { bits.append(v == 1 ? "1 visit" : "\(v) visits") }
        if p.learned == true && p.confirmed != true { bits.append("Learned") }
        if p.mine == false { bits.append("Someone else's") }
        return MagziRow(title: p.name?.magziNonEmpty ?? "Unnamed place",
                        subtitle: bits.isEmpty ? nil : bits.joined(separator: " · "),
                        systemImage: MeAreaCategory.placeSymbol(p.kind),
                        tint: MeAreaCategory.tint(p.kind),
                        showsChevron: p.mine != false) {
            if p.shared == true { MagziPill(title: "Shared", tint: MagziDesign.mint) }
            if p.isSensitive { MagziPill(title: "Private", systemImage: "lock.fill", tint: MagziDesign.labelSecondary) }
        }
    }

    private func load() async {
        do {
            places = try await MagziAPI.shared.places()
            error = nil
        } catch {
            self.error = error
        }
    }
}

private struct MePlaceEditSheet: View {
    let place: MagziPlace
    let onSave: (MagziPlace) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: String
    @State private var shared: Bool
    @State private var saving = false
    @State private var error: String?

    init(place: MagziPlace, onSave: @escaping (MagziPlace) -> Void) {
        self.place = place
        self.onSave = onSave
        _name = State(initialValue: place.name ?? "")
        _kind = State(initialValue: MePlacesView.kinds.contains(place.kind ?? "") ? (place.kind ?? "other") : "other")
        _shared = State(initialValue: place.shared ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { MeAreaBanner(text: error) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section("Name") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Kind") {
                    Picker("Kind", selection: $kind) {
                        ForEach(MePlacesView.kinds, id: \.self) { k in
                            Label(k == "gp" ? "GP" : MeAreaFormat.humanize(k), systemImage: MeAreaCategory.placeSymbol(k)).tag(k)
                        }
                    }
                }
                Section {
                    Toggle("Share with household", isOn: $shared)
                        .disabled(kind == "sensitive")
                } footer: {
                    Text(kind == "sensitive" ? "Sensitive places stay private." : "Household sees only the place name, never your location.")
                }
            }
            .navigationTitle("Edit place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: kind) { k in if k == "sensitive" { shared = false } }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let updated = try await MagziAPI.shared.updatePlace(
                id: place.id,
                name: trimmed == place.name ? nil : trimmed,
                kind: kind == place.kind ? nil : kind,
                shared: shared == (place.shared ?? false) ? nil : shared
            )
            var result = updated ?? place
            if updated == nil { result.name = trimmed; result.kind = kind; result.shared = shared }
            onSave(result)
            MeAreaHaptics.success()
            dismiss()
        } catch {
            MeAreaHaptics.error()
            self.error = MeAreaFailure.message(error)
        }
    }
}
