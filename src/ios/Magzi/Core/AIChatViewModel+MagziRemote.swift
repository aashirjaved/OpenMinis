import Foundation

extension AIChatViewModel {
    @MainActor
    var magziRuntimeMode: MagziRuntimeMode {
        get { MagziSessionRuntimeStore.shared.mode(for: sessionId) }
        set {
            guard let sessionId else { return }
            MagziSessionRuntimeStore.shared.setMode(newValue, for: sessionId)
        }
    }

    @MainActor
    func setMagziRuntimeMode(_ mode: MagziRuntimeMode) {
        if let sessionId {
            MagziSessionRuntimeStore.shared.setMode(mode, for: sessionId)
        } else {
            MagziRuntimePreferences.shared.defaultMode = mode
        }
    }
}
