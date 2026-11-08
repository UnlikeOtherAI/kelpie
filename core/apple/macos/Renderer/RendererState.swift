import Foundation

/// Observable state tracking which renderer is active and switch-in-progress status.
@MainActor
final class RendererState: ObservableObject {
    enum Engine: String, CaseIterable {
        case webkit
        case chromium

        static var allCases: [Self] {
            #if KELPIE_WEBKIT_ONLY
            return [.webkit]
            #else
            return [.webkit, .chromium]
            #endif
        }

        var displayName: String {
            switch self {
            case .webkit: return "Safari (WebKit)"
            case .chromium: return "Chrome (Chromium)"
            }
        }
    }

    @Published var activeEngine: Engine {
        didSet {
            if activeEngine != oldValue { NessieConnection.shared.personChangedTab() }
            KelpieStorage.defaults.set(activeEngine.rawValue, forKey: "com.kelpie.renderer-engine")
        }
    }
    @Published var isSwitching: Bool = false

    init() {
        let saved = KelpieStorage.defaults.string(forKey: "com.kelpie.renderer-engine") ?? ""
        let selected = Engine(rawValue: saved) ?? .webkit
        self.activeEngine = Engine.allCases.contains(selected) ? selected : .webkit
    }
}
