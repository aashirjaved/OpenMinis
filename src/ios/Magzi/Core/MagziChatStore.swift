import Combine
import Foundation

struct MagziChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    enum Status: String, Sendable { case pending, sent, failed, streaming, delivered }

    /// Server message id (`in:<clientId>` / `out:…` / `wa:…`), or `streaming` for the live preview bubble.
    let id: String
    var role: Role
    var text: String
    var createdAt: Date
    var status: Status
    var isProactive = false
    /// `"app"` or `"whatsapp"` in the unified person view.
    var channel: String?
    var clientMessageId: String?
    /// Proactive metadata (`source`, `kind`, `householdId`).
    var meta: JSONValue?

    static let streamingId = "streaming"

    var isStreaming: Bool { status == .streaming }
    var isFailed: Bool { status == .failed }
    var isWhatsApp: Bool { channel == "whatsapp" }

    init(_ m: MagziMessage) {
        id = m.messageId
        role = m.isFromUser ? .user : .assistant
        text = m.text ?? ""
        createdAt = (m.createdAtMs ?? Date().magziMs).magziDate
        status = .delivered
        channel = m.channel
        if m.messageId.hasPrefix("in:") { clientMessageId = String(m.messageId.dropFirst(3)) }
    }

    init(id: String, role: Role, text: String, createdAt: Date = Date(), status: Status,
         isProactive: Bool = false, channel: String? = nil, clientMessageId: String? = nil, meta: JSONValue? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.status = status
        self.isProactive = isProactive
        self.channel = channel
        self.clientMessageId = clientMessageId
        self.meta = meta
    }
}

/// The Magzi conversation: app chat `mobile:<userId>`, or the unified `person:<personId>` thread
/// (app + WhatsApp merged) when the login is linked and `useUnifiedThread` is on.
@MainActor
final class MagziChatStore: ObservableObject {
    static let shared = MagziChatStore()

    /// Oldest → newest. Includes the optimistic pending bubbles and the `streaming` preview bubble.
    @Published private(set) var messages: [MagziChatMessage] = []
    @Published private(set) var isTyping = false
    @Published private(set) var streamingText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingOlder = false
    @Published private(set) var hasMoreHistory = false
    @Published var error: String?
    @Published var useUnifiedThread = UserDefaults.standard.bool(forKey: "magzi.chat.unified") {
        didSet {
            UserDefaults.standard.set(useUnifiedThread, forKey: "magzi.chat.unified")
            if oldValue != useUnifiedThread { Task { await reload() } }
        }
    }

    private(set) var userId: String?
    private(set) var personId: String?

    private var loadedConversationId: String?
    private var streamRound = 0
    private var streamParts: [Int: String] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let logger = AppLogger(category: "MagziChat")

    private init() {
        MagziWebSocket.shared.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)
        MagziAuthStore.shared.$isPaired
            .removeDuplicates()
            .sink { [weak self] paired in if !paired { self?.reset() } }
            .store(in: &cancellables)
    }

    /// `mobile:<userId>` — where sends land and live events arrive.
    var appConversationId: String? {
        (userId ?? MagziAuthStore.shared.user?.userId).map { "mobile:\($0)" }
    }

    /// The conversation currently displayed.
    var conversationId: String? {
        if useUnifiedThread, let personId { return "person:\(personId)" }
        return appConversationId
    }

    var canUseUnifiedThread: Bool { personId != nil }

    /// Called by `MagziHub.refresh()`; reloads history when the identity changed.
    func configure(userId: String, personId: String?) async {
        let changed = userId != self.userId || personId != self.personId
        self.userId = userId
        self.personId = personId
        if changed || messages.isEmpty { await reload() }
    }

    /// Loads the newest page and merges it with local pending/failed bubbles.
    func reload() async {
        guard let conversationId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await MagziAPI.shared.messages(conversationId: conversationId, limit: 50)
            guard conversationId == self.conversationId else { return }
            merge(page)
            // `before` paging only works for the person thread (ms cursor); app-chat ids aren't exposed.
            hasMoreHistory = conversationId.hasPrefix("person:") && page.count >= 50
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Person thread only: pages older messages by time.
    func loadOlder() async {
        guard hasMoreHistory, !isLoadingOlder, let conversationId, conversationId.hasPrefix("person:"),
              let oldest = messages.first(where: { $0.status == .delivered }) else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        do {
            let page = try await MagziAPI.shared.messages(conversationId: conversationId, before: oldest.createdAt.magziMs, limit: 50)
            merge(page)
            hasMoreHistory = page.count >= 50
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Optimistically appends the user bubble, then posts it. The reply streams in over the socket.
    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let clientId = UUID().uuidString
        upsert(MagziChatMessage(id: "in:\(clientId)", role: .user, text: trimmed, status: .pending, channel: "app", clientMessageId: clientId))
        await post(text: trimmed, clientId: clientId)
    }

    /// Re-sends a failed bubble with the same `clientMessageId` (server dedupes the stored row).
    func retry(_ messageId: String) async {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              let clientId = messages[index].clientMessageId else { return }
        messages[index].status = .pending
        await post(text: messages[index].text, clientId: clientId)
    }

    func discardFailed(_ messageId: String) {
        messages.removeAll { $0.id == messageId && $0.status == .failed }
    }

    func reset() {
        messages = []
        isTyping = false
        streamingText = ""
        streamRound = 0
        streamParts = [:]
        hasMoreHistory = false
        userId = nil
        personId = nil
        loadedConversationId = nil
        error = nil
    }

    // MARK: Private

    /// Socket down: reload history every 3s (max ~2 min) until a Magzi line lands after our bubble.
    private func pollForReply(after id: String) {
        isTyping = true
        Task { [weak self] in
            defer { self?.isTyping = false }
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !MagziWebSocket.shared.isConnected else { return }
                await self.reload()
                guard let mine = self.messages.firstIndex(where: { $0.id == id }) else { return }
                if self.messages[(mine + 1)...].contains(where: { $0.role == .assistant }) { return }
            }
        }
    }

    private func post(text: String, clientId: String) async {
        let id = "in:\(clientId)"
        do {
            try await MagziAPI.shared.send(text: text, clientMessageId: clientId)
            setStatus(.sent, for: id, onlyIf: [.pending, .failed])
            if !MagziWebSocket.shared.isConnected { pollForReply(after: id) }
            error = nil
            MagziWebSocket.shared.connect()
        } catch {
            setStatus(.failed, for: id, onlyIf: [.pending])
            self.error = error.localizedDescription
            logger.warning("Send failed: \(error.localizedDescription)")
        }
    }

    private func handle(_ event: MagziLiveEvent) {
        switch event {
        case .ready:
            // (Re)connected: frames may have been dropped, so resync the newest page.
            Task { await reload() }
        case .messageAccepted(let conv, let messageId, let text):
            guard isOurs(conv), !messageId.isEmpty else { return }
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                if messages[index].status != .delivered { messages[index].status = .sent }
            } else {
                upsert(MagziChatMessage(id: messageId, role: .user, text: text, status: .sent, channel: "app",
                                        clientMessageId: messageId.hasPrefix("in:") ? String(messageId.dropFirst(3)) : nil))
            }
        case .typing(let conv, let composing):
            guard isOurs(conv) else { return }
            isTyping = composing
        case .messageDelta(let conv, let delta, let round, let seq):
            guard isOurs(conv) else { return }
            applyDelta(delta, round: round, seq: seq)
        case .messageDone(let conv, let done):
            guard isOurs(conv) else { return }
            // A proactive line can land mid-reply; only the reply itself ends the stream.
            if !done.isProactive { finishStream() }
            var message = MagziChatMessage(
                id: done.messageId, role: .assistant, text: done.text ?? "",
                createdAt: (done.createdAtMs ?? Date().magziMs).magziDate, status: .delivered,
                isProactive: done.isProactive, channel: "app", meta: done.meta
            )
            if let existing = messages.first(where: { $0.id == done.messageId }) { message.createdAt = existing.createdAt }
            upsert(message)
        case .threadLine, .realityChanged, .unknown:
            break
        }
    }

    private func isOurs(_ conversationId: String) -> Bool {
        guard let app = appConversationId else { return false }
        return conversationId.isEmpty || conversationId == app
    }

    private func applyDelta(_ delta: String, round: Int, seq: Int) {
        if round > streamRound {
            // A new model call replaces the preview.
            streamRound = round
            streamParts = [:]
        } else if round < streamRound {
            return
        }
        streamParts[seq] = delta
        streamingText = Self.cleanPlaceholders(streamParts.keys.sorted().compactMap { streamParts[$0] }.joined())
        isTyping = true
        upsert(MagziChatMessage(id: MagziChatMessage.streamingId, role: .assistant, text: streamingText,
                                createdAt: messages.last(where: { $0.isStreaming })?.createdAt ?? Date(), status: .streaming))
    }

    private func finishStream() {
        isTyping = false
        streamingText = ""
        streamRound = 0
        streamParts = [:]
        messages.removeAll { $0.id == MagziChatMessage.streamingId }
    }

    /// `<PARTNER_1>`-style redaction placeholders render as `…`.
    private static func cleanPlaceholders(_ text: String) -> String {
        text.replacingOccurrences(of: "<[A-Z][A-Z0-9_]*>", with: "…", options: .regularExpression)
    }

    private func setStatus(_ status: MagziChatMessage.Status, for id: String, onlyIf allowed: Set<MagziChatMessage.Status>) {
        guard let index = messages.firstIndex(where: { $0.id == id }), allowed.contains(messages[index].status) else { return }
        messages[index].status = status
    }

    private func upsert(_ message: MagziChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        sortMessages()
    }

    private func merge(_ page: [MagziMessage]) {
        var byId: [String: MagziChatMessage] = [:]
        let sameConversation = loadedConversationId == conversationId
        // Same conversation: keep everything (older pages too); otherwise only local-only bubbles. Server rows win.
        for m in messages where sameConversation || m.status != .delivered { byId[m.id] = m }
        loadedConversationId = conversationId
        for row in page {
            var incoming = MagziChatMessage(row)
            if let existing = byId[row.messageId] {
                incoming.isProactive = existing.isProactive
                incoming.meta = existing.meta
            }
            byId[row.messageId] = incoming
        }
        messages = Array(byId.values)
        sortMessages()
    }

    private func sortMessages() {
        messages.sort { a, b in
            if a.isStreaming != b.isStreaming { return b.isStreaming }
            return a.createdAt == b.createdAt ? a.id < b.id : a.createdAt < b.createdAt
        }
    }
}
