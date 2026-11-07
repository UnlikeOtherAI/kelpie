import AppKit

// MARK: - Cookie operations + injection fallbacks
//
// CEFRenderer delegates cookie reads/writes/deletes to CEFBridge via CDP first,
// with a JS document.cookie fallback for sessions where the CDP path fails.
// All cookie-specific code lives here so the core renderer file stays focused
// on lifecycle, navigation, JS evaluation, and screenshot capture.

extension CEFRenderer {
    func allCookies() async -> [HTTPCookie] {
        guard let bridge else { return [] }
        if let cookies = await withCheckedContinuation({ (continuation: CheckedContinuation<[HTTPCookie]?, Never>) in
            bridge.getAllCookiesViaCDP { success, cookieDicts in
                continuation.resume(returning: success ? Self.cookies(from: cookieDicts) : nil)
            }
        }) {
            return cookies
        }

        return await withCheckedContinuation { continuation in
            let state = CookieContinuationState()

            bridge.getAllCookies { cookieDicts in
                if state.didResume {
                    return
                }
                state.didResume = true

                continuation.resume(returning: Self.cookies(from: cookieDicts))
            }
        }
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        guard bridge != nil else {
            if pendingDeleteAllCookies {
                pendingCookies.removeAll()
            }
            pendingCookies.append(contentsOf: cookies)
            return
        }
        guard !containerView.isHidden else {
            if pendingDeleteAllCookies {
                pendingCookies.removeAll()
            }
            pendingCookies.append(contentsOf: cookies)
            return
        }
        await applyCookiesViaCDP(cookies, primeURLForJSFallback: currentURL, reloadAfterJSErrorFallback: false)
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        guard let bridge else { return }
        let deleted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            bridge.deleteCookie(viaCDP: cookie.name, domain: cookie.domain, path: cookie.path) { success in
                continuation.resume(returning: success)
            }
        }
        if deleted {
            return
        }
        await expireCookiesViaJS([cookie])
    }

    func deleteAllCookies() async {
        guard let bridge else {
            pendingDeleteAllCookies = true
            pendingCookies.removeAll()
            return
        }
        guard !containerView.isHidden else {
            pendingDeleteAllCookies = true
            pendingCookies.removeAll()
            return
        }
        let deletedViaCDP = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            bridge.deleteAllCookiesViaCDP { success, _ in
                continuation.resume(returning: success)
            }
        }
        if deletedViaCDP {
            return
        }
        await expireCookiesViaJS(await allCookies())
    }

    func injectCookiesViaJS(_ cookies: [HTTPCookie], reloadAfterInjection: Bool) {
        guard let bridge, let host = currentURL?.host else { return }
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix(".\(domain)")
        }
        let js = cookieInjectionScript(for: matching)
        guard !js.isEmpty else { return }
        NSLog("[CEFRenderer] injecting %d cookies via JS for host=%@", matching.count, host)
        bridge.evaluateJavaScript(js) { [weak self] _, error in
            if let error {
                NSLog("[CEFRenderer] JS cookie injection error: %@", error.localizedDescription)
            } else if reloadAfterInjection {
                NSLog("[CEFRenderer] JS cookies injected, reloading")
                Task { @MainActor [weak self] in
                    self?.bridge?.reload()
                }
            }
        }
    }

    nonisolated static func cookies(from cookieDicts: [Any]) -> [HTTPCookie] {
        cookieDicts.compactMap { item -> HTTPCookie? in
            guard let dict = item as? [String: Any] else { return nil }
            guard let name = dict["name"] as? String,
                  let value = dict["value"] as? String,
                  let domain = dict["domain"] as? String,
                  let path = dict["path"] as? String else { return nil }

            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path
            ]
            if let httpOnly = dict["httpOnly"] as? Bool, httpOnly {
                props[.init("HttpOnly")] = "TRUE"
            }
            if let secure = dict["secure"] as? Bool, secure {
                props[.secure] = "TRUE"
            }
            if let expires = dict["expires"] as? Date {
                props[.expires] = expires
            } else if let expires = dict["expires"] as? NSNumber, expires.doubleValue > 0 {
                props[.expires] = Date(timeIntervalSince1970: expires.doubleValue)
            }
            if let sameSite = dict["sameSite"] as? String, !sameSite.isEmpty {
                props[HTTPCookiePropertyKey("SameSite")] = sameSite
            }
            return HTTPCookie(properties: props)
        }
    }

    func applyCookiesViaCDP(_ cookies: [HTTPCookie],
                            primeURLForJSFallback: URL?,
                            reloadAfterJSErrorFallback: Bool) async {
        guard let bridge else { return }
        var failedCookies: [HTTPCookie] = []

        for cookie in cookies {
            let set = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                bridge.setCookieViaCDP(
                    cookie.name,
                    value: cookie.value,
                    domain: cookie.domain,
                    path: cookie.path,
                    httpOnly: cookie.isHTTPOnly,
                    secure: cookie.isSecure,
                    sameSite: cookie.sameSitePolicy?.rawValue,
                    expires: cookie.expiresDate
                ) { success in
                    continuation.resume(returning: success)
                }
            }

            if !set {
                failedCookies.append(cookie)
            }
        }

        guard !failedCookies.isEmpty else { return }

        if reloadAfterJSErrorFallback, let urlToPrime = primeURLForJSFallback {
            bridge.loadURL(urlToPrime.absoluteString)
            for _ in 0..<200 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if !bridge.isLoading() { break }
            }
        }

        injectCookiesViaJS(failedCookies, reloadAfterInjection: reloadAfterJSErrorFallback)
    }

    func cookieInjectionScript(for cookies: [HTTPCookie]) -> String {
        var js = ""
        for cookie in cookies where !cookie.isHTTPOnly {
            let cookieName = JSEscape.string(cookie.name)
            let cookieValue = JSEscape.string(cookie.value)
            var parts = "\(cookieName)=\(cookieValue)"
            if !cookie.path.isEmpty { parts += "; path=\(cookie.path)" }
            if !cookie.domain.isEmpty { parts += "; domain=\(cookie.domain)" }
            if cookie.isSecure { parts += "; secure" }
            if let sameSite = cookie.sameSitePolicy?.rawValue, !sameSite.isEmpty {
                parts += "; SameSite=\(sameSite)"
            }
            if let expires = cookie.expiresDate {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.timeZone = TimeZone(identifier: "GMT")
                parts += "; expires=\(formatter.string(from: expires))"
            }
            js += "document.cookie='\(parts)';\n"
        }
        return js
    }

    func expireCookiesViaJS(_ cookies: [HTTPCookie]) async {
        let expiredCookies = cookies.map { cookie in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: cookie.name,
                .value: "",
                .domain: cookie.domain,
                .path: cookie.path,
                .expires: Date(timeIntervalSince1970: 0)
            ]
            if cookie.isSecure {
                properties[.secure] = "TRUE"
            }
            if let sameSite = cookie.sameSitePolicy?.rawValue, !sameSite.isEmpty {
                properties[HTTPCookiePropertyKey("SameSite")] = sameSite
            }
            return HTTPCookie(properties: properties)
        }
        injectCookiesViaJS(expiredCookies.compactMap { $0 }, reloadAfterInjection: false)
    }
}
