import Combine
import Foundation

/// Snapshot for the Home screen, assembled from existing endpoints.
struct MagziToday: Hashable, Sendable {
    var householdId: String
    /// Open items due today or overdue, earliest first.
    var dueToday: [MagziItem] = []
    /// Next open items with a later due date (up to 5).
    var upcoming: [MagziItem] = []
    /// Rota chores due today, per person.
    var rotaToday: [RotaEntry] = []
    /// Bills/renewals due within 7 days (including up to 1 day overdue).
    var billsDueSoon: [MagziBill] = []
    var approvals: [MagziApproval] = []
    /// Per-section failures (e.g. 403 for a role); the other sections still load.
    var errors: [String] = []

    struct RotaEntry: Hashable, Identifiable, Sendable {
        var person: String
        var chore: MagziRota.Chore
        var id: Int64 { chore.itemId }
    }
}

/// App-level Magzi state: identity, households, connection status, live household change signals.
@MainActor
final class MagziHub: ObservableObject {
    static let shared = MagziHub()

    enum ConnectionStatus: Equatable {
        case unpaired
        case connecting
        case online
        case offline(String?)

        var isOnline: Bool { self == .online }
    }

    @Published private(set) var bootstrap: MagziBootstrap?
    @Published private(set) var me: MagziMe?
    @Published private(set) var households: [MagziHousehold] = []
    @Published var selectedHouseholdId: String? {
        didSet { UserDefaults.standard.set(selectedHouseholdId, forKey: Self.selectedKey) }
    }
    @Published private(set) var status: ConnectionStatus
    @Published private(set) var pendingApprovalsCount = 0
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    /// Emits a household id on `reality.changed` / `thread.line` — refetch that household's data.
    let householdChanged = PassthroughSubject<String, Never>()
    /// Emits each new household chat line from the socket.
    let threadLines = PassthroughSubject<(householdId: String, line: MagziThreadLine), Never>()

    private static let selectedKey = "magzi.hub.selectedHouseholdId"
    private var cancellables = Set<AnyCancellable>()
    private var refreshTask: Task<Void, Never>?
    private let logger = AppLogger(category: "MagziHub")

    private init() {
        selectedHouseholdId = UserDefaults.standard.string(forKey: Self.selectedKey)
        status = MagziAuthStore.shared.isPaired ? .connecting : .unpaired

        let socket = MagziWebSocket.shared
        socket.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)

        MagziAuthStore.shared.$isPaired
            .combineLatest(socket.$isConnected, socket.$lastError)
            .sink { [weak self] paired, connected, socketError in
                guard let self else { return }
                if !paired {
                    self.status = .unpaired
                } else if connected {
                    self.status = .online
                } else if case .online = self.status {
                    self.status = .offline(socketError)
                } else if socketError != nil {
                    self.status = .offline(socketError)
                }
            }
            .store(in: &cancellables)

        MagziAuthStore.shared.$isPaired
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] paired in if !paired { self?.clear() } }
            .store(in: &cancellables)
    }

    var user: MagziUser? { me?.user ?? bootstrap?.user ?? MagziAuthStore.shared.user }
    var person: MagziPerson? { me?.person }
    var isPaired: Bool { MagziAuthStore.shared.isPaired }
    var isAdmin: Bool { user?.isAdmin ?? false }
    var selectedHousehold: MagziHousehold? {
        households.first { $0.id == selectedHouseholdId } ?? households.first
    }

    /// Call once from the root view (`.task`). No-op when unpaired.
    func start() async {
        guard isPaired, bootstrap == nil, refreshTask == nil else { return }
        await refresh()
    }

    /// Loads bootstrap + me + households, starts the socket and configures the chat store.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh() async {
        guard isPaired else { status = .unpaired; return }
        isRefreshing = true
        defer { isRefreshing = false }
        if !status.isOnline { status = .connecting }
        do {
            let api = MagziAPI.shared
            async let b = api.bootstrap()
            async let m = api.me()
            async let h = api.households()
            let (boot, me, homes) = try await (b, m, h)
            bootstrap = boot
            self.me = me
            households = homes
            if selectedHouseholdId == nil || !homes.contains(where: { $0.id == selectedHouseholdId }) {
                selectedHouseholdId = homes.first?.id
            }
            lastError = nil
            MagziWebSocket.shared.connect()
            if MagziWebSocket.shared.isConnected { status = .online }
            await MagziChatStore.shared.configure(userId: me.user.userId, personId: me.person?.personId)
            await refreshApprovalsCount()
        } catch MagziError.unauthorized {
            status = .unpaired
        } catch {
            lastError = error.localizedDescription
            status = .offline(error.localizedDescription)
            logger.warning("Refresh failed: \(error.localizedDescription)")
            MagziWebSocket.shared.connect()
        }
    }

    /// Pending approvals across all households (admins only can decide; counted for everyone).
    func refreshApprovalsCount() async {
        let ids = households.map(\.id)
        guard !ids.isEmpty else { pendingApprovalsCount = 0; return }
        let counts = await withTaskGroup(of: Int.self) { group -> Int in
            for id in ids {
                group.addTask { @MainActor in
                    ((try? await MagziAPI.shared.approvals(householdId: id)) ?? []).filter(\.isPending).count
                }
            }
            return await group.reduce(0, +)
        }
        pendingApprovalsCount = counts
    }

    /// Builds the Home "today" snapshot concurrently. Defaults to the selected household.
    func today(householdId: String? = nil) async throws -> MagziToday {
        guard let id = householdId ?? selectedHousehold?.id else { throw MagziError.notConfigured }
        let api = MagziAPI.shared
        async let itemsResult = Self.capture { try await api.items(householdId: id) }
        async let rotaResult = Self.capture { try await api.rota(householdId: id) }
        async let billsResult = Self.capture { try await api.bills(householdId: id) }
        async let approvalsResult = Self.capture { try await api.approvals(householdId: id) }
        let (items, rota, bills, approvals) = await (itemsResult, rotaResult, billsResult, approvalsResult)

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        let endMs = endOfToday.magziMs

        var today = MagziToday(householdId: id)
        if case .success(let list) = items {
            let open = list.filter(\.isOpen)
            today.dueToday = open.filter { ($0.dueAt ?? .max) < endMs }.sorted { ($0.dueAt ?? 0) < ($1.dueAt ?? 0) }
            today.upcoming = Array(open.filter { ($0.dueAt ?? .min) >= endMs }.sorted { ($0.dueAt ?? 0) < ($1.dueAt ?? 0) }.prefix(5))
        }
        if case .success(let r) = rota {
            let range = startOfToday.magziMs..<endMs
            today.rotaToday = (r.week ?? []).flatMap { week in
                (week.chores ?? []).filter { range.contains($0.due ?? -1) }.map { MagziToday.RotaEntry(person: week.person ?? "", chore: $0) }
            }
        }
        if case .success(let b) = bills {
            let from = now.addingTimeInterval(-86_400).magziMs
            let to = now.addingTimeInterval(7 * 86_400).magziMs
            today.billsDueSoon = ((b.bills ?? []) + (b.renewals ?? []))
                .filter { guard let due = $0.due else { return false }; return due >= from && due <= to }
                .sorted { ($0.due ?? 0) < ($1.due ?? 0) }
        }
        if case .success(let a) = approvals {
            today.approvals = a.filter(\.isPending)
        }
        for case .failure(let error) in [items.map { _ in () }, rota.map { _ in () }, bills.map { _ in () }, approvals.map { _ in () }] {
            if case .unauthorized = error { throw error }
            today.errors.append(error.localizedDescription)
        }
        return today
    }

    /// Hex-encodes and registers an APNs device token (call from the app delegate).
    func registerPushToken(_ deviceToken: Data) async {
        guard isPaired else { return }
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        do { try await MagziAPI.shared.registerDevice(token: hex) } catch {
            logger.warning("Push registration failed: \(error.localizedDescription)")
        }
    }

    func signOut() {
        MagziAuthStore.shared.signOut()
    }

    // MARK: Private

    private func handle(_ event: MagziLiveEvent) {
        switch event {
        case .realityChanged(let householdId):
            householdChanged.send(householdId)
        case .threadLine(let householdId, let line):
            threadLines.send((householdId: householdId, line: line))
            householdChanged.send(householdId)
        case .messageDone(_, let done) where done.isProactive:
            if let householdId = done.householdId { householdChanged.send(householdId) }
        default:
            break
        }
    }

    private func clear() {
        bootstrap = nil
        me = nil
        households = []
        pendingApprovalsCount = 0
        lastError = nil
        status = .unpaired
    }

    private static func capture<T>(_ body: () async throws -> T) async -> Result<T, MagziError> {
        do { return .success(try await body()) } catch let error as MagziError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }
}
