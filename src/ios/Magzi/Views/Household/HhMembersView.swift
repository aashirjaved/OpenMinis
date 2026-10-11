import SwiftUI

/// Members: the household's real member list (name, role, person id), with
/// presence folded in. Invite, remove and leave appear only for people who may.
struct HhMembersView: View {
    let householdId: String

    private struct Member: Identifiable, Hashable {
        var name: String
        var role: String
        var personId: String?
        var me: Bool
        var owner: Bool
        var presence: MagziPresence?
        var id: String { personId ?? name }
    }

    @ObservedObject private var hub = MagziHub.shared
    @Environment(\.dismiss) private var dismiss
    @State private var members: [Member]?
    @State private var canManage = false
    @State private var error: String?
    @State private var showInvite = false
    @State private var showJoin = false
    @State private var removing: Member?
    @State private var confirmLeave = false
    @State private var toast: HhToast?
    @State private var working = false

    var body: some View {
        List {
            if let error, members == nil {
                Section { HhErrorCard(message: error) { Task { await load() } } }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } else if let members {
                Section("Members") {
                    if members.isEmpty {
                        Text("No members found yet.")
                            .font(MagziDesign.Typography.subheadline)
                            .foregroundStyle(MagziDesign.labelSecondary)
                    }
                    ForEach(members) { member in row(member) }
                }
            } else {
                Section("Members") {
                    ForEach(0..<4, id: \.self) { _ in
                        HStack { HhAvatar(name: "S", size: 36); Text("Member name"); Spacer(); Text("home") }
                    }
                }
                .redacted(reason: .placeholder)
            }

            Section("Invite") {
                if canManage {
                    Button { showInvite = true } label: {
                        MagziRow(title: "Invite someone", systemImage: "person.badge.plus", tint: MagziDesign.mint, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                }
                Button { showJoin = true } label: {
                    MagziRow(title: "Join with a code", systemImage: "ticket", tint: MagziDesign.blue, showsChevron: true)
                }
                .buttonStyle(.plain)
            }

            if canManage {
                Section {
                    Button(role: .destructive) { confirmLeave = true } label: {
                        Text("Leave household")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(working)
                } footer: {
                    Text("Leaving removes you from this household's lists and chat. Your personal data stays with you.")
                }
            }
        }
        .hhListChrome()
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .hhOnHouseholdChange(householdId) { await load() }
        .sheet(isPresented: $showInvite) { HhInviteSheet(householdId: householdId) }
        .sheet(isPresented: $showJoin) { HhJoinSheet() }
        .confirmationDialog(
            "Remove \(removing?.name ?? "them") from the household? Their personal data stays with them.",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { member in
            Button("Remove", role: .destructive) { Task { await remove(member) } }
        }
        .confirmationDialog("Leave this household?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave household", role: .destructive) { Task { await leave() } }
        } message: {
            Text("You'll need a new invite to come back.")
        }
        .hhToast($toast)
    }

    private func row(_ member: Member) -> some View {
        let me = member.me
        let state = member.presence?.state
        return HStack(spacing: MagziDesign.Spacing.m) {
            ZStack(alignment: .bottomTrailing) {
                HhAvatar(name: member.name, size: 36)
                if let status = HhPalette.presenceStatus(state) {
                    MagziStatusDot(status, size: 9)
                        .padding(2)
                        .background(Circle().fill(MagziDesign.surface))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(MagziDesign.Typography.body)
                        .foregroundStyle(MagziDesign.label)
                    if me { MagziPill(title: "You", tint: MagziDesign.mint) }
                    if member.owner {
                        MagziPill(title: "Owner", tint: MagziDesign.amber)
                    } else if !member.role.isEmpty {
                        MagziPill(title: HhFormat.capitalized(member.role), tint: MagziDesign.labelSecondary)
                    }
                }
                if let state = state?.magziNonEmpty {
                    Text(HhFormat.capitalized(state) + (member.presence?.asOf.map { " · \(HhFormat.time($0))" } ?? ""))
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            if canManage && !me && !member.owner && member.personId != nil {
                Button(role: .destructive) { removing = member } label: { Label("Remove", systemImage: "person.badge.minus") }
            }
        }
    }

    // MARK: Actions

    private func load() async {
        let api = MagziAPI.shared
        async let listResult = Self.list(householdId)
        async let presenceResult = Self.presence(householdId)
        let (listRes, presenceRes) = await (listResult, presenceResult)
        let presence = (try? presenceRes.get()) ?? []
        let response: MagziMembersResponse
        switch listRes {
        case .success(let r): response = r
        case .failure(let e):
            if HhErrors.isCancellation(e) { return }
            if members == nil { error = HhErrors.message(e) }
            return
        }
        let list = (response.members ?? []).map { m in
            Member(
                name: m.name,
                role: m.role ?? "",
                personId: m.personId,
                me: m.me ?? HhIdentity.isMe(m.name),
                owner: m.owner ?? false,
                presence: presence.first { $0.name == m.name }
            )
        }
        withAnimation(MagziDesign.Motion.standard) {
            members = list
            canManage = response.canManage ?? hub.isAdmin
        }
        error = nil
    }

    private static func list(_ id: String) async -> Result<MagziMembersResponse, Error> {
        do { return .success(try await MagziAPI.shared.members(householdId: id)) } catch { return .failure(error) }
    }

    private static func presence(_ id: String) async -> Result<[MagziPresence], Error> {
        do { return .success(try await MagziAPI.shared.presence(householdId: id)) } catch { return .failure(error) }
    }

    private func remove(_ member: Member) async {
        guard let personId = member.personId else { return }
        working = true
        defer { working = false }
        do {
            _ = try await MagziAPI.shared.removeMember(householdId: householdId, personId: personId)
            HhHaptics.medium()
            toast = HhToast(text: "Removed \(member.name)")
            await load()
        } catch {
            HhHaptics.error()
            toast = HhToast(text: HhErrors.message(error))
        }
    }

    private func leave() async {
        working = true
        defer { working = false }
        do {
            _ = try await MagziAPI.shared.leave(householdId: householdId)
            HhHaptics.medium()
            await hub.refresh()
            dismiss()
        } catch {
            HhHaptics.error()
            toast = HhToast(text: HhErrors.message(error))
        }
    }
}

// MARK: - Invite

struct HhInviteSheet: View {
    let householdId: String

    private enum Contact: String, CaseIterable, Identifiable {
        case phone = "Phone", email = "Email"
        var id: String { rawValue }
    }

    private static let roles = ["adult", "teen", "child", "guest", "carer"]

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = "adult"
    @State private var contact: Contact = .phone
    @State private var phone = ""
    @State private var email = ""
    @State private var working = false
    @State private var error: String?
    @State private var invite: MagziInvite?

    var body: some View {
        NavigationStack {
            Group {
                if let invite { created(invite) } else { form }
            }
            .navigationTitle(invite == nil ? "Invite someone" : "Invite ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(invite == nil ? "Cancel" : "Done") { dismiss() }
                }
                if invite == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if working { ProgressView() } else {
                            Button("Create") { Task { await create() } }
                                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        Form {
            Section("Who") {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                Picker("Role", selection: $role) {
                    ForEach(Self.roles, id: \.self) { Text(HhFormat.capitalized($0)).tag($0) }
                }
            }
            Section {
                Picker("Contact", selection: $contact) {
                    ForEach(Contact.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if contact == .phone {
                    TextField("+44 7700 900123", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } else {
                    TextField("name@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("How they'll sign in")
            } footer: {
                Text("Optional. They'll use this to sign in to the Magzi app. Codes last 7 days.")
            }
            if let error {
                Section { Text(error).foregroundStyle(MagziDesign.rose) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background.ignoresSafeArea())
    }

    private func created(_ invite: MagziInvite) -> some View {
        let link = invite.link?.magziNonEmpty ?? "magzi://invite/\(invite.code)"
        let message = "Join our household on Magzi. Open \(link) or enter code \(invite.code) in the app."
        return ScrollView {
            VStack(spacing: MagziDesign.Spacing.xl) {
                MagziIconBadge(systemImage: "person.badge.plus", tint: MagziDesign.mint, size: 52)
                Text("Share this code with \(invite.name ?? name)")
                    .font(MagziDesign.Typography.headline)
                    .multilineTextAlignment(.center)
                Text(invite.code)
                    .font(MagziDesign.Typography.metric)
                    .monospacedDigit()
                    .kerning(4)
                    .textSelection(.enabled)
                    .padding(.horizontal, MagziDesign.Spacing.xl)
                    .padding(.vertical, MagziDesign.Spacing.m)
                    .background(RoundedRectangle(cornerRadius: MagziDesign.Radius.control).fill(MagziDesign.surfaceSecondary))
                if let role = invite.role?.magziNonEmpty {
                    MagziPill(title: HhFormat.capitalized(role), tint: MagziDesign.blue)
                }
                if let exp = invite.expiresAt {
                    Text("Expires \(exp.magziDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                ShareLink(item: link, subject: Text("Magzi invite"), message: Text(message)) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(MagziPrimaryButtonStyle())
                Text(link)
                    .font(MagziDesign.Typography.mono)
                    .foregroundStyle(MagziDesign.labelTertiary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding(MagziDesign.Spacing.gutter)
        }
        .magziScreenBackground()
    }

    private func create() async {
        working = true
        defer { working = false }
        do {
            let result = try await MagziAPI.shared.invite(
                householdId: householdId,
                name: name.trimmingCharacters(in: .whitespaces),
                role: role,
                phone: contact == .phone ? phone.trimmingCharacters(in: .whitespaces) : nil,
                email: contact == .email ? email.trimmingCharacters(in: .whitespaces) : nil
            )
            guard let result else {
                error = "Magzi didn't return an invite code. Try again."
                return
            }
            HhHaptics.success()
            withAnimation(MagziDesign.Motion.standard) { invite = result }
        } catch {
            HhHaptics.error()
            self.error = HhErrors.message(error)
        }
    }
}

// MARK: - Join

struct HhJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @State private var joined: MagziInviteAcceptResponse?

    var body: some View {
        NavigationStack {
            Form {
                if let joined {
                    Section {
                        Label("You joined \(joined.household?.name ?? "the household").", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(MagziDesign.mint)
                    }
                } else {
                    Section {
                        TextField("Invite code or link", text: $code)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.join)
                            .onSubmit { Task { await accept() } }
                    } footer: {
                        Text("Paste the code or magzi://invite link someone shared with you.")
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(MagziDesign.rose) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MagziDesign.background.ignoresSafeArea())
            .navigationTitle("Join a household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(joined == nil ? "Cancel" : "Done") { dismiss() }
                }
                if joined == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if working { ProgressView() } else {
                            Button("Join") { Task { await accept() } }
                                .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func accept() async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !working else { return }
        working = true
        defer { working = false }
        do {
            let result = try await MagziAPI.shared.acceptInvite(code: trimmed)
            HhHaptics.success()
            error = nil
            withAnimation(MagziDesign.Motion.standard) { joined = result }
            await MagziHub.shared.refresh()
            if let id = result.household?.id, MagziHub.shared.households.contains(where: { $0.id == id }) {
                MagziHub.shared.selectedHouseholdId = id
            }
        } catch {
            HhHaptics.error()
            self.error = HhErrors.message(error)
        }
    }
}
