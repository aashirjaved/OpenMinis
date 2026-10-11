import SwiftUI
import UIKit
import UserNotifications

/// Me → Devices: register this device for push. The APNs token itself is forwarded to
/// `MagziHub.registerPushToken` by the app delegate.
struct MeDevicesView: View {
    @ObservedObject private var hub = MagziHub.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var authStatus: UNAuthorizationStatus?
    @State private var sessions: [MagziSession]?
    @State private var sessionsError: Error?
    @State private var registering = false
    @State private var message: String?

    private var pushEnabledOnServer: Bool? { hub.bootstrap?.features?.push }
    private var notificationsOn: Bool {
        guard let authStatus else { return false }
        return authStatus == .authorized || authStatus == .provisional || authStatus == .ephemeral
    }

    var body: some View {
        MeAreaScroll(refresh: load) {
            thisDevice
            sessionsSection
        }
        .navigationTitle("Devices")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await refreshAuth() } }
        }
    }

    private var thisDevice: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            MagziSectionHeader("This device")
            VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
                HStack(spacing: MagziDesign.Spacing.m) {
                    MagziIconBadge(systemImage: "iphone", tint: MagziDesign.blue, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(UIDevice.current.name)
                            .font(MagziDesign.Typography.headline)
                            .foregroundStyle(MagziDesign.label)
                        Text("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                            .font(MagziDesign.Typography.footnote)
                            .foregroundStyle(MagziDesign.labelSecondary)
                    }
                    Spacer(minLength: 0)
                    MagziPill(title: notificationsOn ? "Notifications on" : "Notifications off",
                              tint: notificationsOn ? MagziDesign.mint : MagziDesign.labelSecondary)
                        .redacted(reason: authStatus == nil ? .placeholder : [])
                }
                if pushEnabledOnServer == false {
                    Text("Push isn't switched on for this Magzi server yet. You can still register; it'll start working once an admin enables it.")
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
                if authStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    } label: {
                        MagziRow(title: "Turn on in Settings", subtitle: "Notifications are off for this app.",
                                 systemImage: "gearshape", tint: MagziDesign.amber, showsChevron: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await register() }
                    } label: {
                        HStack {
                            if registering { ProgressView().tint(MagziDesign.onAccent) }
                            Text(notificationsOn ? "Re-register for notifications" : "Turn on notifications")
                        }
                    }
                    .buttonStyle(MagziPrimaryButtonStyle())
                    .disabled(registering)
                }
                if let message {
                    Text(message)
                        .font(MagziDesign.Typography.footnote)
                        .foregroundStyle(MagziDesign.labelSecondary)
                }
            }
            .magziCard()
        }
    }

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.m) {
            MagziSectionHeader("Signed-in devices")
            if let sessionsError, sessions == nil {
                MeAreaErrorCard(error: sessionsError) { Task { await load() } }
            } else {
                let list = sessions ?? (0..<2).map { MagziSession(sessionId: "p\($0)", deviceName: "Placeholder iPhone", lastSeenAtMs: 0) }
                VStack(spacing: 0) {
                    if list.isEmpty {
                        Text("No other sessions.")
                            .font(MagziDesign.Typography.subheadline)
                            .foregroundStyle(MagziDesign.labelSecondary)
                            .padding(.vertical, 10)
                    }
                    ForEach(list.filter { $0.revokedAtMs == nil }) { s in
                        MagziRow(title: s.deviceName?.magziNonEmpty ?? "Device",
                                 subtitle: "Last seen \(MeAreaFormat.relative(s.lastSeenAtMs))",
                                 systemImage: "iphone", tint: MagziDesign.labelSecondary) {
                            if s.deviceId == MagziAPI.deviceId { MagziPill(title: "This device", tint: MagziDesign.mint) }
                        }
                    }
                }
                .magziCard(padding: MagziDesign.Spacing.m)
                .redacted(reason: sessions == nil ? .placeholder : [])
            }
        }
    }

    private func load() async {
        await refreshAuth()
        do {
            sessions = try await MagziAPI.shared.sessions()
            sessionsError = nil
        } catch {
            sessionsError = error
        }
    }

    private func refreshAuth() async {
        authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func register() async {
        registering = true
        defer { registering = false }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuth()
            guard granted else {
                MeAreaHaptics.error()
                message = "Notifications are off. Turn them on in Settings to hear from Magzi."
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
            MeAreaHaptics.success()
            message = "Registered. Magzi will reach this phone when the app is closed."
        } catch {
            MeAreaHaptics.error()
            message = MeAreaFailure.message(error)
        }
    }
}
