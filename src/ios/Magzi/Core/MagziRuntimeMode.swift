import Foundation

/// Runtime metadata. Normal chat stays local 9router; Homecloud is a separate Magzi surface.
enum MagziRuntimeMode: String, Codable, CaseIterable, Identifiable {
    case homecloud
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homecloud: return "Homecloud"
        case .local: return "9router"
        }
    }

    var badgeSystemImage: String {
        switch self {
        case .homecloud: return "cloud.fill"
        case .local: return "sparkles"
        }
    }
}

@MainActor
final class MagziRuntimePreferences: ObservableObject {
    static let shared = MagziRuntimePreferences()

    @Published var defaultMode: MagziRuntimeMode {
        didSet { UserDefaults.standard.set(defaultMode.rawValue, forKey: Self.defaultModeKey) }
    }

    private static let defaultModeKey = "magzi.defaultRuntimeMode"

    private init() {
        // Product default: normal chats use the local iOS agent with the seeded
        // 9router provider. Homecloud Magzi is an explicit separate surface.
        defaultMode = .local
        UserDefaults.standard.set(MagziRuntimeMode.local.rawValue, forKey: Self.defaultModeKey)
    }
}

struct MagziSessionRuntimeMetadata: Codable, Equatable {
    var runtimeMode: MagziRuntimeMode
    var remoteThreadId: String?
    var remoteConversationId: String?
    var lastRemoteSyncAt: Date?
    var remoteStatus: String

    static func `default`(_ mode: MagziRuntimeMode = .local) -> Self {
        Self(runtimeMode: mode, remoteThreadId: nil, remoteConversationId: nil, lastRemoteSyncAt: nil, remoteStatus: "pending")
    }
}

@MainActor
final class MagziSessionRuntimeStore: ObservableObject {
    static let shared = MagziSessionRuntimeStore()

    private let key = "magzi.sessionRuntimeMetadata.v1"
    private var cache: [String: MagziSessionRuntimeMetadata] = [:]

    private init() { load() }

    func metadata(for sessionId: String?) -> MagziSessionRuntimeMetadata {
        guard let sessionId, let existing = cache[sessionId] else { return .default(MagziRuntimePreferences.shared.defaultMode) }
        return existing
    }

    func mode(for sessionId: String?) -> MagziRuntimeMode {
        metadata(for: sessionId).runtimeMode
    }

    func setMode(_ mode: MagziRuntimeMode, for sessionId: String) {
        var next = cache[sessionId] ?? .default(mode)
        next.runtimeMode = mode
        cache[sessionId] = next
        save()
        objectWillChange.send()
    }

    func update(_ metadata: MagziSessionRuntimeMetadata, for sessionId: String) {
        cache[sessionId] = metadata
        save()
        objectWillChange.send()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        cache = (try? JSONDecoder().decode([String: MagziSessionRuntimeMetadata].self, from: data)) ?? [:]
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
