import Foundation

struct NavigationPageSnapshot {
    let url: String
    let title: String

    @MainActor
    static func read(from renderer: any RendererEngine, fallbackURL: String? = nil) async -> Self {
        let fallback = Self(
            url: renderer.currentURL?.absoluteString ?? fallbackURL ?? "",
            title: renderer.currentTitle
        )
        let script = """
        JSON.stringify({
            url: window.location.href || '',
            title: document.title || ''
        })
        """

        do {
            let result = try await renderer.evaluateJS(script)
            guard let payload = payload(from: result) else {
                return fallback
            }
            let liveURL = payload["url"] as? String
            let liveTitle = payload["title"] as? String
            let resolvedURL: String
            if let liveURL, !liveURL.isEmpty {
                resolvedURL = liveURL
            } else {
                resolvedURL = fallback.url
            }
            return Self(
                url: resolvedURL,
                title: liveTitle ?? fallback.title
            )
        } catch {
            return fallback
        }
    }

    private static func payload(from result: Any?) -> [String: Any]? {
        if let payload = result as? [String: Any] {
            return payload
        }
        guard let string = result as? String,
              let data = string.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }
}
