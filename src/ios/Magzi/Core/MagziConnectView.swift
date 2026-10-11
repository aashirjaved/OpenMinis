import SwiftUI

/// Functional mobile sign-in (server URL → email/phone → code). Plain system styling; restyle freely.
struct MagziConnectView: View {
    @ObservedObject private var auth = MagziAuthStore.shared
    @ObservedObject private var hub = MagziHub.shared

    @State private var method: Method = .email
    @State private var email = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var codeRequested = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorText: String?

    enum Method: String, CaseIterable, Identifiable {
        case email = "Email"
        case phone = "WhatsApp"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("http://host:8767", text: $auth.serverURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(auth.isPaired)
            }

            if auth.isPaired {
                pairedSection
            } else {
                signInSections
            }

            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Magzi")
        .disabled(isWorking)
    }

    @ViewBuilder
    private var pairedSection: some View {
        Section("Signed in") {
            LabeledContent("Name", value: hub.user?.name ?? "—")
            if let email = hub.user?.email, !email.isEmpty { LabeledContent("Email", value: email) }
            LabeledContent("Status", value: statusText)
            if let person = hub.person { LabeledContent("Linked to", value: person.displayName ?? person.personId) }
        }
        Section {
            Button("Refresh") { Task { await hub.refresh() } }
            Button("Sign out", role: .destructive) {
                hub.signOut()
                code = ""
                codeRequested = false
                message = nil
            }
        }
    }

    @ViewBuilder
    private var signInSections: some View {
        Section("Sign in") {
            Picker("Method", selection: $method) {
                ForEach(Method.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(codeRequested)

            if method == .email {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(codeRequested)
            } else {
                TextField("+44 7700 900000", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .disabled(codeRequested)
            }

            Button(codeRequested ? "Send a new code" : "Send code") { Task { await requestCode() } }
                .disabled(identifier.isEmpty)
        }

        if codeRequested {
            Section("Code") {
                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: code) { c in if c.filter(\.isNumber).count == 6 { Task { await verify() } } } // number pad has no return key
                Button("Verify") { Task { await verify() } }
                    .disabled(code.trimmingCharacters(in: .whitespaces).count < 4)
                Button("Change \(method == .email ? "email" : "number")") {
                    codeRequested = false
                    code = ""
                    message = nil
                }
            }
        }
    }

    private var identifier: String {
        (method == .email ? email : phone).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var statusText: String {
        switch hub.status {
        case .unpaired: return "Not connected"
        case .connecting: return "Connecting…"
        case .online: return "Online"
        case .offline(let reason): return reason.map { "Offline — \($0)" } ?? "Offline"
        }
    }

    private func requestCode() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            let response: MagziLoginRequestResponse
            if method == .email {
                response = try await MagziAPI.shared.requestLogin(email: identifier)
            } else {
                response = try await MagziAPI.shared.requestLogin(phone: identifier)
            }
            message = response.message ?? "If this account is enabled, a code was sent."
            codeRequested = true
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func verify() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            if method == .email {
                try await MagziAPI.shared.verifyLogin(email: identifier, code: code)
            } else {
                try await MagziAPI.shared.verifyLogin(phone: identifier, code: code)
            }
            code = ""
            codeRequested = false
            message = nil
            await hub.refresh()
        } catch MagziError.unauthorized {
            errorText = "That code is wrong or expired."
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Functional cockpit (owner console) sign-in: the code arrives over WhatsApp.
struct MagziCockpitLoginView: View {
    @ObservedObject private var auth = MagziCockpitAuth.shared

    @State private var code = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Cockpit server") {
                TextField("http://host:8766", text: $auth.serverURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(auth.isLoggedIn)
            }

            if auth.isLoggedIn {
                Section {
                    Label("Signed in", systemImage: "checkmark.seal")
                    Button("Sign out", role: .destructive) { Task { await auth.logout() } }
                }
            } else {
                Section {
                    Button(auth.codeSent ? "Send a new code" : "Send code over WhatsApp") { Task { await requestCode() } }
                }
                if auth.codeSent {
                    Section("Code") {
                        TextField("Code", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .onChange(of: code) { c in if c.filter(\.isNumber).count == 6 { Task { await verify() } } } // number pad has no return key
                        Button("Verify") { Task { await verify() } }
                            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            if let message {
                Section { Text(message).foregroundStyle(.secondary) }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Cockpit")
        .disabled(isWorking)
    }

    private func requestCode() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            let response = try await auth.requestCode()
            message = response.throttled == true
                ? "A code was sent moments ago — check WhatsApp."
                : "A code was sent to the owner's WhatsApp. It expires in 5 minutes."
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func verify() async {
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            try await auth.verify(code: code)
            code = ""
            message = nil
            MagziCockpitSocket.shared.connect()
        } catch MagziError.unauthorized {
            errorText = "Invalid or expired code."
        } catch {
            errorText = error.localizedDescription
        }
    }
}
