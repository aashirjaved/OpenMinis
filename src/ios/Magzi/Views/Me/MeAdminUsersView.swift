import SwiftUI

/// Admin → Users: list, create, disable.
struct MeAdminUsersView: View {
    @State private var users: [MagziUser]?
    @State private var error: Error?
    @State private var actionError: String?
    @State private var query = ""
    @State private var creating = false
    @State private var disabling: MagziUser?

    private var filtered: [MagziUser] {
        let all = (users ?? []).sorted { ($0.isDisabled ? 1 : 0, $0.name.lowercased()) < ($1.isDisabled ? 1 : 0, $1.name.lowercased()) }
        guard !query.isEmpty else { return all }
        return all.filter { "\($0.name) \($0.email ?? "")".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if let actionError {
                MeAreaBanner(text: actionError) { self.actionError = nil }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if let error, users == nil {
                MeAreaErrorCard(error: error) { Task { await load() } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if users == nil {
                Section { ForEach(0..<5, id: \.self) { i in row(MagziUser(userId: "\(i)", email: "person@example.com", displayName: "Placeholder", role: "user")) } }
                    .redacted(reason: .placeholder)
            } else if filtered.isEmpty {
                MagziEmptyState(systemImage: "person.3", title: query.isEmpty ? "No users yet" : "No matches",
                                message: query.isEmpty ? "Add someone with the + button." : "Try a different name or email.")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filtered) { user in
                        row(user)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !user.isDisabled {
                                    Button("Disable", role: .destructive) { disabling = user }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background.ignoresSafeArea())
        .searchable(text: $query, prompt: "Search users")
        .refreshable { await load() }
        .navigationTitle("Users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add user")
            }
        }
        .task { if users == nil { await load() } }
        .sheet(isPresented: $creating) {
            MeAdminCreateUserSheet { user in
                users = (users ?? []) + [user]
            }
        }
        .confirmationDialog(
            "Disable \(disabling?.name ?? "this user")? They'll be signed out on all devices.",
            isPresented: Binding(get: { disabling != nil }, set: { if !$0 { disabling = nil } }),
            titleVisibility: .visible,
            presenting: disabling
        ) { user in
            Button("Disable", role: .destructive) { Task { await disable(user) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func row(_ u: MagziUser) -> some View {
        MagziRow(title: u.name, subtitle: u.email) {
            HStack(spacing: 4) {
                MagziPill(title: MeAreaFormat.humanize(u.role ?? "user"),
                          tint: u.isAdmin ? MagziDesign.amber : MagziDesign.labelSecondary)
                if u.isDisabled { MagziPill(title: "Disabled", tint: MagziDesign.rose) }
            }
        }
        .opacity(u.isDisabled ? 0.6 : 1)
    }

    private func load() async {
        do {
            users = try await MagziAPI.shared.users()
            error = nil
        } catch {
            self.error = error
        }
    }

    private func disable(_ user: MagziUser) async {
        do {
            _ = try await MagziAPI.shared.disableUser(userId: user.userId)
            if let i = users?.firstIndex(where: { $0.userId == user.userId }) {
                users?[i].disabledAtMs = Date().magziMs
            }
            MeAreaHaptics.medium()
            await load()
        } catch {
            MeAreaHaptics.error()
            actionError = MeAreaFailure.message(error)
        }
    }
}

private struct MeAdminCreateUserSheet: View {
    let onCreate: (MagziUser) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var name = ""
    @State private var role = "user"
    @State private var chatScope = true
    @State private var adminScope = false
    @State private var extraScopes = ""
    @State private var saving = false
    @State private var error: String?

    private var scopes: [String] {
        var s: [String] = []
        if chatScope { s.append("chat") }
        if adminScope { s.append("admin") }
        s += extraScopes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !s.contains($0) }
        return s
    }

    private var validEmail: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && !e.contains(" ")
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { MeAreaBanner(text: error) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section("Account") {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Display name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    Picker("Role", selection: $role) {
                        Text("User").tag("user")
                        Text("Family").tag("family")
                        Text("Admin").tag("admin")
                        Text("Guest").tag("guest")
                    }
                } footer: {
                    Text("Admins can approve, pause groups and manage users. Guests can chat but not decide.")
                }
                Section {
                    Toggle("Chat", isOn: $chatScope)
                    Toggle("Admin", isOn: $adminScope)
                    TextField("Other scopes, comma separated", text: $extraScopes)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Scopes")
                } footer: {
                    Text("Sent: \(scopes.isEmpty ? "none" : scopes.joined(separator: ", "))")
                }
            }
            .navigationTitle("New user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!validEmail || saving)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func create() async {
        saving = true
        defer { saving = false }
        do {
            let user = try await MagziAPI.shared.createUser(
                email: email.trimmingCharacters(in: .whitespaces),
                displayName: name.trimmingCharacters(in: .whitespaces),
                role: role,
                scopes: scopes
            )
            MeAreaHaptics.success()
            onCreate(user)
            dismiss()
        } catch {
            MeAreaHaptics.error()
            self.error = MeAreaFailure.message(error)
        }
    }
}
