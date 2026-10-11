import Combine
import Foundation
import UIKit

// MARK: - Shared socket driver

/// Owns one `URLSessionWebSocketTask` at a time: receive loop, 25 s client pings
/// (the server sends none), and exponential reconnect backoff (1, 2, 4 … 30 s).
@MainActor
final class MagziSocketDriver {
    /// Builds the upgrade request; `nil` means "not configured", so no connection is attempted.
    var makeRequest: () -> URLRequest? = { nil }
    var onOpen: () -> Void = {}
    var onText: (String) -> Void = { _ in }
    var onClose: (_ error: String?) -> Void = { _ in }
    var onUnauthorized: () -> Void = {}

    private(set) var wantsConnection = false
    private(set) var isOpen = false

    private let logger: AppLogger
    private let delegate = Delegate()
    private lazy var session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var attempt = 0
    private var generation = 0

    static let pingInterval: UInt64 = 25
    static let maxBackoff: Double = 30

    init(category: String) {
        logger = AppLogger(category: category)
        delegate.onOpen = { [weak self] opened in
            Task { @MainActor in
                guard let self, opened === self.task else { return }
                self.isOpen = true
                self.attempt = 0
                self.onOpen()
            }
        }
    }

    func start() {
        wantsConnection = true
        if task == nil && reconnectTask == nil { connectNow() }
    }

    func stop() {
        wantsConnection = false
        reconnectTask?.cancel()
        reconnectTask = nil
        attempt = 0
        teardown(error: nil)
    }

    /// Drops the current socket (if any) and connects immediately with a fresh backoff.
    func reconnectNow() {
        guard wantsConnection else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        attempt = 0
        teardown(error: nil)
        connectNow()
    }

    /// Pings the live socket; reconnects if it turns out to be dead (e.g. after a suspension).
    func verifyAlive() {
        guard wantsConnection else { return }
        guard let task, isOpen else { reconnectNow(); return }
        task.sendPing { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, self.task === task else { return }
                self.reconnectNow()
            }
        }
    }

    func send(_ text: String) {
        task?.send(.string(text)) { _ in }
    }

    // MARK: Private

    private func connectNow() {
        reconnectTask = nil
        guard wantsConnection, let request = makeRequest() else { return }
        generation += 1
        let gen = generation
        let socket = session.webSocketTask(with: request)
        task = socket
        socket.resume()
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket, gen) }
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pingInterval * 1_000_000_000)
                guard !Task.isCancelled, let self, self.generation == gen else { return }
                socket.sendPing { _ in }
            }
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask, _ gen: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                guard gen == generation else { return }
                if !isOpen {
                    isOpen = true
                    attempt = 0
                    onOpen()
                }
                switch message {
                case .string(let text): onText(text)
                case .data(let data): onText(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
            } catch {
                guard gen == generation else { return }
                handleFailure(socket, error)
                return
            }
        }
    }

    private func handleFailure(_ socket: URLSessionWebSocketTask, _ error: Error) {
        let status = (socket.response as? HTTPURLResponse)?.statusCode
        if status == 401 {
            logger.warning("Socket upgrade rejected (401)")
            wantsConnection = false
            teardown(error: MagziError.unauthorized.localizedDescription)
            onUnauthorized()
            return
        }
        logger.info("Socket closed: \(error.localizedDescription)")
        teardown(error: error.localizedDescription)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard wantsConnection, reconnectTask == nil else { return }
        let delay = min(Self.maxBackoff, pow(2, Double(attempt)))
        attempt += 1
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.connectNow()
        }
    }

    private func teardown(error: String?) {
        generation += 1
        receiveTask?.cancel()
        pingTask?.cancel()
        receiveTask = nil
        pingTask = nil
        if let task {
            task.cancel(with: .goingAway, reason: nil)
            self.task = nil
            let wasOpen = isOpen
            isOpen = false
            if wasOpen || error != nil { onClose(error) }
        }
    }

    private final class Delegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
        var onOpen: ((URLSessionWebSocketTask) -> Void)?

        func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
            onOpen?(webSocketTask)
        }
    }
}

// MARK: - Mobile live socket

/// `GET /mobile/v1/ws` with `Authorization: Bearer` (never in the URL). Publishes typed `MagziLiveEvent`s.
@MainActor
final class MagziWebSocket: ObservableObject {
    static let shared = MagziWebSocket()

    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastEventAt: Date?

    /// Every server frame, including `.ready` (sent after each (re)connect — resync history then).
    let events = PassthroughSubject<MagziLiveEvent, Never>()

    private let driver = MagziSocketDriver(category: "MagziLiveSocket")
    private var cancellables = Set<AnyCancellable>()

    private init() {
        driver.makeRequest = {
            let auth = MagziAuthStore.shared
            guard let base = auth.serverURL, let token = auth.token,
                  var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
            components.scheme = components.scheme == "https" ? "wss" : "ws"
            components.path = components.path.trimmingTrailingSlashes + "/mobile/v1/ws"
            guard let url = components.url else { return nil }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        driver.onOpen = { [weak self] in
            self?.isConnected = true
            self?.lastError = nil
        }
        driver.onClose = { [weak self] error in
            self?.isConnected = false
            if let error { self?.lastError = error }
        }
        driver.onUnauthorized = { MagziAuthStore.shared.signOut() }
        driver.onText = { [weak self] text in self?.handle(text) }

        MagziAuthStore.shared.$isPaired
            .removeDuplicates()
            .sink { [weak self] paired in if !paired { self?.disconnect() } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.driver.verifyAlive() }
            .store(in: &cancellables)
    }

    /// Connects (and keeps reconnecting) while paired. Safe to call repeatedly.
    func connect() {
        guard MagziAuthStore.shared.isPaired else { return }
        driver.start()
    }

    /// Kept for existing call sites.
    func connectIfPossible() { connect() }

    func reconnect() {
        guard MagziAuthStore.shared.isPaired else { return }
        if driver.wantsConnection { driver.reconnectNow() } else { driver.start() }
    }

    func disconnect() {
        driver.stop()
        isConnected = false
    }

    private func handle(_ text: String) {
        guard let envelope = try? MagziHTTP.decoder.decode(MagziEnvelope.self, from: Data(text.utf8)) else { return }
        lastEventAt = Date()
        let event = MagziLiveEvent(envelope: envelope)
        if case .ready = event {
            isConnected = true
            lastError = nil
        }
        events.send(event)
    }
}

// MARK: - Cockpit live socket

/// Cockpit `GET /ws?token=` stream: backfill (no `source`), then live `bus` events and `audit` frames.
@MainActor
final class MagziCockpitSocket: ObservableObject {
    static let shared = MagziCockpitSocket()

    @Published private(set) var isConnected = false
    @Published private(set) var lastError: String?

    /// Deduplicated frames (backfill vs. live, by `seq`).
    let frames = PassthroughSubject<MagziCockpitFrame, Never>()

    private let driver = MagziSocketDriver(category: "MagziCockpitSocket")
    private var lastSeq: Int64 = -1
    private var cancellables = Set<AnyCancellable>()

    private init() {
        driver.makeRequest = {
            let auth = MagziCockpitAuth.shared
            guard let base = auth.serverURL, let token = auth.token,
                  var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
            components.scheme = components.scheme == "https" ? "wss" : "ws"
            components.path = components.path.trimmingTrailingSlashes + "/ws"
            components.queryItems = [URLQueryItem(name: "token", value: token)]
            return components.url.map { URLRequest(url: $0) }
        }
        driver.onOpen = { [weak self] in
            self?.isConnected = true
            self?.lastError = nil
        }
        driver.onClose = { [weak self] error in
            self?.isConnected = false
            if let error { self?.lastError = error }
        }
        driver.onUnauthorized = { MagziCockpitAuth.shared.signOut() }
        driver.onText = { [weak self] text in self?.handle(text) }

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.driver.verifyAlive() }
            .store(in: &cancellables)
    }

    func connect() {
        guard MagziCockpitAuth.shared.isLoggedIn else { return }
        if !driver.wantsConnection { lastSeq = -1 }
        driver.start()
    }

    func disconnect() {
        driver.stop()
        isConnected = false
    }

    private func handle(_ text: String) {
        guard let json = try? MagziHTTP.decoder.decode(JSONValue.self, from: Data(text.utf8)) else { return }
        let frame = MagziCockpitFrame(json)
        if case .event(let event) = frame, let seq = event.seq {
            guard seq > lastSeq else { return }
            lastSeq = seq
        }
        frames.send(frame)
    }
}

private extension String {
    var trimmingTrailingSlashes: String {
        var s = self
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
