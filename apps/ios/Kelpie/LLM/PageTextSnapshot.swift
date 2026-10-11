import WebKit

/// One ephemeral read, captured against a specific WebView before any suspension.
enum PageTextSnapshot {
    static func script(selector: String) -> String {
        """
        (function() {
            const root = document.querySelector('\(JSEscape.string(selector))');
            const text = (root && (root.innerText || root.textContent) || '').trim();
            const labels = [];
            if (root) for (const element of root.querySelectorAll('img[alt], [aria-label], [aria-labelledby], svg')) {
                const style = getComputedStyle(element);
                if (element.closest('[aria-hidden="true"]') || style.display === 'none' || style.visibility === 'hidden') continue;
                const labelled = (element.getAttribute('aria-labelledby') || '').split(/\\s+/)
                    .map(id => document.getElementById(id)?.textContent || '').join(' ').trim();
                const title = element.tagName.toLowerCase() === 'svg' ? element.querySelector('title')?.textContent : '';
                const label = (element.getAttribute('aria-label') || labelled || element.getAttribute('alt') || title || '').trim();
                if (label && !labels.includes(label)) labels.push(label);
            }
            return {title: document.title, url: location.href, content: text, accessibleLabels: labels,
                wordCount: text ? text.split(/\\s+/).length : 0, language: document.documentElement.lang || null,
                excerpt: text.substring(0, 200)};
        })()
        """
    }

    @MainActor
    static func read(context: HandlerContext, body: [String: Any]) async throws -> [String: Any] {
        let webView: WKWebView?
        if let requested = body["tabId"] as? String {
            guard let id = UUID(uuidString: requested),
                  let tab = context.tabStore?.tabs.first(where: { $0.id == id }) else {
                throw AIHandlerError(code: "TAB_NOT_FOUND", message: "Tab \(requested) not found")
            }
            webView = tab.webView
        } else {
            webView = context.webView
        }
        guard let webView else { throw AIHandlerError(code: "NO_WEBVIEW", message: "No browser tab is available") }
        let script = script(selector: body["selector"] as? String ?? "body")
        guard let raw = try await webView.evaluateJavaScript("JSON.stringify((\(script)))") as? String,
              let data = raw.data(using: .utf8),
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["title"] is String, result["url"] is String,
              result["content"] is String, result["accessibleLabels"] is [String] else {
            throw AIHandlerError(code: "EVAL_ERROR", message: "Page text returned an invalid snapshot")
        }
        return result
    }
}
