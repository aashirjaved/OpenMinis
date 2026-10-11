import SwiftUI

/// Me → Memory: notes (editable, forgettable) and facts.
struct MeMemoryView: View {
    @State private var memory: MagziMemory?
    @State private var error: Error?
    @State private var actionError: String?
    @State private var query = ""
    @State private var editing: MagziMemory.MemoryNote?
    @State private var forgetting: MagziMemory.MemoryNote?

    private var notes: [MagziMemory.MemoryNote] {
        let all = memory?.notes ?? []
        guard !query.isEmpty else { return all }
        return all.filter { ($0.text ?? "").localizedCaseInsensitiveContains(query) || ($0.about ?? "").localizedCaseInsensitiveContains(query) }
    }

    private var facts: [MagziMemory.MemoryFact] {
        let all = memory?.facts ?? []
        guard !query.isEmpty else { return all }
        return all.filter { "\($0.label ?? "") \($0.value ?? "")".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if let actionError {
                MeAreaBanner(text: actionError) { self.actionError = nil }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if let error, memory == nil {
                MeAreaErrorCard(error: error) { Task { await load() } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if memory == nil {
                Section { ForEach(0..<5, id: \.self) { _ in noteRow(.init(id: 0, about: "About someone", text: "A remembered sentence about life at home goes here.", savedAt: 0)) } }
                    .redacted(reason: .placeholder)
            } else if memory?.linked == false {
                emptyRow(MagziEmptyState(systemImage: "link", title: "Not linked yet", message: MeAreaFailure.unlinkedCopy))
            } else if notes.isEmpty && facts.isEmpty {
                emptyRow(MagziEmptyState(systemImage: "brain", title: query.isEmpty ? "Nothing remembered yet." : "No matches",
                                         message: query.isEmpty ? "Things you tell Magzi to remember will show up here." : "Try a different word."))
            } else {
                if !notes.isEmpty {
                    Section("Notes") {
                        ForEach(notes) { note in
                            Button { editing = note } label: { noteRow(note) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("Forget", role: .destructive) { forgetting = note }
                                }
                        }
                    }
                }
                if !facts.isEmpty {
                    Section {
                        ForEach(facts) { fact in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(fact.label ?? "Fact")
                                    .font(MagziDesign.Typography.footnote)
                                    .foregroundStyle(MagziDesign.labelSecondary)
                                Text(fact.value ?? "")
                                    .font(MagziDesign.Typography.body)
                                    .foregroundStyle(MagziDesign.label)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Household facts")
                    } footer: {
                        Text("Facts are shared with the household. Edit them from Household → Facts.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search memories")
        .refreshable { await load() }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .task { if memory == nil { await load() } }
        .sheet(item: $editing) { note in
            MeMemoryEditSheet(note: note) { text in await save(note, text: text) }
        }
        .confirmationDialog("Forget this? Magzi won't use it again.", isPresented: Binding(
            get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }
        ), titleVisibility: .visible, presenting: forgetting) { note in
            Button("Forget", role: .destructive) { Task { await forget(note) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func emptyRow(_ state: MagziEmptyState) -> some View {
        state.listRowBackground(Color.clear)
    }

    private func noteRow(_ note: MagziMemory.MemoryNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.text ?? "")
                .font(MagziDesign.Typography.body)
                .foregroundStyle(MagziDesign.label)
                .lineLimit(3)
            HStack(spacing: 4) {
                if note.private == true {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(MagziDesign.labelTertiary)
                }
                Text(subtitle(note))
                    .font(MagziDesign.Typography.footnote)
                    .foregroundStyle(MagziDesign.labelSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func subtitle(_ note: MagziMemory.MemoryNote) -> String {
        [note.about?.magziNonEmpty.map { "About \($0)" }, note.household?.magziNonEmpty,
         note.savedAt.map { $0.magziDate.formatted(date: .abbreviated, time: .omitted) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func load() async {
        do {
            memory = try await MagziAPI.shared.memory()
            error = nil
        } catch {
            self.error = error
        }
    }

    private func save(_ note: MagziMemory.MemoryNote, text: String) async -> Bool {
        do {
            let updated = try await MagziAPI.shared.editMemory(id: note.id, text: text)
            if let i = memory?.notes?.firstIndex(where: { $0.id == note.id }) {
                memory?.notes?[i].text = updated?.text ?? text
            }
            MeAreaHaptics.success()
            return true
        } catch {
            MeAreaHaptics.error()
            actionError = MeAreaFailure.message(error)
            return false
        }
    }

    private func forget(_ note: MagziMemory.MemoryNote) async {
        do {
            try await MagziAPI.shared.forgetMemory(id: note.id)
            withAnimation(MagziDesign.Motion.standard) { memory?.notes?.removeAll { $0.id == note.id } }
            MeAreaHaptics.medium()
        } catch {
            MeAreaHaptics.error()
            actionError = MeAreaFailure.message(error)
        }
    }
}

private struct MeMemoryEditSheet: View {
    let note: MagziMemory.MemoryNote
    let save: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false

    init(note: MagziMemory.MemoryNote, save: @escaping (String) async -> Bool) {
        self.note = note
        self.save = save
        _text = State(initialValue: note.text ?? "")
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                } footer: {
                    Text("Magzi uses this exactly as written.")
                }
            }
            .navigationTitle("Edit memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            let ok = await save(trimmed)
                            saving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(trimmed.isEmpty || trimmed == note.text || saving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
