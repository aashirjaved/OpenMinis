import Foundation

// Mobile API (`/mobile/v1/*`) models — see docs/magzi-api-contract.md.
// Identifiers are required; everything else is optional so a server tweak never breaks decoding.
// Timestamps are epoch milliseconds (`Int64`); use `.magziDate` to convert.

typealias MagziMs = Int64

// MARK: - Accounts

struct MagziUser: Codable, Hashable, Identifiable, Sendable {
    let userId: String
    var email: String?
    var displayName: String?
    var role: String?
    var scopes: [String]?
    var createdBy: String?
    var createdAtMs: MagziMs?
    var disabledAtMs: MagziMs?

    var id: String { userId }
    var isAdmin: Bool { role == "admin" || (scopes ?? []).contains("admin") }
    var isDisabled: Bool { disabledAtMs != nil }
    var name: String { displayName?.magziNonEmpty ?? email?.magziNonEmpty ?? userId }
    var appConversationId: String { "mobile:\(userId)" }
}

struct MagziSession: Codable, Hashable, Identifiable, Sendable {
    let sessionId: String
    var userId: String?
    var deviceId: String?
    var deviceName: String?
    var createdAtMs: MagziMs?
    var lastSeenAtMs: MagziMs?
    var expiresAtMs: MagziMs?
    var revokedAtMs: MagziMs?

    var id: String { sessionId }
}

/// `/me` person — the only snake_case struct in the API.
struct MagziPerson: Codable, Hashable, Identifiable, Sendable {
    let personId: String
    var displayName: String?

    var id: String { personId }
    var conversationId: String { "person:\(personId)" }

    enum CodingKeys: String, CodingKey {
        case personId = "person_id"
        case displayName = "display_name"
    }
}

struct MagziLoginRequestResponse: Codable, Hashable, Sendable {
    var accepted: Bool?
    var identifier: String?
    var message: String?
}

struct MagziLoginVerifyResponse: Codable, Hashable, Sendable {
    let token: String
    let user: MagziUser
    let session: MagziSession
}

struct MagziBootstrap: Codable, Hashable, Sendable {
    var server: String?
    /// `"ShadowReadonly" | "StagingActive" | "ProductionActive"` (Rust Debug format).
    var mode: String?
    let user: MagziUser
    var session: MagziSession?
    var features: Features?

    struct Features: Codable, Hashable, Sendable {
        var chat: Bool?
        var alerts: Bool?
        var approvals: Bool?
        var push: Bool?
    }

    var isReadOnly: Bool { mode == "ShadowReadonly" }
}

struct MagziMe: Codable, Hashable, Sendable {
    let user: MagziUser
    var person: MagziPerson?
}

struct MagziUsersResponse: Codable, Hashable, Sendable { var users: [MagziUser]? }
struct MagziUserResponse: Codable, Hashable, Sendable { let user: MagziUser }
struct MagziDisableUserResponse: Codable, Hashable, Sendable {
    var changed: Bool?
    var waRevoked: [String]?
}
struct MagziSessionsResponse: Codable, Hashable, Sendable { var sessions: [MagziSession]? }
struct MagziOK: Codable, Hashable, Sendable { var ok: Bool? }

// MARK: - Preferences

struct MagziPreferences: Codable, Hashable, Sendable {
    var quietHours: String?
    var channel: String?
    var brief: Brief?
    var pokes: Pokes?
    var timeShare: Bool?

    struct Brief: Codable, Hashable, Sendable {
        var enabled: Bool?
        /// `""` means the default time.
        var at: String?
    }

    struct Pokes: Codable, Hashable, Sendable {
        var pokeStyle: String?
        var pokesPerDay: Int?
        var adminRound: Bool?
        var pokeOptionsOnly: Bool?
        var learnedFormat: String?
        var learnedHour: Int?
    }
}

// MARK: - Memory / activity / time

struct MagziMemory: Codable, Hashable, Sendable {
    var linked: Bool?
    var personId: String?
    var notes: [MemoryNote]?
    var facts: [MemoryFact]?

    struct MemoryNote: Codable, Hashable, Identifiable, Sendable {
        let id: Int64
        var householdId: String?
        var household: String?
        var about: String?
        var text: String?
        var `private`: Bool?
        var savedAt: MagziMs?
    }

    struct MemoryFact: Codable, Hashable, Identifiable, Sendable {
        var householdId: String?
        var label: String?
        var value: String?
        var updatedAt: MagziMs?

        var id: String { "\(householdId ?? "")|\(label ?? "")" }
    }
}

struct MagziNote: Codable, Hashable, Identifiable, Sendable {
    let id: Int64
    var about: String?
    var text: String?
    var privateTo: String?
    var source: String?
    var createdAt: MagziMs?
}

struct MagziNoteResponse: Codable, Hashable, Sendable { var note: MagziNote? }

struct MagziActivityEntry: Codable, Hashable, Identifiable, Sendable {
    var at: MagziMs?
    var what: String?
    var why: String?
    var household: String?

    var id: String { "\(at ?? 0)|\(what ?? "")" }
}

struct MagziActivityResponse: Codable, Hashable, Sendable { var activity: [MagziActivityEntry]? }

struct MagziTimeLine: Codable, Hashable, Identifiable, Sendable {
    var key: String?
    var label: String?
    var actualMin: Double?
    var plannedMin: Double?
    var changeMin: Double?

    var id: String { key ?? label ?? "" }
}

struct MagziTimeReport: Codable, Hashable, Sendable {
    var week: String?
    var from: MagziMs?
    var to: MagziMs?
    var lines: [MagziTimeLine]?
    var actualMin: Double?
    var plannedMin: Double?
    var share: Bool?
    var household: Household?

    struct Household: Codable, Hashable, Sendable {
        var members: [String]?
        var lines: [MagziTimeLine]?
    }
}

// MARK: - Chat

/// App chat row (`mobile:<uid>`) or person-thread row (`person:<pid>`).
struct MagziMessage: Codable, Hashable, Identifiable, Sendable {
    /// `"in:<clientMessageId>"`, `"out:<id>"`, or `"wa:<n>"` for WhatsApp rows.
    let messageId: String
    var conversationId: String?
    var userId: String?
    /// Person thread only: `"whatsapp" | "app"`.
    var channel: String?
    /// `"in"` (from the user) or `"out"` (from Magzi).
    var direction: String?
    var text: String?
    var createdAtMs: MagziMs?

    var id: String { messageId }
    var isFromUser: Bool { direction == "in" }
    var isWhatsApp: Bool { channel == "whatsapp" }
}

struct MagziMessagesResponse: Codable, Hashable, Sendable { var messages: [MagziMessage]? }

struct MagziSendResponse: Codable, Hashable, Sendable {
    var accepted: Bool?
    var clientMessageId: String?
    var serverMessageId: String?
    var conversationId: String?
    var status: String?
}

// MARK: - Households

/// `neuro::store::Group` — a household (id = WhatsApp group JID).
struct MagziHousehold: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String?
    var enabled: Bool?
    var intensity: String?
    var quietHours: String?
    var morningAt: String?
    var eveningAt: String?
    var weeklyReset: String?
    var pausedUntil: MagziMs?
    var lastUnsolicitedAt: MagziMs?
    var lastCaptureAt: MagziMs?
    var lastConsideredAt: MagziMs?
    var dayKey: String?
    var dayCount: Int?
    var lastMorning: String?
    var lastEvening: String?
    var lastWeekly: String?
    var configHash: String?
    var lastActivityAt: MagziMs?
    var createdAt: MagziMs?
    var coupleCheckin: String?
    var bodyChecks: String?
    var lastCouple: String?
    var lastBody: String?
    var nightBefore: String?
    var lastNightBefore: String?
    var incidentUntil: MagziMs?
    var incidentNote: String?
    var allclearPending: Bool?
    var lowPowerDay: String?
    var tone: String?
    var kind: String?
    var timezone: String?
    var ownerPersonId: String?
    var profileFile: String?
    var calendarGrant: String?

    var title: String { name?.magziNonEmpty ?? id }
    var isPaused: Bool { (pausedUntil ?? 0) > Date().magziMs }
}

struct MagziHouseholdsResponse: Codable, Hashable, Sendable { var households: [MagziHousehold]? }

struct MagziItem: Codable, Hashable, Identifiable, Sendable {
    let id: Int64
    /// `"task" | "shopping" | "decision" | "checkin" | "project" | "idea" | …`
    var kind: String?
    var title: String?
    var owner: String?
    /// `"open" | "done" | "dropped" | "likely" | "past" | "someday" | "merged" | …`
    var status: String?
    var dueAt: MagziMs?
    var dueHasTime: Bool?
    var remindAt: MagziMs?
    var reminded: Bool?
    var firstStep: String?
    var estimateMin: Int?
    var energy: String?
    var notes: String?
    var createdBy: String?
    var createdAt: MagziMs?
    var updatedAt: MagziMs?
    var doneAt: MagziMs?
    var snoozedUntil: MagziMs?
    var warnedStage: Int?
    var area: String?
    var `repeat`: String?
    var rotate: Bool?
    var `private`: Bool?
    var leadMin: Int?
    var projectId: Int64?

    var isOpen: Bool { status == nil || status == "open" }
    var isDone: Bool { status == "done" }
    var isShopping: Bool { kind == "shopping" }
    var dueDate: Date? { dueAt.map(\.magziDate) }
    var isOverdue: Bool { isOpen && (dueAt ?? .max) < Date().magziMs }
}

struct MagziItemsResponse: Codable, Hashable, Sendable { var items: [MagziItem]? }

/// Shared response for item mutations (capture/update/swap/skip/reopen/progress).
struct MagziItemResponse: Codable, Hashable, Sendable {
    var item: MagziItem?
    var message: String?
    var wrongInference: Bool?
    var kind: String?
}

enum MagziItemsView: String, Sendable { case open, mine, shopping, decisions }

struct MagziFact: Codable, Hashable, Identifiable, Sendable {
    var key: String?
    var label: String?
    var value: String?
    var updatedAt: MagziMs?

    var id: String { key ?? label ?? "" }
}

struct MagziFactsResponse: Codable, Hashable, Sendable { var facts: [MagziFact]? }

struct MagziRota: Codable, Hashable, Sendable {
    var people: [String]?
    var week: [PersonWeek]?
    var waiting: [Waiting]?

    struct PersonWeek: Codable, Hashable, Identifiable, Sendable {
        var person: String?
        var chores: [Chore]?
        var id: String { person ?? "" }
    }

    struct Chore: Codable, Hashable, Identifiable, Sendable {
        let itemId: Int64
        var title: String?
        var due: MagziMs?
        var id: Int64 { itemId }
    }

    struct Waiting: Codable, Hashable, Identifiable, Sendable {
        let id: Int64
        var itemId: Int64?
        var title: String?
        var by: String?
        var at: MagziMs?
    }
}

struct MagziRotaResponse: Codable, Hashable, Sendable { var rota: MagziRota? }

struct MagziHouseholdEvent: Codable, Hashable, Identifiable, Sendable {
    let cursor: Int64
    var householdId: String?
    /// Actually the mobile userId of the writer.
    var personId: String?
    var kind: String?
    /// JSON-encoded string — use `decodedPayload` / `item`.
    var payload: String?
    var idempotencyKey: String?
    var at: MagziMs?

    var id: Int64 { cursor }
    var decodedPayload: JSONValue? { JSONValue.parse(payload) }
    var item: MagziItem? { try? decodedPayload?["item"]?.decode(MagziItem.self) }
}

struct MagziEventsResponse: Codable, Hashable, Sendable { var events: [MagziHouseholdEvent]? }

struct MagziMeals: Codable, Hashable, Sendable {
    var plan: [PlanEntry]?
    var saved: [Saved]?

    struct PlanEntry: Codable, Hashable, Identifiable, Sendable {
        var day: String?
        var meal: String?
        var cook: String?
        var quick: Bool?
        var id: String { "\(day ?? "")|\(meal ?? "")" }
    }

    struct Saved: Codable, Hashable, Identifiable, Sendable {
        var name: String?
        var ingredients: [String]?
        var quick: Bool?
        var id: String { name ?? "" }
    }
}

struct MagziBill: Codable, Hashable, Identifiable, Sendable {
    let id: Int64
    var title: String?
    var kind: String?
    var amount: String?
    var payer: String?
    var due: MagziMs?
    var `repeat`: String?

    var dueDate: Date? { due.map(\.magziDate) }
}

struct MagziBills: Codable, Hashable, Sendable {
    var bills: [MagziBill]?
    var renewals: [MagziBill]?
}

struct MagziThreadLine: Codable, Hashable, Identifiable, Sendable {
    let id: Int64
    var speaker: String?
    var text: String?
    var at: MagziMs?
    var fromMagzi: Bool?
    var channel: String?
}

struct MagziThreadResponse: Codable, Hashable, Sendable { var lines: [MagziThreadLine]? }

struct MagziThreadPostResponse: Codable, Hashable, Sendable {
    var accepted: Bool?
    var duplicate: Bool?
    var messageId: String?
    var line: String?
}

struct MagziPresence: Codable, Hashable, Identifiable, Sendable {
    var name: String?
    /// `"home" | "away" | "moving" | "work" | "school" | "gym" | …`
    var state: String?
    var asOf: MagziMs?
    var id: String { name ?? "" }
}

struct MagziPresenceResponse: Codable, Hashable, Sendable { var presence: [MagziPresence]? }

// MARK: - Reality (weekly progress)

/// `[name, count]` tuple (serde tuple → JSON array).
struct MagziNamedCount: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var count: Double

    var id: String { name }

    init(name: String, count: Double) { self.name = name; self.count = count }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = (try? c.decode(String.self)) ?? ""
        count = (try? c.decode(Double.self)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(name)
        try c.encode(count)
    }
}

struct MagziHonesty: Codable, Hashable, Sendable {
    var known: Int?
    var due: Int?
    var knownRate: Double?
    var wrong: Int?
    var inferred: Int?
    var wrongRate: Double?
    var kinds: [Kind]?

    struct Kind: Codable, Hashable, Identifiable, Sendable {
        var kind: String?
        var wrong: Int?
        var total: Int?
        var demoted: Bool?
        var id: String { kind ?? "" }
    }
}

struct MagziHouseholdHonesty: Codable, Hashable, Identifiable, Sendable {
    var householdId: String?
    var name: String?
    var honesty: MagziHonesty?
    var id: String { householdId ?? name ?? "" }
}

struct MagziDriverMetrics: Codable, Hashable, Sendable {
    var pokes: Int?
    var acted: Int?
    var rate: Double?
    var stuck: [Int64]?
    var people: [Person]?
    var groupToday: Int?
    var stage3: Int?
    var capBreaches: Int?
    var rescheduled: Int?
    var rotated: Int?
    var parked: Int?

    struct Person: Codable, Hashable, Identifiable, Sendable {
        var name: String?
        var today: Int?
        var cap: Int?
        var maxDay: Int?
        var id: String { name ?? "" }
    }
}

struct MagziReality: Codable, Hashable, Sendable {
    var week: String?
    var from: MagziMs?
    var to: MagziMs?
    var household: Totals?
    var people: [PersonTotals]?
    var fairLoad: FairLoad?
    var inferred: [Inferred]?
    var slipping: [Slipping]?
    var parked: [Parked]?
    var honesty: MagziHonesty?
    var driver: Driver?

    struct Totals: Codable, Hashable, Sendable {
        var planned: Int?
        var done: Int?
        var confirmed: Int?
        var likely: Int?
        var moved: Int?
        var past: Int?
        var unknown: Int?
        var upcoming: Int?
        var slipping: Int?
        var parked: Int?
        var merged: Int?
    }

    struct PersonTotals: Codable, Hashable, Identifiable, Sendable {
        var name: String?
        var planned: Int?
        var done: Int?
        var id: String { name ?? "" }
    }

    struct FairLoad: Codable, Hashable, Sendable {
        var chores: [MagziNamedCount]?
        var runs: [MagziNamedCount]?
    }

    /// A suggested fix. `needs` says which extra field (`to` / `when`) the progress call requires.
    struct Action: Codable, Hashable, Identifiable, Sendable {
        /// `"drop" | "delegate" | "schedule" | "reopen"`
        var action: String?
        var method: String?
        var path: String?
        var needs: String?
        var id: String { "\(action ?? "")|\(path ?? "")" }
    }

    struct Evidence: Codable, Hashable, Sendable {
        var kind: String?
        var label: String?
        var strength: String?
        var reason: String?
        var person: String?
        var at: MagziMs?
    }

    struct Undo: Codable, Hashable, Sendable {
        var method: String?
        var path: String?
    }

    struct Inferred: Codable, Hashable, Identifiable, Sendable {
        let itemId: Int64
        var title: String?
        var status: String?
        var evidence: Evidence?
        var undo: Undo?
        var id: Int64 { itemId }
    }

    struct Slipping: Codable, Hashable, Identifiable, Sendable {
        let itemId: Int64
        var title: String?
        var owner: String?
        var days: Int?
        var actions: [Action]?
        var id: Int64 { itemId }
    }

    struct Parked: Codable, Hashable, Identifiable, Sendable {
        let itemId: Int64
        var title: String?
        var actions: [Action]?
        var id: Int64 { itemId }
    }

    struct Driver: Codable, Hashable, Sendable {
        var metrics: MagziDriverMetrics?
        var items: [DriverItem]?
    }

    struct Lead: Codable, Hashable, Sendable {
        var days: Double?
        var source: String?
        var why: String?
    }

    struct DriverItem: Codable, Hashable, Identifiable, Sendable {
        let itemId: Int64
        var title: String?
        var owner: String?
        var nextAction: String?
        var startBy: MagziMs?
        var lead: Lead?
        /// `-1` = none.
        var stage: Int?
        var pokes: Int?
        var noPoke: Bool?
        var id: Int64 { itemId }
    }
}

// MARK: - Approvals

struct MagziApproval: Codable, Hashable, Identifiable, Sendable {
    let id: Int64
    var householdId: String?
    var kind: String?
    var summary: String?
    var preview: String?
    var requestedBy: String?
    var requestedByRole: String?
    var expires: MagziMs?
    /// `"pending" | "approved" | "denied" | …`
    var status: String?
    var decision: String?
    var decidedBy: String?

    var isPending: Bool { status == nil || status == "pending" }
}

struct MagziApprovalsResponse: Codable, Hashable, Sendable {
    var approvals: [MagziApproval]?
    var features: [String: Bool]?
}

struct MagziApprovalResponse: Codable, Hashable, Sendable { var approval: MagziApproval? }

// MARK: - Membership

struct MagziInvite: Codable, Hashable, Identifiable, Sendable {
    let code: String
    var householdId: String?
    var name: String?
    var role: String?
    var personId: String?
    var expiresAt: MagziMs?
    /// `"magzi://invite/<code>"`
    var link: String?
    var id: String { code }
}

struct MagziInviteResponse: Codable, Hashable, Sendable { var invite: MagziInvite? }

/// One row of `GET /households/:id/members`.
struct MagziMember: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var role: String?
    var personId: String?
    var me: Bool?
    var owner: Bool?
    var id: String { personId ?? name }
}

struct MagziMembersResponse: Codable, Hashable, Sendable {
    var members: [MagziMember]?
    /// Whether the caller may invite or remove people (adults and admins).
    var canManage: Bool?
}

struct MagziMembership: Codable, Hashable, Sendable {
    var householdId: String?
    var personId: String?
    var name: String?
    var role: String?
    var state: String?
    var joinedAt: MagziMs?
    var leftAt: MagziMs?
}

struct MagziInviteAcceptResponse: Codable, Hashable, Sendable {
    var household: HouseholdRef?
    var membership: MagziMembership?

    struct HouseholdRef: Codable, Hashable, Sendable {
        let id: String
        var name: String?
    }
}

struct MagziLeaveReport: Codable, Hashable, Sendable {
    var householdId: String?
    var personId: String?
    var name: String?
    var state: String?
    var membersRemoved: Int?
    var waRevoked: [String]?
    var sessionsRevoked: Int?
    var approvalsCancelled: [Int64]?
}

struct MagziLeaveResponse: Codable, Hashable, Sendable {
    var left: MagziLeaveReport?
    var removed: MagziLeaveReport?
    var report: MagziLeaveReport? { left ?? removed }
}

// MARK: - Admin (mobile)

struct MagziAdminStatus: Codable, Hashable, Sendable {
    var status: Status?
    var text: String?
    var honesty: [MagziHouseholdHonesty]?
    var driver: [GroupDriver]?

    struct Status: Codable, Hashable, Sendable {
        var startedAt: MagziMs?
        var uptimeMs: MagziMs?
        var whatsappConnectedSince: MagziMs?
        var whatsappState: String?
        var lastInboundAt: MagziMs?
        var lastOutboundAt: MagziMs?
        var llmProvider: String?
        var deadLettersToday: Int?
        var households: [HouseholdBudget]?
        var lastBackupOkAt: MagziMs?
        var latency: [Latency]?
        var pairingQrPending: Bool?
    }

    struct HouseholdBudget: Codable, Hashable, Identifiable, Sendable {
        var householdId: String?
        var name: String?
        var tokensToday: Int64?
        var budget: Int64?
        var id: String { householdId ?? name ?? "" }
    }

    struct Latency: Codable, Hashable, Identifiable, Sendable {
        var path: String?
        var turns: Int?
        var queueP95Ms: Double?
        var readyP95Ms: Double?
        var totalP95Ms: Double?
        var budgetMs: Double?
        var id: String { path ?? "" }
    }

    struct GroupDriver: Codable, Hashable, Identifiable, Sendable {
        var group: String?
        var name: String?
        var driver: MagziDriverMetrics?
        var id: String { group ?? name ?? "" }
    }
}

struct MagziPauseResponse: Codable, Hashable, Sendable {
    var paused: Bool?
    /// `0` when resumed.
    var until: MagziMs?
    var groups: [String]?
}

struct MagziAdminQR: Codable, Hashable, Sendable {
    var pairing: Pairing?
    var whatsappState: String?

    struct Pairing: Codable, Hashable, Sendable {
        var qr: String?
        var at: MagziMs?
    }
}

// MARK: - Ambient context

struct MagziSharing: Codable, Hashable, Sendable {
    var location = false
    var activity = false
    var workouts = false
    var proximity = false
    /// `"" | "self" | "adults" | "household"`
    var presenceVisibleTo = ""
    var sharePlaceNames = false
    var shareWins = false
    var skipSensitive = true
    var liveLocation = false
    var selfWins = true
    var reflection = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MagziSharing()
        location = try c.decodeIfPresent(Bool.self, forKey: .location) ?? d.location
        activity = try c.decodeIfPresent(Bool.self, forKey: .activity) ?? d.activity
        workouts = try c.decodeIfPresent(Bool.self, forKey: .workouts) ?? d.workouts
        proximity = try c.decodeIfPresent(Bool.self, forKey: .proximity) ?? d.proximity
        presenceVisibleTo = try c.decodeIfPresent(String.self, forKey: .presenceVisibleTo) ?? d.presenceVisibleTo
        sharePlaceNames = try c.decodeIfPresent(Bool.self, forKey: .sharePlaceNames) ?? d.sharePlaceNames
        shareWins = try c.decodeIfPresent(Bool.self, forKey: .shareWins) ?? d.shareWins
        skipSensitive = try c.decodeIfPresent(Bool.self, forKey: .skipSensitive) ?? d.skipSensitive
        liveLocation = try c.decodeIfPresent(Bool.self, forKey: .liveLocation) ?? d.liveLocation
        selfWins = try c.decodeIfPresent(Bool.self, forKey: .selfWins) ?? d.selfWins
        reflection = try c.decodeIfPresent(Bool.self, forKey: .reflection) ?? d.reflection
    }
}

struct MagziSharingResponse: Codable, Hashable, Sendable {
    var sharing: MagziSharing?
    var personId: String?
}

struct MagziContextReport: Codable, Hashable, Sendable {
    var inserted: Int?
    var updated: Int?
    var duplicates: Int?
    var rejected: Int?
}

struct MagziContextVisit: Codable, Hashable, Sendable {
    var clientId: String
    var lat: Double
    var lng: Double
    var arrivedAt: MagziMs
    var departedAt: MagziMs?
    var source: String?
}

struct MagziContextActivity: Codable, Hashable, Sendable {
    var clientId: String
    var kind: String
    var at: MagziMs
}

struct MagziContextWorkout: Codable, Hashable, Sendable {
    var clientId: String
    var kind: String
    var startedAt: MagziMs
    var endedAt: MagziMs
    var calories: Double?
}

struct MagziLiveLocationResponse: Codable, Hashable, Sendable {
    var ok: Bool?
    var expiresAt: MagziMs?
}

struct MagziHeartbeatResponse: Codable, Hashable, Sendable {
    var ok: Bool?
    var state: String?
}

struct MagziPlace: Codable, Hashable, Identifiable, Sendable {
    let id: Int64
    var name: String?
    /// `"home" | "work" | "school" | "gym" | "restaurant" | "cafe" | "shop" | "gp" | "family" | "other" | "sensitive"`
    var kind: String?
    var shared: Bool?
    var mine: Bool?
    var learned: Bool?
    var confirmed: Bool?
    var visits: Int?

    var isSensitive: Bool { kind == "sensitive" }
}

struct MagziPlacesResponse: Codable, Hashable, Sendable { var places: [MagziPlace]? }
struct MagziPlaceResponse: Codable, Hashable, Sendable { var place: MagziPlace? }

struct MagziEpisode: Codable, Hashable, Identifiable, Sendable {
    let id: Int64
    var kind: String?
    var label: String?
    var startedAt: MagziMs?
    var endedAt: MagziMs?
    var place: String?
    var placeKind: String?
    var with: [String]?
    var confidence: Double?
    var confirmed: Bool?
}

struct MagziTimeline: Codable, Hashable, Sendable {
    var day: String?
    var episodes: [MagziEpisode]?
    var visits: [Visit]?

    struct Visit: Codable, Hashable, Identifiable, Sendable {
        var arrivedAt: MagziMs?
        var departedAt: MagziMs?
        var place: String?
        var placeKind: String?
        var id: String { "\(arrivedAt ?? 0)|\(place ?? "")" }
    }
}

struct MagziEpisodeResponse: Codable, Hashable, Sendable { var episode: MagziEpisode? }

// MARK: - Live (mobile WebSocket)

/// Raw WS frame: `connection.ready` or the `{type, conversationId, payload, cursor, timestamp}` envelope.
struct MagziEnvelope: Codable, Hashable, Sendable {
    let type: String
    var conversationId: String?
    var payload: JSONValue?
    var cursor: Int64?
    /// RFC 3339 send time.
    var timestamp: String?
    /// Only on `connection.ready`.
    var userId: String?
}

/// Final assistant message (`message.done`).
struct MagziMessageDone: Codable, Hashable, Sendable {
    let messageId: String
    var text: String?
    var direction: String?
    var createdAtMs: MagziMs?
    var proactive: Bool?
    var meta: JSONValue?

    var isProactive: Bool { proactive == true || meta?["proactive"]?.boolValue == true }
    var householdId: String? { meta?["householdId"]?.stringValue }
    var proactiveKind: String? { meta?["kind"]?.stringValue }
}

enum MagziLiveEvent: Hashable, Sendable {
    case ready(userId: String)
    case messageAccepted(conversationId: String, messageId: String, text: String)
    case typing(conversationId: String, composing: Bool)
    case messageDelta(conversationId: String, delta: String, round: Int, seq: Int)
    case messageDone(conversationId: String, MagziMessageDone)
    case threadLine(householdId: String, MagziThreadLine)
    /// A WhatsApp line in my own private chat, pushed live (`person.line`).
    case personLine(conversationId: String, MagziMessage)
    case realityChanged(householdId: String)
    case unknown(MagziEnvelope)

    init(envelope e: MagziEnvelope) {
        let conv = e.conversationId ?? ""
        let p = e.payload
        switch e.type {
        case "connection.ready":
            self = .ready(userId: e.userId ?? "")
        case "message.accepted":
            self = .messageAccepted(
                conversationId: conv,
                messageId: p?["messageId"]?.stringValue ?? "",
                text: p?["text"]?.stringValue ?? ""
            )
        case "typing":
            self = .typing(conversationId: conv, composing: p?["state"]?.stringValue == "composing")
        case "message.delta":
            self = .messageDelta(
                conversationId: conv,
                delta: p?["delta"]?.stringValue ?? "",
                round: p?["round"]?.intValue ?? 1,
                seq: p?["seq"]?.intValue ?? 0
            )
        case "message.done":
            if let done = try? p?.decode(MagziMessageDone.self) {
                self = .messageDone(conversationId: conv, done)
            } else {
                self = .unknown(e)
            }
        case "thread.line":
            if let line = try? p?["line"]?.decode(MagziThreadLine.self) {
                self = .threadLine(householdId: p?["householdId"]?.stringValue ?? conv, line)
            } else {
                self = .unknown(e)
            }
        case "reality.changed":
            self = .realityChanged(householdId: p?["householdId"]?.stringValue ?? conv)
        case "person.line":
            if let line = try? p?["line"]?.decode(MagziMessage.self) {
                self = .personLine(conversationId: conv, line)
            } else {
                self = .unknown(e)
            }
        default:
            self = .unknown(e)
        }
    }

    var conversationId: String? {
        switch self {
        case .messageAccepted(let c, _, _), .typing(let c, _), .messageDelta(let c, _, _, _), .messageDone(let c, _):
            return c
        case .threadLine(let h, _), .realityChanged(let h):
            return h
        case .personLine(let c, _): return c
        case .ready: return nil
        case .unknown(let e): return e.conversationId
        }
    }
}

extension String {
    var magziNonEmpty: String? { isEmpty ? nil : self }
}
