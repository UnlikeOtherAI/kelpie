import Foundation

extension Notification.Name {
    /// Posted when the Chromium renderer finishes loading a document. Chromium has no
    /// cookie observer, so this is the signal that its store may have changed.
    static let kelpieChromiumDocumentLoaded = Notification.Name("kelpie.chromiumDocumentLoaded")
}

/// The live default cookie store: WebKit's default store while WebKit renders and
/// Chromium's global store while Chromium renders. Partitioned tabs never resolve here.
///
/// Every programmatic access goes through `exclusive`, one operation at a time, so a sync
/// write and its read-back, an agent's import and a renderer switch never interleave.
@MainActor
final class DefaultCookieStore {
    enum Engine: Equatable {
        case webkit
        case chromium
    }

    private(set) var engine: Engine
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(engine: Engine) {
        self.engine = engine
    }

    /// Deletes the file the retired shared cookie jar kept: a plaintext copy of every cookie
    /// that nothing reads any more.
    static func removeRetiredJar() {
        let jar = KelpieStorage.homeDirectory
            .appendingPathComponent(".kelpie/session/cookies.json", isDirectory: false)
        try? FileManager.default.removeItem(at: jar)
    }

    /// Records the engine the session starts with, before any cookie access.
    func adoptInitialEngine(_ initial: Engine) {
        engine = initial
    }

    /// The store for the active engine.
    var jar: CookieJar {
        switch engine {
        case .webkit:
            return .webKit(KelpieWebsiteData.store.httpCookieStore)
        case .chromium:
            #if KELPIE_WEBKIT_ONLY
            preconditionFailure("Chromium is unavailable in this build")
            #else
            return .chromium
            #endif
        }
    }

    /// Runs `body` with sole access to the live store.
    func exclusive<T>(_ body: (CookieJar) async throws -> T) async rethrows -> T {
        while busy {
            await withCheckedContinuation { waiters.append($0) }
        }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return try await body(jar)
    }

    /// A renderer switch: every cookie of the outgoing engine is copied into the incoming
    /// engine's store, which then becomes the live store.
    @discardableResult
    func switchEngine(to target: Engine) async -> CookieCopier.Report {
        await exclusive { source in
            guard target != engine else { return CookieCopier.Report() }
            engine = target
            let report = await CookieCopier.copyAll(from: source, to: jar)
            if report.sourceUnreadable || !report.failed.isEmpty {
                NSLog(
                    "[DefaultCookieStore] renderer switch copied %d cookies, %d refused, source readable: %@",
                    report.copied,
                    report.failed.count,
                    report.sourceUnreadable ? "no" : "yes"
                )
            }
            return report
        }
    }
}
