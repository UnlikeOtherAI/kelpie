import AppKit
import Foundation

// MARK: - Cookie management (cross-renderer sync)

extension HandlerContext {
    /// True when the renderer the cookie sync would act on belongs to a
    /// partitioned tab.
    ///
    /// `SharedCookieJar` is not a passive snapshot: a poller pushes its
    /// contents into the active renderer and writes that renderer's cookies
    /// back every two seconds. Letting a partitioned tab join would hand it
    /// every other tab's cookies and leak its own into the shared file, which
    /// is exactly the isolation the partition was created to provide. Every
    /// shared-jar path below therefore excludes partitioned tabs and operates
    /// on the tab's own `websiteDataStore.httpCookieStore` instead.
    var activeRendererIsPartitioned: Bool {
        guard let renderer else { return false }
        return WindowRegistry.shared.allEntries().contains { entry in
            entry.tabStore.tabs.contains { $0.partition != nil && $0.renderer === renderer }
        }
    }

    func allCookies() async -> [HTTPCookie] {
        guard let renderer else { return [] }
        if activeRendererIsPartitioned {
            return await renderer.allCookies()
        }
        if renderer.engineName == "chromium" {
            return SharedCookieJar.load().cookies
        }
        return await renderer.allCookies()
    }

    func setCookie(_ cookie: HTTPCookie) async {
        guard let renderer else { return }
        await renderer.setCookies([cookie])
        guard !activeRendererIsPartitioned else { return }

        if renderer.engineName == "chromium" {
            var merged = SharedCookieJar.load().cookies
            merged.removeAll { existing in
                existing.domain == cookie.domain &&
                existing.path == cookie.path &&
                existing.name == cookie.name
            }
            merged.append(cookie)
            SharedCookieJar.save(cookies: merged)
            let snapshot = SharedCookieJar.load()
            lastSharedCookieSignature = snapshot.signature
            lastSharedCookieModifiedAt = snapshot.modifiedAt
            return
        }

        await persistRendererCookiesToSharedJar()
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        guard let renderer else { return }
        await renderer.deleteCookie(cookie)
        guard !activeRendererIsPartitioned else { return }

        if renderer.engineName == "chromium" {
            var merged = SharedCookieJar.load().cookies
            merged.removeAll { existing in
                existing.domain == cookie.domain &&
                existing.path == cookie.path &&
                existing.name == cookie.name
            }
            SharedCookieJar.save(cookies: merged)
            let snapshot = SharedCookieJar.load()
            lastSharedCookieSignature = snapshot.signature
            lastSharedCookieModifiedAt = snapshot.modifiedAt
            return
        }

        await persistRendererCookiesToSharedJar()
    }

    func deleteAllCookies() async {
        guard let renderer else { return }
        await renderer.deleteAllCookies()
        guard !activeRendererIsPartitioned else { return }

        if renderer.engineName == "chromium" {
            SharedCookieJar.save(cookies: [])
            let snapshot = SharedCookieJar.load()
            lastSharedCookieSignature = snapshot.signature
            lastSharedCookieModifiedAt = snapshot.modifiedAt
            return
        }

        await persistRendererCookiesToSharedJar()
    }

    func syncSharedCookiesIntoRenderer(force: Bool = false) async {
        guard let renderer else { return }
        guard !activeRendererIsPartitioned else { return }
        let snapshot = SharedCookieJar.load()

        if !force,
           snapshot.signature == lastSharedCookieSignature,
           snapshot.modifiedAt == lastSharedCookieModifiedAt {
            return
        }

        if renderer.engineName == "chromium" && snapshot.cookies.isEmpty {
            // CEF cookie deletion is unstable during renderer switches. The
            // shared jar remains the source of truth, and Chromium no longer
            // tries to wipe its store during activation.
        } else if snapshot.modifiedAt != nil && snapshot.cookies.isEmpty {
            await renderer.deleteAllCookies()
        } else if !snapshot.cookies.isEmpty {
            await renderer.setCookies(snapshot.cookies)
        }
        lastSharedCookieSignature = snapshot.signature
        lastSharedCookieModifiedAt = snapshot.modifiedAt
    }

    func persistRendererCookiesToSharedJar() async {
        guard let renderer else { return }
        guard renderer.engineName != "chromium" else { return }
        guard !activeRendererIsPartitioned else { return }
        let cookies = await renderer.allCookies()
        let signature = SharedCookieJar.signature(for: cookies)
        if signature == lastSharedCookieSignature { return }

        SharedCookieJar.save(cookies: cookies)
        let snapshot = SharedCookieJar.load()
        lastSharedCookieSignature = snapshot.signature
        lastSharedCookieModifiedAt = snapshot.modifiedAt
    }

    func startSharedCookieSync() {
        sharedCookiePoller?.invalidate()
        sharedCookiePoller = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncSharedCookiesIntoRenderer()
                await self?.persistRendererCookiesToSharedJar()
            }
        }
    }

    func stopSharedCookieSync() {
        sharedCookiePoller?.invalidate()
        sharedCookiePoller = nil
    }
}
