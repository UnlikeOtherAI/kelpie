import AppKit
import Foundation
import WebKit

// MARK: - Cookie stores

extension HandlerContext {
    /// A cookie store a request reads or writes: the live default store or one partition.
    struct CookieTarget {
        let jar: CookieJar
        /// nil for the default store.
        let partition: String?
        /// Equal for two targets that name the same store.
        let identity: String

        var isDefault: Bool { identity == Self.defaultIdentity }
        static let defaultIdentity = "default"
    }

    /// True when the active renderer belongs to a partitioned tab. Such a tab has its own
    /// store, so the UOA login hand-over and the default-store paths never touch it.
    var activeRendererIsPartitioned: Bool {
        guard let renderer else { return false }
        return WindowRegistry.shared.allEntriesIncludingDetached().contains { entry in
            entry.tabStore.tabs.contains { $0.partition != nil && $0.renderer === renderer }
        }
    }

    var defaultCookieTarget: CookieTarget {
        CookieTarget(jar: defaultCookies.jar, partition: nil, identity: CookieTarget.defaultIdentity)
    }

    /// The store a resolved renderer uses. Chromium has only the default store.
    func cookieTarget(for renderer: any RendererEngine) -> CookieTarget {
        guard let webKit = renderer as? WKWebViewRenderer,
              webKit.websiteDataStore !== KelpieWebsiteData.store else { return defaultCookieTarget }
        let partition = WindowRegistry.shared.allEntriesIncludingDetached()
            .lazy.flatMap(\.tabStore.tabs).first { $0.renderer === webKit }?.partition
        let identity = partition.map { "partition:\($0)" } ?? "store:\(ObjectIdentifier(webKit.websiteDataStore).hashValue)"
        return CookieTarget(jar: .webKit(webKit.websiteDataStore.httpCookieStore), partition: partition, identity: identity)
    }

    /// Runs `body` on the target store; default-store work waits its turn with sync.
    func withCookies<T>(_ target: CookieTarget, _ body: (CookieJar) async throws -> T) async throws -> T {
        guard profileID == KelpieStorage.profileID else { throw CancellationError() }
        if target.isDefault { return try await defaultCookies.exclusive(body) }
        return try await body(target.jar)
    }
}
