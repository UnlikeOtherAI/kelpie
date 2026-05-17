import AppKit
import Foundation

// MARK: - Cookie management (cross-renderer sync)

extension HandlerContext {
    func allCookies() async -> [HTTPCookie] {
        guard let renderer else { return [] }
        if renderer.engineName == "chromium" {
            return SharedCookieJar.load().cookies
        }
        return await renderer.allCookies()
    }

    func setCookie(_ cookie: HTTPCookie) async {
        guard let renderer else { return }
        await renderer.setCookies([cookie])

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
