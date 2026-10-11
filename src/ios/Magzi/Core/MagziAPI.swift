import UIKit

/// Mobile API (`/mobile/v1/*`). One method per route in docs/magzi-api-contract.md §2.
@MainActor
final class MagziAPI {
    static let shared = MagziAPI()

    private let auth = MagziAuthStore.shared
    private init() {}

    private func http() throws -> MagziHTTP { try auth.client() }
    private static let prefix = "/mobile/v1"
    private func hh(_ id: String) -> String { "\(Self.prefix)/households/\(MagziHTTP.segment(id))" }
    private func p(_ path: String) -> String { Self.prefix + path }

    // MARK: Auth / account

    /// Route 1. Email OTP.
    @discardableResult
    func requestLogin(email: String) async throws -> MagziLoginRequestResponse {
        try await auth.anonymousClient().post(p("/login/request"), json: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    /// Route 1. WhatsApp OTP (send the phone exactly as typed again in `verifyLogin`).
    @discardableResult
    func requestLogin(phone: String) async throws -> MagziLoginRequestResponse {
        try await auth.anonymousClient().post(p("/login/request"), json: ["phone": phone.trimmingCharacters(in: .whitespacesAndNewlines)])
    }

    /// Route 2. On success the token/user/session are persisted in `MagziAuthStore`.
    @discardableResult
    func verifyLogin(email: String? = nil, phone: String? = nil, code: String) async throws -> MagziLoginVerifyResponse {
        var body: [String: Any] = [
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
            "deviceId": Self.deviceId,
            "deviceName": String(UIDevice.current.name.prefix(80)),
        ]
        if let phone = phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty {
            body["phone"] = phone
        } else {
            body["email"] = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let response: MagziLoginVerifyResponse = try await auth.anonymousClient().post(p("/login/verify"), json: body)
        auth.save(response)
        return response
    }

    /// Stable per-install device id.
    static var deviceId: String {
        let key = "magzi.mobile.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// Route 3.
    func bootstrap() async throws -> MagziBootstrap {
        let b: MagziBootstrap = try await http().get(p("/bootstrap"))
        auth.update(user: b.user, session: b.session)
        return b
    }

    /// Route 4.
    func me() async throws -> MagziMe {
        let me: MagziMe = try await http().get(p("/me"))
        auth.update(user: me.user)
        return me
    }

    /// Route 5 (admin).
    func users() async throws -> [MagziUser] {
        let r: MagziUsersResponse = try await http().get(p("/users"))
        return r.users ?? []
    }

    /// Route 6 (admin). `role`: admin|family|user|guest.
    func createUser(email: String, displayName: String? = nil, role: String = "user", scopes: [String] = ["chat"]) async throws -> MagziUser {
        var body: [String: Any] = ["email": email, "role": role, "scopes": scopes]
        if let displayName, !displayName.isEmpty { body["displayName"] = displayName }
        let r: MagziUserResponse = try await http().post(p("/users"), json: body)
        return r.user
    }

    /// Route 7 (admin).
    func disableUser(userId: String) async throws -> MagziDisableUserResponse {
        try await http().post(p("/users/disable"), json: ["userId": userId])
    }

    /// Route 8. Own sessions, newest first.
    func sessions() async throws -> [MagziSession] {
        let r: MagziSessionsResponse = try await http().get(p("/sessions"))
        return r.sessions ?? []
    }

    /// Route 9. APNs device token registration.
    func registerDevice(token: String, platform: String = "ios") async throws {
        let _: MagziOK = try await http().post(p("/me/devices"), json: ["token": token, "platform": platform])
    }

    /// Route 10. Keys: brief, quietHours, channel, timeShare, pokeStyle, pokesPerDay, adminRound, pokeOptionsOnly.
    func updatePreferences(_ changes: [String: Any]) async throws -> MagziPreferences {
        try await http().patch(p("/me/preferences"), json: changes)
    }

    /// Route 11.
    func memory() async throws -> MagziMemory {
        try await http().get(p("/me/memory"))
    }

    /// Route 12.
    func forgetMemory(id: Int64) async throws {
        let _: MagziOK = try await http().delete(p("/me/memory/\(id)"))
    }

    /// Route 13.
    func editMemory(id: Int64, text: String) async throws -> MagziNote? {
        let r: MagziNoteResponse = try await http().patch(p("/me/memory/\(id)"), json: ["text": text])
        return r.note
    }

    /// Route 14.
    func activity() async throws -> [MagziActivityEntry] {
        let r: MagziActivityResponse = try await http().get(p("/me/activity"))
        return r.activity ?? []
    }

    /// Route 15. `week` = "YYYY-Www".
    func time(week: String? = nil) async throws -> MagziTimeReport {
        try await http().get(p("/me/time"), query: ["week": week])
    }

    // MARK: Chat

    /// Route 16. `conversationId` is `mobile:<uid>` (no usable paging) or `person:<pid>` (`before` = ms cursor).
    /// Returned oldest → newest.
    func messages(conversationId: String, before: Int64? = nil, limit: Int = 50) async throws -> [MagziMessage] {
        let r: MagziMessagesResponse = try await http().get(
            p("/conversations/\(MagziHTTP.segment(conversationId))/messages"),
            query: ["limit": String(limit), "before": before.map(String.init)]
        )
        return (r.messages ?? []).reversed()
    }

    /// Route 17. Reply streams over the WebSocket.
    @discardableResult
    func send(text: String, clientMessageId: String) async throws -> MagziSendResponse {
        try await http().post(p("/messages"), json: ["text": text, "clientMessageId": clientMessageId])
    }

    // MARK: Households

    /// Route 19.
    func households() async throws -> [MagziHousehold] {
        let r: MagziHouseholdsResponse = try await http().get(p("/households"))
        return r.households ?? []
    }

    /// Route 20.
    func items(householdId: String, view: MagziItemsView = .open) async throws -> [MagziItem] {
        let r: MagziItemsResponse = try await http().get(hh(householdId) + "/items", query: ["view": view.rawValue])
        return r.items ?? []
    }

    /// Route 21. Pass a stable `idempotencyKey` when retrying.
    func captureItem(householdId: String, title: String, kind: String = "task", idempotencyKey: String? = UUID().uuidString) async throws -> MagziItem? {
        var headers: [String: String] = [:]
        if let idempotencyKey { headers["Idempotency-Key"] = idempotencyKey }
        let r: MagziItemResponse = try await http().post(hh(householdId) + "/items", json: ["title": title, "kind": kind], headers: headers)
        return r.item
    }

    /// Route 22. `action`: done | drop | claim.
    func updateItem(id: Int64, householdId: String, action: String) async throws -> MagziItem? {
        let r: MagziItemResponse = try await http().patch(p("/items/\(id)"), json: ["householdId": householdId, "action": action])
        return r.item
    }

    /// Route 23.
    func swapChore(id: Int64, householdId: String, to: String) async throws -> MagziItemResponse {
        try await http().post(p("/items/\(id)/swap"), json: ["householdId": householdId, "to": to])
    }

    /// Route 24.
    func skipChore(id: Int64, householdId: String) async throws -> MagziItemResponse {
        try await http().post(p("/items/\(id)/skip"), json: ["householdId": householdId])
    }

    /// Route 25. Undo an inferred completion.
    func reopenItem(id: Int64, householdId: String) async throws -> MagziItemResponse {
        try await http().post(p("/items/\(id)/reopen"), json: ["householdId": householdId])
    }

    /// Route 26. `action`: drop | park | schedule (needs `when`) | delegate (needs `to`) | reopen.
    func progressItem(id: Int64, householdId: String, action: String, to: String? = nil, when: String? = nil) async throws -> MagziItem? {
        var body: [String: Any] = ["householdId": householdId, "action": action]
        if let to { body["to"] = to }
        if let when { body["when"] = when }
        let r: MagziItemResponse = try await http().post(p("/items/\(id)/progress"), json: body)
        return r.item
    }

    /// Route 27.
    func facts(householdId: String) async throws -> [MagziFact] {
        let r: MagziFactsResponse = try await http().get(hh(householdId) + "/facts")
        return r.facts ?? []
    }

    /// Route 28.
    func putFact(householdId: String, label: String, value: String) async throws {
        let _: MagziOK = try await http().post(hh(householdId) + "/facts", json: ["label": label, "value": value])
    }

    /// Route 29.
    func rota(householdId: String) async throws -> MagziRota {
        let r: MagziRotaResponse = try await http().get(hh(householdId) + "/rota")
        return r.rota ?? MagziRota()
    }

    /// Route 30. Ascending, `cursor > since`.
    func events(householdId: String, since: Int64 = 0) async throws -> [MagziHouseholdEvent] {
        let r: MagziEventsResponse = try await http().get(hh(householdId) + "/events", query: ["since": String(since)])
        return r.events ?? []
    }

    /// Route 31.
    func meals(householdId: String) async throws -> MagziMeals {
        try await http().get(hh(householdId) + "/meals")
    }

    /// Route 32.
    func bills(householdId: String) async throws -> MagziBills {
        try await http().get(hh(householdId) + "/bills")
    }

    /// Route 33. Latest weekly summary PDF (404 when none yet).
    func summaryPDF(householdId: String) async throws -> Data {
        try await http().data(hh(householdId) + "/summary/latest").0
    }

    /// Route 34. Household chat, returned oldest → newest. `before` = line id.
    func thread(householdId: String, before: Int64? = nil, limit: Int = 50) async throws -> [MagziThreadLine] {
        let r: MagziThreadResponse = try await http().get(
            hh(householdId) + "/thread",
            query: ["before": before.map(String.init), "limit": String(limit)]
        )
        return (r.lines ?? []).reversed()
    }

    /// Route 35.
    @discardableResult
    func postThread(householdId: String, text: String, clientMessageId: String = UUID().uuidString) async throws -> MagziThreadPostResponse {
        try await http().post(hh(householdId) + "/thread", json: ["text": text, "clientMessageId": clientMessageId])
    }

    /// Route 36. `week` = "YYYY-Www".
    func reality(householdId: String, week: String? = nil) async throws -> MagziReality {
        try await http().get(hh(householdId) + "/reality", query: ["week": week])
    }

    /// Route 37.
    func presence(householdId: String) async throws -> [MagziPresence] {
        let r: MagziPresenceResponse = try await http().get(hh(householdId) + "/presence")
        return r.presence ?? []
    }

    // MARK: Approvals

    /// Route 38. Pending only.
    func approvals(householdId: String) async throws -> [MagziApproval] {
        let r: MagziApprovalsResponse = try await http().get(hh(householdId) + "/approvals")
        return r.approvals ?? []
    }

    /// Route 39.
    func approve(id: Int64) async throws -> MagziApproval? {
        let r: MagziApprovalResponse = try await http().post(p("/approvals/\(id)/approve"))
        return r.approval
    }

    /// Route 40.
    func deny(id: Int64) async throws -> MagziApproval? {
        let r: MagziApprovalResponse = try await http().post(p("/approvals/\(id)/deny"))
        return r.approval
    }

    // MARK: Membership

    /// Route 41. `phone` wins over `email`.
    func invite(householdId: String, name: String, role: String, phone: String? = nil, email: String? = nil) async throws -> MagziInvite? {
        var body: [String: Any] = ["name": name, "role": role]
        if let phone, !phone.isEmpty { body["phone"] = phone }
        if let email, !email.isEmpty { body["email"] = email }
        let r: MagziInviteResponse = try await http().post(hh(householdId) + "/invites", json: body)
        return r.invite
    }

    /// Route 42. Accepts a raw code or a `magzi://invite/<code>` link.
    func acceptInvite(code: String) async throws -> MagziInviteAcceptResponse {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.hasPrefix("magzi://invite/") ? String(trimmed.dropFirst("magzi://invite/".count)) : trimmed
        return try await http().post(p("/invites/accept"), json: ["code": raw])
    }

    /// `GET /households/:id/members` — everyone with their role and person id.
    func members(householdId: String) async throws -> MagziMembersResponse {
        try await http().get(hh(householdId) + "/members")
    }

    /// Route 43.
    func leave(householdId: String) async throws -> MagziLeaveReport? {
        let r: MagziLeaveResponse = try await http().post(hh(householdId) + "/leave")
        return r.report
    }

    /// Route 44.
    func removeMember(householdId: String, personId: String) async throws -> MagziLeaveReport? {
        let r: MagziLeaveResponse = try await http().post(hh(householdId) + "/members/remove", json: ["personId": personId])
        return r.report
    }

    // MARK: Admin

    /// Route 45 (admin).
    func adminStatus() async throws -> MagziAdminStatus {
        try await http().get(p("/admin/status"))
    }

    /// Route 46 (admin). `hours` clamps 0.25–336 server-side.
    func adminPause(on: Bool = true, hours: Double = 12) async throws -> MagziPauseResponse {
        try await http().post(p("/admin/pause"), json: ["on": on, "hours": hours])
    }

    /// Route 47 (admin).
    func adminQR() async throws -> MagziAdminQR {
        try await http().get(p("/admin/qr"))
    }

    // MARK: Ambient context

    /// Route 48. ≤1000 rows per batch.
    func ingestVisits(_ visits: [MagziContextVisit]) async throws -> MagziContextReport {
        struct Body: Encodable { let visits: [MagziContextVisit] }
        return try await http().post(p("/me/context/visits"), body: Body(visits: visits))
    }

    /// Route 49.
    func ingestActivities(_ activities: [MagziContextActivity]) async throws -> MagziContextReport {
        struct Body: Encodable { let activities: [MagziContextActivity] }
        return try await http().post(p("/me/context/activities"), body: Body(activities: activities))
    }

    /// Route 50.
    func ingestWorkouts(_ workouts: [MagziContextWorkout]) async throws -> MagziContextReport {
        struct Body: Encodable { let workouts: [MagziContextWorkout] }
        return try await http().post(p("/me/context/workouts"), body: Body(workouts: workouts))
    }

    /// Route 51. `expiresAt` must be ≤ 2 h ahead.
    func liveLocation(lat: Double, lng: Double, expiresAt: Int64, at: Int64? = nil) async throws -> MagziLiveLocationResponse {
        var body: [String: Any] = ["lat": lat, "lng": lng, "expiresAt": expiresAt]
        if let at { body["at"] = at }
        return try await http().post(p("/me/context/location"), json: body)
    }

    /// Route 52. `state`: home|away|moving|work|school|gym.
    func presenceHeartbeat(state: String, at: Int64? = nil) async throws -> MagziHeartbeatResponse {
        var body: [String: Any] = ["state": state]
        if let at { body["at"] = at }
        return try await http().post(p("/me/context/presence/heartbeat"), json: body)
    }

    /// Route 53.
    func sharing() async throws -> MagziSharing {
        let r: MagziSharingResponse = try await http().get(p("/me/context/sharing"))
        return r.sharing ?? MagziSharing()
    }

    /// Route 54. Always sends the full object (missing keys reset to defaults server-side).
    func updateSharing(_ sharing: MagziSharing) async throws -> MagziSharing {
        let r: MagziSharingResponse = try await http().put(p("/me/context/sharing"), body: sharing)
        return r.sharing ?? sharing
    }

    /// Route 55.
    func places() async throws -> [MagziPlace] {
        let r: MagziPlacesResponse = try await http().get(p("/me/places"))
        return r.places ?? []
    }

    /// Route 56.
    func updatePlace(id: Int64, name: String? = nil, kind: String? = nil, shared: Bool? = nil) async throws -> MagziPlace? {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let kind { body["kind"] = kind }
        if let shared { body["shared"] = shared }
        let r: MagziPlaceResponse = try await http().put(p("/me/places/\(id)"), json: body)
        return r.place
    }

    /// Route 57. `day` = "YYYY-MM-DD" (default today in the person's timezone).
    func timeline(day: String? = nil) async throws -> MagziTimeline {
        try await http().get(p("/me/timeline"), query: ["day": day])
    }

    /// Route 58.
    func confirmEpisode(id: Int64) async throws {
        let _: MagziOK = try await http().post(p("/me/timeline/\(id)/confirm"))
    }

    /// Route 59. `kind`: gym|eating_out|at_work|at_school|school_run|errand|commute|home|away|sensitive.
    func correctEpisode(id: Int64, kind: String, placeName: String? = nil) async throws -> MagziEpisode? {
        var body: [String: Any] = ["kind": kind]
        if let placeName, !placeName.isEmpty { body["placeName"] = placeName }
        let r: MagziEpisodeResponse = try await http().post(p("/me/timeline/\(id)/correct"), json: body)
        return r.episode
    }
}
