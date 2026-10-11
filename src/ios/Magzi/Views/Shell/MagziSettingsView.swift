import SwiftUI
import UIKit
import UserNotifications

/// Settings (spec §4.10): Magzi server, notifications, appearance, Ad-hoc gateway, about.
struct MagziSettingsView: View {
    @ObservedObject private var hub = MagziHub.shared
    @ObservedObject private var auth = MagziAuthStore.shared
    @AppStorage("appearanceMode") private var appearanceMode: Int = 0

    @State private var isTesting = false
    @State private var testResult: (ok: Bool, text: String)?
    @State private var confirmSignOut = false
    @State private var notificationStatus: UNAuthorizationStatus?

    var body: some View {
        Form {
            serverSection
            notificationsSection
            Section("Appearance") {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                Button("App icon") { ShellAdhocSettings.open(.appearance) }
            }
            MagziGatewaySection()
            Section("About") {
                LabeledContent("Version", value: Self.info("CFBundleShortVersionString"))
                LabeledContent("Build", value: Self.info("CFBundleVersion"))
                NavigationLink("Acknowledgements") { AboutView() }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MagziDesign.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNotificationStatus() }
        .confirmationDialog("Sign out of Magzi?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { hub.signOut() }
        } message: {
            Text("Ad-hoc keeps working. You can sign in again any time.")
        }
    }

    @ViewBuilder
    private var serverSection: some View {
        Section("Magzi server") {
            if auth.isPaired {
                LabeledContent("Server") {
                    Text(auth.serverURLString)
                        .font(MagziDesign.Typography.mono)
                        .foregroundStyle(MagziDesign.labelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                HStack(spacing: MagziDesign.Spacing.s) {
                    MagziStatusDot(hub.status.isOnline ? .live : .off)
                    Text(hub.status.isOnline ? "Connected" : "Offline")
                    Spacer()
                    if isTesting { ProgressView() }
                }
                Button("Test connection") { Task { await testConnection() } }
                    .disabled(isTesting)
                if let testResult {
                    Text(testResult.text)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(testResult.ok ? MagziDesign.mint : MagziDesign.rose)
                }
                if let email = hub.user?.email, !email.isEmpty {
                    LabeledContent("Signed in as", value: email)
                }
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            } else {
                NavigationLink("Connect to Magzi") { MagziConnectView() }
            }
        }
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            LabeledContent("Status", value: notificationText)
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off"
        case .notDetermined: return "Not asked yet"
        default: return "—"
        }
    }

    private func loadNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        do {
            _ = try await MagziAPI.shared.bootstrap()
            testResult = (true, "Magzi answered. All good.")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            testResult = (false, "Couldn't reach Magzi. Check you're on the home network or Tailscale.")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private static func info(_ key: String) -> String {
        Bundle.main.infoDictionary?[key] as? String ?? "—"
    }
}
