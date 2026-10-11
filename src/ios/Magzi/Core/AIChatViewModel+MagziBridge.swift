import Foundation

// MARK: - Magzi bridge tools
//
// Lets the on-device ad-hoc agent (running on the 9router gateway) hand work to the
// household's 24/7 Magzi agent, and read live household state. Registered only while
// the app is paired with Magzi.

extension AIChatViewModel {

    static let magziBridgeToolNames: Set<String> = ["magzi_ask", "magzi_household"]

    func makeMagziBridgeTools() -> [AgentToolDefinition] {
        guard MagziAuthStore.shared.isPaired else { return [] }
        return [
            AgentToolDefinition(
                name: "magzi_ask",
                description: "Delegate a request to Magzi, the household's always-on agent running on the homelab. Magzi owns capabilities this device does not: WhatsApp/email messaging, reminders, tasks, goals and cron automations, household lists/chores/meals/bills, Google Workspace (Gmail, Calendar, Drive, Docs), finance portfolio and crypto trader desk, market news, research scout, Instagram studio, Magziflex media requests, Home Assistant, Nextcloud, homelab service status, and long-term memory about the family. Use it whenever the task needs one of those, or needs something to keep happening after this chat ends. Write the request as a complete instruction. Returns Magzi's reply text.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user (e.g. 'Ask Magzi to set a reminder'). Use the same language as the user."),
                    "request": AgentToolParam(type: .string, description: "The full instruction or question for Magzi."),
                    "timeout": AgentToolParam(type: .integer, description: "Seconds to wait for Magzi's reply (default 240, max 600)."),
                ],
                required: ["tool_title", "request"],
                propertyOrdering: ["tool_title", "request", "timeout"]
            ),
            AgentToolDefinition(
                name: "magzi_household",
                description: "Read live household data from Magzi as JSON. Views: items (open to-dos/shopping), rota (chores next 7 days), meals (this week's dinner plan), bills (due in 30 days + renewals), approvals (pending), reality (this week's planned vs done, slipping items), presence (who is home/away), facts (household facts), events (recent changes), households (list). To change anything, use magzi_ask.",
                parameters: [
                    "tool_title": AgentToolParam(type: .string, description: "A concise 5-10 word summary of what this tool call does, shown to the user. Use the same language as the user."),
                    "view": AgentToolParam(type: .string, description: "Which data to read.", enumValues: ["items", "rota", "meals", "bills", "approvals", "reality", "presence", "facts", "events", "households"]),
                    "household_id": AgentToolParam(type: .string, description: "Optional household id; defaults to the household selected in the app."),
                ],
                required: ["tool_title", "view"],
                propertyOrdering: ["tool_title", "view", "household_id"]
            ),
        ]
    }

    func executeMagziBridgeTool(name: String, argsJson: String) async -> FileToolResult {
        let args = (argsJson.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        do {
            switch name {
            case "magzi_ask":
                guard let request = (args["request"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !request.isEmpty else {
                    return FileToolResult(output: "Error: Missing required 'request' parameter", success: false)
                }
                let timeout = min(max(args["timeout"] as? Int ?? 240, 10), 600)
                return try await magziAsk(request, timeout: TimeInterval(timeout))
            default:
                return try await magziHousehold(view: args["view"] as? String ?? "", householdId: args["household_id"] as? String)
            }
        } catch is CancellationError {
            return FileToolResult(output: "Cancelled.", success: false)
        } catch where Task.isCancelled {
            return FileToolResult(output: "Cancelled.", success: false)
        } catch {
            return FileToolResult(output: "Magzi error: \(error.localizedDescription)", success: false)
        }
    }

    private func magziAsk(_ request: String, timeout: TimeInterval) async throws -> FileToolResult {
        guard let user = MagziAuthStore.shared.user else { throw MagziError.notConfigured }
        let api = MagziAPI.shared
        let conversation = user.appConversationId
        let sentAt = Date().magziMs
        let clientId = UUID().uuidString
        _ = try await api.send(text: request, clientMessageId: clientId)
        // ponytail: polls history for the first Magzi line after our send; a proactive
        // line landing in the same window would be taken as the reply. Switch to
        // correlating message.done on the socket if the server starts echoing a reply-to id.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let recent = try await api.messages(conversationId: conversation, limit: 10)
            // Server clock: anchor on our own stored row (device clocks can skew); fall back to the send time.
            let anchor = recent.first(where: { $0.messageId == "in:\(clientId)" })?.createdAtMs ?? sentAt
            if let reply = recent.first(where: { $0.direction == "out" && ($0.createdAtMs ?? 0) >= anchor }),
               let text = reply.text, !text.isEmpty {
                return FileToolResult(output: text, success: true)
            }
        }
        return FileToolResult(output: "Magzi accepted the request but hasn't replied within \(Int(timeout))s. It keeps working in the background; the reply will appear in the Magzi tab.", success: true)
    }

    private func magziHousehold(view: String, householdId: String?) async throws -> FileToolResult {
        let api = MagziAPI.shared
        if view == "households" { return try encode(try await api.households()) }
        var hid = householdId ?? MagziHub.shared.selectedHouseholdId
        if hid == nil { hid = try await api.households().first?.id }
        guard let hid else { return FileToolResult(output: "No household is linked to this login.", success: false) }
        switch view {
        case "items": return try encode(try await api.items(householdId: hid))
        case "rota": return try encode(try await api.rota(householdId: hid))
        case "meals": return try encode(try await api.meals(householdId: hid))
        case "bills": return try encode(try await api.bills(householdId: hid))
        case "approvals": return try encode(try await api.approvals(householdId: hid))
        case "reality": return try encode(try await api.reality(householdId: hid))
        case "presence": return try encode(try await api.presence(householdId: hid))
        case "facts": return try encode(try await api.facts(householdId: hid))
        case "events": return try encode(try await api.events(householdId: hid))
        default: return FileToolResult(output: "Error: unknown view '\(view)'", success: false)
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> FileToolResult {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let text = String(decoding: try enc.encode(value), as: UTF8.self)
        return FileToolResult(output: text.count > 30_000 ? String(text.prefix(30_000)) + "\n…(truncated)" : text, success: true)
    }
}
