import Foundation

/// Mobile API credentials: server URL (UserDefaults), bearer token (Keychain), user/session (UserDefaults).
@MainActor
final class MagziAuthStore: ObservableObject {
    static let shared = MagziAuthStore()
    static let defaultServerURL = "http://100.121.185.6:8767"

    @Published var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Keys.serverURL) }
    }
    @Published private(set) var isPaired: Bool
    @Published private(set) var user: MagziUser?
    @Published private(set) var session: MagziSession?

    /// Never log this.
    private(set) var token: String?

    private enum Keys {
        static let serverURL = "magzi.remote.serverURL"
        static let user = "magzi.mobile.user.v2"
        static let session = "magzi.mobile.session.v2"
        static let tokenService = "MagziRemoteToken"
        static let tokenAccount = "homecloud"
    }

    private let logger = AppLogger(category: "MagziAuth")

    private init() {
        let defaults = UserDefaults.standard
        serverURLString = defaults.string(forKey: Keys.serverURL) ?? Self.defaultServerURL
        token = MagziKeychain.get(service: Keys.tokenService, account: Keys.tokenAccount)?.magziNonEmpty
        isPaired = token != nil
        user = defaults.data(forKey: Keys.user).flatMap { try? MagziHTTP.decoder.decode(MagziUser.self, from: $0) }
        session = defaults.data(forKey: Keys.session).flatMap { try? MagziHTTP.decoder.decode(MagziSession.self, from: $0) }
    }

    var serverURL: URL? { MagziHTTP.normalizeBaseURL(serverURLString) }

    /// HTTP client for authenticated mobile calls; a 401 signs the user out.
    func client() throws -> MagziHTTP {
        guard let serverURL else { throw MagziError.badURL }
        guard let token else { throw MagziError.notConfigured }
        return MagziHTTP(baseURL: serverURL, token: token, onUnauthorized: { MagziAuthStore.shared.handleUnauthorized() })
    }

    /// HTTP client for the unauthenticated login routes.
    func anonymousClient() throws -> MagziHTTP {
        guard let serverURL else { throw MagziError.badURL }
        return MagziHTTP(baseURL: serverURL, token: nil)
    }

    func save(_ login: MagziLoginVerifyResponse) {
        if let serverURL { serverURLString = serverURL.absoluteString }
        token = login.token
        MagziKeychain.set(login.token, service: Keys.tokenService, account: Keys.tokenAccount)
        update(user: login.user, session: login.session)
        isPaired = true
        logger.info("Paired as \(login.user.userId)")
    }

    func update(user: MagziUser? = nil, session: MagziSession? = nil) {
        let defaults = UserDefaults.standard
        if let user, user != self.user {
            self.user = user
            defaults.set(try? MagziHTTP.encoder.encode(user), forKey: Keys.user)
        }
        if let session, session != self.session {
            self.session = session
            defaults.set(try? MagziHTTP.encoder.encode(session), forKey: Keys.session)
        }
    }

    func signOut() {
        guard isPaired || user != nil else { return }
        token = nil
        MagziKeychain.delete(service: Keys.tokenService, account: Keys.tokenAccount)
        UserDefaults.standard.removeObject(forKey: Keys.user)
        UserDefaults.standard.removeObject(forKey: Keys.session)
        user = nil
        session = nil
        isPaired = false
        logger.info("Signed out of Magzi")
    }

    private func handleUnauthorized() {
        guard isPaired else { return }
        logger.warning("Mobile token rejected (401); clearing session")
        signOut()
    }
}

/// Cockpit (owner console) credentials. Server tokens live in daemon memory only, so any 401 means "log in again".
@MainActor
final class MagziCockpitAuth: ObservableObject {
    static let shared = MagziCockpitAuth()
    static let defaultServerURL = "http://100.121.185.6:8766"

    @Published var serverURLString: String {
        didSet { UserDefaults.standard.set(serverURLString, forKey: Keys.serverURL) }
    }
    @Published private(set) var isLoggedIn: Bool
    /// Set after `requestCode()` succeeds (code is delivered over WhatsApp).
    @Published private(set) var codeSent = false

    /// Never log this.
    private(set) var token: String?

    private enum Keys {
        static let serverURL = "magzi.cockpit.serverURL"
        static let tokenService = "MagziCockpitToken"
        static let tokenAccount = "owner"
    }

    private let logger = AppLogger(category: "MagziCockpitAuth")

    private init() {
        serverURLString = UserDefaults.standard.string(forKey: Keys.serverURL) ?? Self.defaultServerURL
        token = MagziKeychain.get(service: Keys.tokenService, account: Keys.tokenAccount)?.magziNonEmpty
        isLoggedIn = token != nil
    }

    var serverURL: URL? { MagziHTTP.normalizeBaseURL(serverURLString) }

    func client() throws -> MagziHTTP {
        guard let serverURL else { throw MagziError.badURL }
        guard let token else { throw MagziError.notConfigured }
        return MagziHTTP(baseURL: serverURL, token: token, onUnauthorized: { MagziCockpitAuth.shared.handleUnauthorized() })
    }

    func anonymousClient() throws -> MagziHTTP {
        guard let serverURL else { throw MagziError.badURL }
        return MagziHTTP(baseURL: serverURL, token: nil)
    }

    /// `POST /api/login` — asks the daemon to WhatsApp a 5-minute code to the owner.
    @discardableResult
    func requestCode() async throws -> MagziCockpitLoginResponse {
        let response: MagziCockpitLoginResponse = try await anonymousClient().post("/api/login")
        codeSent = true
        return response
    }

    /// `POST /api/verify`.
    func verify(code: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let response: MagziCockpitVerifyResponse = try await anonymousClient().post("/api/verify", json: ["code": trimmed])
        token = response.token
        MagziKeychain.set(response.token, service: Keys.tokenService, account: Keys.tokenAccount)
        isLoggedIn = true
        codeSent = false
        logger.info("Cockpit login verified")
    }

    /// `POST /api/logout` (best effort), then clears local state.
    func logout() async {
        if let client = try? client() {
            let _: MagziOK? = try? await client.post("/api/logout")
        }
        signOut()
    }

    func signOut() {
        token = nil
        MagziKeychain.delete(service: Keys.tokenService, account: Keys.tokenAccount)
        isLoggedIn = false
        codeSent = false
        MagziCockpitSocket.shared.disconnect()
    }

    private func handleUnauthorized() {
        guard isLoggedIn else { return }
        logger.warning("Cockpit token rejected (401); login required")
        signOut()
    }
}
