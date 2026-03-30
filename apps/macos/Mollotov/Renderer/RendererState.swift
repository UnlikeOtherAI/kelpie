import Foundation

/// Observable state tracking which renderer is active and switch-in-progress status.
@MainActor
final class RendererState: ObservableObject {
    enum Engine: String, CaseIterable {
        case webkit = "webkit"
        case chromium = "chromium"

        var displayName: String {
            switch self {
            case .webkit: return "Safari (WebKit)"
            case .chromium: return "Chrome (Chromium)"
            }
        }
    }

    @Published var activeEngine: Engine {
        didSet { UserDefaults.standard.set(activeEngine.rawValue, forKey: "com.mollotov.renderer-engine") }
    }
    @Published var isSwitching: Bool = false

    init() {
        let saved = UserDefaults.standard.string(forKey: "com.mollotov.renderer-engine") ?? ""
        self.activeEngine = Engine(rawValue: saved) ?? .webkit
    }
}
