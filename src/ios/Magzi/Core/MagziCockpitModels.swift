import Foundation

// Cockpit API (`/api/*`, `/metrics/usage`, `/ws`) models — see docs/magzi-api-contract.md §4–5.

struct MagziCockpitLoginResponse: Codable, Hashable, Sendable {
    var sent: Bool?
    var throttled: Bool?
}

struct MagziCockpitVerifyResponse: Codable, Hashable, Sendable { let token: String }

struct MagziCockpitState: Codable, Hashable, Sendable {
    /// `"personal" | "family" | "front-desk" | "coworker" | …` (there is no `profile` key).
    var agentProfile: String?
    /// `"ShadowReadonly" | "StagingActive" | "ProductionActive"`
    var mode: String?
    var ownerId: String?
    var primaryChannel: String?
    var paused: Bool?
    var features: [Feature]?
    var allowlist: [String]?
    var allowlistGrants: [String: [Grant]]?
    var whatsappSends: WhatsAppSends?
    var capabilities: [MagziCapability]?
    var honesty: [MagziHouseholdHonesty]?
    /// Raw `config.json` — no fixed schema.
    var config: JSONValue?

    struct Feature: Codable, Hashable, Identifiable, Sendable {
        let name: String
        /// `"on" | "off" | "attention"`
        var state: String?
        var note: String?
        var id: String { name }
        var isOn: Bool { state == "on" }
        var needsAttention: Bool { state == "attention" }
    }

    struct Grant: Codable, Hashable, Sendable {
        var reason: String?
        /// String timestamp.
        var grantedAt: String?
    }

    struct WhatsAppSends: Codable, Hashable, Sendable {
        var lastHour: Window?
        var lastDay: Window?
    }

    struct Window: Codable, Hashable, Sendable {
        var all: Int?
        var proactive: Int?
        var ceiling: Int?
    }
}

struct MagziCapability: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var toolName: String?
    var extensionPath: String?
    /// `"draft" | "validation_failed" | "validated" | "approval_required" | "approved" | "active" | "disabled"`
    var status: String?
    var createdAt: String?
    var validatedAt: String?
    var sourceUserNeed: String?
    /// `"low" | "medium" | "high"`
    var riskLevel: String?
    var checksum: String?
    var sourceChecksum: String?
    var validatedChecksum: String?
    var activatedChecksum: String?
    var approvedAt: String?
    var approvedBy: String?
    var approvalReason: String?
    var approvalRecordId: String?
    var activatedAt: String?

    var isActive: Bool { status == "active" }
    var isDisabled: Bool { status == "disabled" }
}

/// `[label, turns, totalTokens]` tuple used by `byProvider` / `byModel`.
struct MagziTally: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var turns: Int
    var totalTokens: Int64

    var id: String { name }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        name = (try? c.decode(String.self)) ?? ""
        turns = Int((try? c.decode(Double.self)) ?? 0)
        totalTokens = Int64((try? c.decode(Double.self)) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(name)
        try c.encode(turns)
        try c.encode(totalTokens)
    }
}

struct MagziUsageRecord: Codable, Hashable, Identifiable, Sendable {
    var at: MagziMs?
    var channel: String?
    var conversationId: String?
    var provider: String?
    var model: String?
    var inputTokens: Int64?
    var outputTokens: Int64?
    var totalTokens: Int64?
    var iterations: Int?
    var status: String?
    var cacheReadTokens: Int64?
    var cacheWriteTokens: Int64?
    var costTotal: Double?
    var errorKind: String?
    var errorMessage: String?
    var contextBreakdown: [MagziNamedCount]?
    var codeMode: Bool?
    var coreToolCount: Int?
    var personId: String?
    var householdId: String?

    var id: String { "\(at ?? 0)|\(conversationId ?? "")|\(model ?? "")" }
}

struct MagziUsageSummary: Codable, Hashable, Sendable {
    var turns: Int?
    var inputTokens: Int64?
    var outputTokens: Int64?
    var totalTokens: Int64?
    var avgContextTokens: Double?
    var maxContextTokens: Int64?
    var byProvider: [MagziTally]?
    var byModel: [MagziTally]?
    var byHousehold: [HouseholdUsage]?
    var costTotal: Double?
    var recent: [MagziUsageRecord]?

    struct HouseholdUsage: Codable, Hashable, Identifiable, Sendable {
        var household: String?
        var turns: Int?
        var totalTokens: Int64?
        var costTotal: Double?
        var people: Int?
        var id: String { household ?? "" }
    }
}

struct MagziHostMetrics: Codable, Hashable, Sendable {
    var memTotalMb: Double?
    var memUsedMb: Double?
    var memAvailableMb: Double?
    var memUsedPct: Double?
    var procRssMb: Double?
    var cpuCores: Int?
    var load1: Double?
    var load5: Double?
    var load15: Double?
    var cpuLoadPct: Double?
}

struct MagziUsageResponse: Codable, Hashable, Sendable {
    var summary: MagziUsageSummary?
    var recent: [MagziUsageRecord]?
    var host: MagziHostMetrics?
}

struct MagziCockpitSession: Codable, Hashable, Identifiable, Sendable {
    let conversation: String
    var lastInput: String?
    var lastReply: String?
    var ts: MagziMs?
    var turns: Int?
    var id: String { conversation }
}

struct MagziCockpitSessionsResponse: Codable, Hashable, Sendable {
    var sessions: [MagziCockpitSession]?
    var count: Int?
}

/// Audit row. `source` is `"audit"` on watch/WS frames and absent in session traces.
struct MagziAuditFrame: Codable, Hashable, Identifiable, Sendable {
    var time: String?
    var session: String?
    var run: String?
    var scope: String?
    var action: String?
    /// `"ok" | "error" | "skipped"`
    var status: String?
    var summary: String?
    var source: String?

    var id: String { "\(time ?? "")|\(scope ?? "")|\(action ?? "")|\(session ?? "")|\(run ?? "")" }
    var isError: Bool { status == "error" }
}

struct MagziSessionTrace: Codable, Hashable, Sendable {
    var conversation: String?
    var pages: [Page]?
    var events: [MagziAuditFrame]?
    var usage: [Usage]?

    struct Page: Codable, Hashable, Identifiable, Sendable {
        var input: String?
        var reply: String?
        var ts: MagziMs?
        var summary: String?
        var id: String { "\(ts ?? 0)|\(input ?? "")" }
    }

    struct Usage: Codable, Hashable, Identifiable, Sendable {
        var at: MagziMs?
        var provider: String?
        var model: String?
        var inputTokens: Int64?
        var outputTokens: Int64?
        var totalTokens: Int64?
        var cacheReadTokens: Int64?
        var iterations: Int?
        var status: String?
        var contextBreakdown: [MagziNamedCount]?
        var codeMode: Bool?
        var coreToolCount: Int?
        var costTotal: Double?
        var id: String { "\(at ?? 0)|\(model ?? "")" }
    }
}

struct MagziWatchResponse: Codable, Hashable, Sendable {
    var events: [MagziAuditFrame]?
    var count: Int?
}

/// Live pipeline event (backfill has no `source`; live frames carry `source: "bus"`).
struct MagziCockpitEvent: Codable, Hashable, Identifiable, Sendable {
    var seq: Int64?
    var at: MagziMs?
    var session: String?
    var run: String?
    /// `"turn_start" | "layer" | "tool" | "llm" | "message" | "reply" | "turn_end" | …`
    var kind: String?
    var layer: String?
    var name: String?
    /// `"ok" | "error" | "running" | …`
    var status: String?
    var text: String?
    var data: JSONValue?
    var source: String?

    var id: String { seq.map(String.init) ?? "\(at ?? 0)|\(kind ?? "")|\(name ?? "")" }
    var isLive: Bool { source == "bus" }
}

enum MagziCockpitFrame: Hashable, Sendable, Identifiable {
    case event(MagziCockpitEvent)
    case audit(MagziAuditFrame)
    case unknown(JSONValue)

    init(_ json: JSONValue) {
        if json["source"]?.stringValue == "audit", let audit = try? json.decode(MagziAuditFrame.self) {
            self = .audit(audit)
        } else if json["seq"] != nil || json["kind"] != nil, let event = try? json.decode(MagziCockpitEvent.self) {
            self = .event(event)
        } else {
            self = .unknown(json)
        }
    }

    var id: String {
        switch self {
        case .event(let e): return "e:\(e.id)"
        case .audit(let a): return "a:\(a.id)"
        case .unknown(let j): return "u:\(j.hashValue)"
        }
    }
}

struct MagziAllowlistResponse: Codable, Hashable, Sendable {
    var changed: Bool?
    var allowlist: [String]?
}

struct MagziCockpitPauseResponse: Codable, Hashable, Sendable { var paused: Bool? }

struct MagziConfigSetResponse: Codable, Hashable, Sendable {
    var ok: Bool?
    var restartRequired: Bool?
    var rollbackHash: String?
}

/// Keys accepted by `POST /api/config`.
enum MagziConfigKey: String, CaseIterable, Sendable {
    case timezone
    case agentProfile
    case turnConcurrency
    case updateCheckIntervalHours = "updateCheck.intervalHours"
    case backupsRetentionDays = "backups.retentionDays"
}

struct MagziInstruction: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var instruction: String?
    var acceptance: String?
    var scope: [String]?
    /// `"queued" | "awaiting_setup" | "coding" | "verifying" | "awaiting_approval" | "pull_request" |
    /// "awaiting_deploy" | "awaiting_acceptance" | "completed" | "failed"`
    var status: String?
    var detail: String?
    var branch: String?
    var worktree: String?
    var head: String?
    var pr: Int?
    var mergeCommit: String?
    var approvedHead: String?
    var createdAt: MagziMs?
    var updatedAt: MagziMs?
    var notificationQueued: Bool?

    var isTerminal: Bool { status == "completed" || status == "failed" }
    var awaitingApproval: Bool { status == "awaiting_approval" }
    var awaitingAcceptance: Bool { status == "awaiting_acceptance" }
}

struct MagziInstructionsResponse: Codable, Hashable, Sendable { var requests: [MagziInstruction]? }

struct MagziInstructionCreateResponse: Codable, Hashable, Sendable {
    var request: MagziInstruction?
    var queued: Bool?
    var completed: Bool?
}

struct MagziInstructionApproveResponse: Codable, Hashable, Sendable { var approved: Bool? }

struct MagziInstructionAcceptResponse: Codable, Hashable, Sendable {
    var accepted: Bool?
    var notification: String?
}

struct MagziRestartResponse: Codable, Hashable, Sendable {
    var restarted: Bool?
    var service: String?
}

struct MagziMetricsUsage: Codable, Hashable, Sendable {
    var turns: Int?
    var totalTokens: Int64?
    var inputTokens: Int64?
    var outputTokens: Int64?
    var avgContextTokens: Double?
    var maxContextTokens: Int64?
    var byModel: [MagziTally]?
    var recent: [MagziUsageRecord]?
    var host: MagziHostMetrics?
}
