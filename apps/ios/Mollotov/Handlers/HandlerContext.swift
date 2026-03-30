import WebKit

/// Shared context providing access to the WebView for all handlers.
@MainActor
final class HandlerContext: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var consoleMessages: [[String: Any]] = []
    let safariAuth = SafariAuthHelper()

    nonisolated override init() { super.init() }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }

        switch message.name {
        case "mollotovConsole":
            consoleMessages.append(body)
            if consoleMessages.count > 5000 { consoleMessages.removeFirst() }

        case "mollotovNetwork":
            let entry = NetworkTrafficStore.TrafficEntry(
                id: UUID(),
                method: (body["method"] as? String ?? "GET").uppercased(),
                url: body["url"] as? String ?? "",
                statusCode: body["statusCode"] as? Int ?? 0,
                contentType: body["contentType"] as? String ?? "",
                requestHeaders: body["requestHeaders"] as? [String: String] ?? [:],
                responseHeaders: body["responseHeaders"] as? [String: String] ?? [:],
                requestBody: body["requestBody"] as? String,
                responseBody: body["responseBody"] as? String,
                startTime: Date(),
                duration: body["duration"] as? Int ?? 0,
                size: body["size"] as? Int ?? 0
            )
            NetworkTrafficStore.shared.append(entry)

        default:
            break
        }
    }

    func evaluateJS(_ script: String) async throws -> Any? {
        guard let webView else { throw HandlerError.noWebView }
        return try await webView.evaluateJavaScript(script)
    }

    func evaluateJSReturningString(_ script: String) async throws -> String {
        let result = try await evaluateJS(script)
        return result as? String ?? String(describing: result ?? "null")
    }

    /// Show a blue touch indicator at viewport coordinates with a ripple animation.
    func showTouchIndicator(x: Double, y: Double) async {
        let js = """
        (function() {
            var dot = document.createElement('div');
            dot.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'background:rgba(59,130,246,0.7);pointer-events:none;z-index:2147483647;' +
                'transition:transform 0.5s ease-out, opacity 0.5s ease-out;transform:scale(1);opacity:1;';
            document.body.appendChild(dot);
            var ripple = document.createElement('div');
            ripple.style.cssText = 'position:fixed;left:\(x)px;top:\(y)px;width:36px;height:36px;' +
                'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                'border:2px solid rgba(59,130,246,0.7);pointer-events:none;z-index:2147483647;' +
                'transition:transform 0.6s ease-out, opacity 0.6s ease-out;transform:scale(1);opacity:1;';
            document.body.appendChild(ripple);
            requestAnimationFrame(function() {
                ripple.style.transform = 'scale(3)';
                ripple.style.opacity = '0';
            });
            setTimeout(function() {
                dot.style.transform = 'scale(0.5)';
                dot.style.opacity = '0';
            }, 550);
            setTimeout(function() {
                dot.remove();
                ripple.remove();
            }, 1100);
        })();
        """
        try? await evaluateJS(js)
    }

    /// Show touch indicator at an element's center by selector.
    func showTouchIndicatorForElement(_ selector: String) async {
        let js = """
        (function() {
            var el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (!el) return JSON.stringify(null);
            var r = el.getBoundingClientRect();
            return JSON.stringify({x: r.left + r.width/2, y: r.top + r.height/2});
        })()
        """
        if let result = try? await evaluateJSReturningString(js),
           let data = result.data(using: .utf8),
           let pos = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
           let x = pos["x"], let y = pos["y"] {
            await showTouchIndicator(x: x, y: y)
        }
    }

    /// Show a toast message overlay at the bottom of the viewport.
    func showToast(_ message: String) async {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let js = """
        (function() {
            var existing = document.getElementById('__mollotov_toast');
            if (existing) existing.remove();
            var toast = document.createElement('div');
            toast.id = '__mollotov_toast';
            toast.textContent = '\(escaped)';
            toast.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);' +
                'max-width:390px;width:calc(100% - 32px);padding:14px 22px;border-radius:16px;' +
                'background:rgba(0,0,0,0.5);color:#fff;font:15px/1.4 -apple-system,system-ui,sans-serif;' +
                'text-align:center;pointer-events:none;z-index:2147483647;' +
                'backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);' +
                'transition:opacity 0.3s ease-out;opacity:0;';
            document.body.appendChild(toast);
            requestAnimationFrame(function() { toast.style.opacity = '1'; });
            setTimeout(function() {
                toast.style.opacity = '0';
                setTimeout(function() { toast.remove(); }, 300);
            }, 3000);
        })();
        """
        try? await evaluateJS(js)
    }

    func evaluateJSReturningJSON(_ script: String) async throws -> [String: Any] {
        let wrapped = "JSON.stringify((\(script)))"
        let jsonString = try await evaluateJSReturningString(wrapped)
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
}

enum HandlerError: Error {
    case noWebView
    case elementNotFound(String)
    case timeout
    case platformNotSupported(String)
}

func errorResponse(code: String, message: String) -> [String: Any] {
    ["success": false, "error": ["code": code, "message": message]]
}

func successResponse(_ data: [String: Any] = [:]) -> [String: Any] {
    var result: [String: Any] = ["success": true]
    for (key, value) in data { result[key] = value }
    return result
}
