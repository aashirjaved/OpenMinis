import Foundation

/// Cockpit (owner console) API. One method per route in docs/magzi-api-contract.md §4.
/// Login lives on `MagziCockpitAuth` (`requestCode()`, `verify(code:)`, `logout()`).
@MainActor
final class MagziCockpitAPI {
    static let shared = MagziCockpitAPI()

    private let auth = MagziCockpitAuth.shared
    private init() {}

    private func http() throws -> MagziHTTP { try auth.client() }

    /// C4.
    func state() async throws -> MagziCockpitState {
        try await http().get("/api/state")
    }

    /// C5. `limit` 1–500.
    func usage(limit: Int = 50) async throws -> MagziUsageResponse {
        try await http().get("/api/usage", query: ["limit": String(limit)])
    }

    /// C6.
    func sessions(limit: Int = 60) async throws -> [MagziCockpitSession] {
        let r: MagziCockpitSessionsResponse = try await http().get("/api/sessions", query: ["limit": String(limit)])
        return r.sessions ?? []
    }

    /// C7. Full trace for one conversation.
    func sessionTrace(conversation: String, limit: Int = 200) async throws -> MagziSessionTrace {
        try await http().get("/api/session", query: ["conversation": conversation, "limit": String(limit)])
    }

    /// C8. Recent audit frames, oldest first.
    func watch(session: String? = nil, run: String? = nil, scope: String? = nil, errorsOnly: Bool = false, limit: Int = 50) async throws -> [MagziAuditFrame] {
        let r: MagziWatchResponse = try await http().get("/api/watch", query: [
            "session": session, "run": run, "scope": scope,
            "errors": errorsOnly ? "1" : nil, "limit": String(limit),
        ])
        return r.events ?? []
    }

    /// C9.
    func allow(recipient: String) async throws -> MagziAllowlistResponse {
        try await http().post("/api/allow", json: ["recipient": recipient])
    }

    /// C10.
    func deny(recipient: String) async throws -> MagziAllowlistResponse {
        try await http().post("/api/deny", json: ["recipient": recipient])
    }

    /// C11. Pauses (or resumes) the agent.
    func pause(on: Bool) async throws -> Bool {
        let r: MagziCockpitPauseResponse = try await http().post("/api/pause", json: ["on": on])
        return r.paused ?? on
    }

    /// C12.
    func disableCapability(tool: String) async throws -> MagziCapability {
        try await http().post("/api/capability", json: ["tool": tool, "action": "disable"])
    }

    /// C13. Only the keys in `MagziConfigKey` are accepted. Restart required afterwards.
    func setConfig(_ key: MagziConfigKey, value: Any) async throws -> MagziConfigSetResponse {
        try await http().post("/api/config", json: ["key": key.rawValue, "value": value])
    }

    /// C14.
    func rollbackConfig(expectedHash: String) async throws -> MagziConfigSetResponse {
        try await http().post("/api/config/rollback", json: ["expectedHash": expectedHash])
    }

    /// C15.
    func adminInstructions() async throws -> [MagziInstruction] {
        let r: MagziInstructionsResponse = try await http().get("/api/admin-instructions")
        return r.requests ?? []
    }

    /// C16. `scope`: 1–14 relative paths.
    func createAdminInstruction(instruction: String, acceptance: String, scope: [String], idempotencyKey: String = UUID().uuidString) async throws -> MagziInstructionCreateResponse {
        struct Body: Encodable { let idempotencyKey: String; let instruction: String; let acceptance: String; let scope: [String] }
        return try await http().post("/api/admin-instructions", body: Body(
            idempotencyKey: idempotencyKey, instruction: instruction, acceptance: acceptance, scope: scope
        ))
    }

    /// C17.
    func approveAdminInstruction(id: String, head: String) async throws -> Bool {
        let r: MagziInstructionApproveResponse = try await http().post("/api/admin-instructions/approve", json: ["id": id, "head": head])
        return r.approved ?? false
    }

    /// C18.
    func acceptAdminInstruction(id: String, commit: String) async throws -> MagziInstructionAcceptResponse {
        try await http().post("/api/admin-instructions/accept", json: ["id": id, "commit": commit])
    }

    /// C19.
    func restart() async throws -> MagziRestartResponse {
        try await http().post("/api/restart")
    }

    /// C20. No auth required.
    func metricsUsage(limit: Int = 20) async throws -> MagziMetricsUsage {
        try await auth.anonymousClient().get("/metrics/usage", query: ["limit": String(limit)])
    }
}
