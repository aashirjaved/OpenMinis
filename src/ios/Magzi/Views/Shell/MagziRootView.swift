import Combine
import SwiftUI

/// App root: five tabs (Home · Magzi · Household · Ad-hoc · More). Ad-hoc is the existing ContentView,
/// which inherits every environment object MinisApp attaches above this view.
struct MagziRootView: View {
    @ObservedObject private var router = MagziRouter.shared
    @ObservedObject private var hub = MagziHub.shared
    @ObservedObject private var adminHealth = MagziShellAdminHealth.shared
    @State private var unreadProactive = 0

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { MagziHomeView() }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(MagziRouter.Tab.home)

            MagziChatView()
                .tabItem { Label("Magzi", systemImage: "bubble.left.and.bubble.right") }
                .badge(unreadProactive)
                .tag(MagziRouter.Tab.magzi)

            HouseholdView()
                .tabItem { Label("Household", systemImage: "person.2") }
                .badge(hub.canDecide ? hub.pendingApprovalsCount : 0)
                .tag(MagziRouter.Tab.household)

            // Kid-safe: no on-device agent for a child or teen.
            if !hub.isMinor {
                ContentView()
                    .tabItem { Label("Ad-hoc", systemImage: "sparkles") }
                    .tag(MagziRouter.Tab.adhoc)
            }

            NavigationStack { MoreView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .badge(hub.isAdmin && adminHealth.needsAttention ? Text("•") : nil)
                .tag(MagziRouter.Tab.more)
        }
        .tint(MagziDesign.mint)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            await MagziHub.shared.start()
            await adminHealth.refreshIfAdmin()
        }
        .onChange(of: router.tab) { tab in
            if tab == .magzi { unreadProactive = 0 }
        }
        .onChange(of: hub.isAdmin) { _ in
            Task { await adminHealth.refreshIfAdmin() }
        }
        .onChange(of: hub.isMinor) { minor in
            if minor, router.tab == .adhoc { router.tab = .home }
        }
        .onReceive(MagziWebSocket.shared.events.receive(on: RunLoop.main)) { event in
            guard case .messageDone(_, let done) = event, done.isProactive, router.tab != .magzi else { return }
            unreadProactive += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .magziAdhocNewTask).receive(on: RunLoop.main)) { note in
            if !hub.isMinor { router.startAdhocTask(prompt: note.object as? String) }
        }
    }
}

/// Admin status for the More tab dot and the Admin row. Admins only; others never fetch.
@MainActor
final class MagziShellAdminHealth: ObservableObject {
    static let shared = MagziShellAdminHealth()

    @Published private(set) var status: MagziStatus?
    @Published private(set) var updatedAt: Date?

    private init() {}

    var needsAttention: Bool {
        guard let status else { return false }
        return status != .ok
    }

    func refreshIfAdmin() async {
        guard MagziHub.shared.isPaired, MagziHub.shared.isAdmin else { status = nil; return }
        do {
            let report = try await MagziAPI.shared.adminStatus()
            status = Self.map(report)
            updatedAt = Date()
        } catch {
            status = .problem
        }
    }

    private static func map(_ report: MagziAdminStatus) -> MagziStatus {
        guard let s = report.status else { return .attention }
        if s.whatsappConnectedSince == nil || s.pairingQrPending == true { return .problem }
        if (s.deadLettersToday ?? 0) > 0 { return .attention }
        return .ok
    }
}
