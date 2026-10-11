import SwiftUI
import UIKit

extension Notification.Name {
    /// Switch to Ad-hoc and open a fresh local (9router) session. `object` may carry a prompt String.
    static let magziAdhocNewTask = Notification.Name("magziAdhocNewTask")
}

/// Cross-screen navigation: lets any screen switch tabs or hand Magzi chat a starter prompt.
@MainActor
final class MagziRouter: ObservableObject {
    static let shared = MagziRouter()

    enum Tab: Hashable { case home, magzi, household, adhoc, more }

    @Published var tab: Tab = .home
    /// Text to prefill in the Magzi composer; the chat view consumes and clears it.
    @Published var chatDraft: String?
    /// When true the chat view sends `chatDraft` immediately instead of prefilling.
    @Published var sendDraftImmediately = false
    /// Set by `magzi://household/approvals`; the Household view consumes and clears it.
    @Published var showHouseholdApprovals = false
    /// A Household screen to push next (`magzi://household/<route>`); the Household view consumes and clears it.
    @Published var householdRoute: HhRoute?
    /// Set when the Ask Magzi entry asks for dictation; the chat view consumes and clears it.
    @Published var startDictation = false

    func askMagzi(_ prompt: String, send: Bool = false) {
        chatDraft = prompt
        sendDraftImmediately = send
        tab = .magzi
    }

    /// Switch to the Ad-hoc tab and start a new local session (runs on the default 9router group).
    /// A non-empty `prompt` is sent as the session's first message.
    func startAdhocTask(prompt: String? = nil) {
        tab = .adhoc
        // Reuses the Home Screen quick-action workflow: ContentView consumes the trigger on change
        // (or on first appear when the tab was never mounted) and AIChatView sends the prompt once mounted.
        QuickActionRouter.shared.startNewChat(sendingPrompt: prompt ?? "")
    }

    /// Handles `magzi://` deep links. Returns false for anything else so existing handlers run.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "magzi", let host = url.host?.lowercased() else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch host {
        case "chat":
            if let prefill = components?.queryItems?.first(where: { $0.name == "prefill" })?.value, !prefill.isEmpty {
                askMagzi(prefill)
            } else {
                tab = .magzi
            }
        case "household":
            tab = .household
            if path == "approvals" { showHouseholdApprovals = true } else if let r = HhRoute.named(path) { householdRoute = r }
        case "adhoc":
            if path == "new" {
                startAdhocTask(prompt: components?.queryItems?.first(where: { $0.name == "prompt" })?.value)
            } else {
                tab = .adhoc
            }
        default:
            return false
        }
        return true
    }
}
