import AppKit

enum BrowserMenuCommand: String, CaseIterable, Identifiable {
    case newTab, closeTab, newWindow, addBookmark, hardRefresh, fullScreen
    case welcome, website, repository, unlikeOtherAI
    var id: String { rawValue }

    static let tabs: [Self] = [.newTab, .closeTab, .newWindow]
    static let tools: [Self] = [.addBookmark, .hardRefresh]
    static let help: [Self] = [.website, .repository, .unlikeOtherAI]

    var title: String {
        switch self {
        case .newTab: return "New Tab"
        case .closeTab: return "Close Tab"
        case .newWindow: return "New Window"
        case .addBookmark: return "Add bookmark"
        case .hardRefresh: return "Hard Refresh"
        case .fullScreen: return "Toggle Full Screen"
        case .welcome: return "Show Welcome Screen"
        case .website: return "Open Kelpie Website"
        case .repository: return "Open GitHub Repository"
        case .unlikeOtherAI: return "Open UnlikeOtherAI"
        }
    }

    var key: Character? {
        switch self {
        case .newTab: return "t"
        case .closeTab: return "w"
        case .newWindow: return "n"
        case .addBookmark: return "d"
        case .hardRefresh: return "r"
        case .fullScreen: return "f"
        default: return nil
        }
    }

    @MainActor
    func perform(in session: KelpieBrowserSession) {
        guard !session.isClosed, !session.serverState.isScriptRecording else { return }
        switch self {
        case .newTab: BrowserCommandRouter.shared.newTab()
        case .closeTab: BrowserCommandRouter.shared.closeTab()
        case .newWindow: session.openWindow()
        case .addBookmark: BrowserCommandRouter.shared.addBookmark()
        case .hardRefresh: BrowserCommandRouter.shared.hardReload()
        case .fullScreen: WindowRegistry.shared.defaultEntry()?.ownedWindow?.toggleFullScreen(nil)
        case .welcome:
            NotificationCenter.default.post(name: .showWelcomeCard, object: WelcomeCardPresentationSource.helpMenu.rawValue)
        case .website: open("https://unlikeotherai.github.io/kelpie")
        case .repository: open("https://github.com/UnlikeOtherAI/kelpie")
        case .unlikeOtherAI: open("https://unlikeotherai.com")
        }
    }

    @MainActor
    private func open(_ value: String) {
        if let url = URL(string: value) { NSWorkspace.shared.open(url) }
    }
}
