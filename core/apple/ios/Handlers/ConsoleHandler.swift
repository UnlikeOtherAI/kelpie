import WebKit

/// Handles getConsoleMessages, getJSErrors, clearConsole.
/// Uses an injected bridge script to capture console output via WKScriptMessageHandler.
struct ConsoleHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-console-messages") { body in await getConsoleMessages(body) }
        router.register("get-js-errors") { body in await getJSErrors(body) }
        router.register("clear-console") { _ in await clearConsole() }
    }

    @MainActor
    private func getConsoleMessages(_ body: [String: Any]) async -> [String: Any] {
        let level = body["level"] as? String
        let limit = body["limit"] as? Int ?? 100

        var messages = context.consoleMessages
        if let level {
            messages = messages.filter { ($0["level"] as? String) == level }
        }
        let limited = Array(messages.suffix(limit))
        return successResponse([
            "messages": limited,
            "count": limited.count,
            "hasMore": messages.count > limit
        ])
    }

    @MainActor
    private func getJSErrors(_ body: [String: Any]) async -> [String: Any] {
        let errors = context.consoleMessages.filter { ($0["level"] as? String) == "error" }
        return successResponse([
            "errors": errors.map { msg -> [String: Any] in
                var error = msg
                error["type"] = "console-error"
                return error
            },
            "count": errors.count
        ])
    }

    @MainActor
    private func clearConsole() async -> [String: Any] {
        let count = context.consoleMessages.count
        context.consoleMessages.removeAll()
        return successResponse(["cleared": count])
    }

    /// Returns the user script to inject at document start for console capture.
    /// Saves a private reference to postMessage, then masks window.webkit.messageHandlers
    /// so Google OAuth and similar services don't detect WKWebView.
    static var bridgeScript: WKUserScript {
        let js = """
        (function() {
            // Save private reference before masking — Google OAuth detects messageHandlers
            var _post = window.webkit.messageHandlers.kelpieConsole.postMessage.bind(
                window.webkit.messageHandlers.kelpieConsole
            );
            // Mask webkit.messageHandlers from page scripts
            try {
                Object.defineProperty(window.webkit, 'messageHandlers', {
                    get: function() { return undefined; },
                    configurable: false
                });
            } catch(e) {
                try { delete window.webkit.messageHandlers; } catch(e2) {}
            }

            var _origConsole = {};
            ['log','warn','error','info','debug'].forEach(function(level) {
                _origConsole[level] = console[level];
                console[level] = function() {
                    var args = Array.from(arguments).map(function(a) {
                        try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
                        catch(e) { return String(a); }
                    });
                    var msg = {
                        level: level,
                        text: args.join(' '),
                        timestamp: new Date().toISOString(),
                        source: '',
                        line: 0,
                        column: 0,
                        stackTrace: null
                    };
                    try {
                        var stack = new Error().stack || '';
                        var lines = stack.split('\\n');
                        if (lines.length > 2) {
                            var match = lines[2].match(/(https?:\\/\\/[^:]+):?(\\d+)?:?(\\d+)?/);
                            if (match) {
                                msg.source = match[1] || '';
                                msg.line = parseInt(match[2]) || 0;
                                msg.column = parseInt(match[3]) || 0;
                            }
                            msg.stackTrace = lines.slice(2).join('\\n');
                        }
                    } catch(e) {}
                    _post(msg);
                    _origConsole[level].apply(console, arguments);
                };
            });
            window.addEventListener('error', function(e) {
                _post({
                    level: 'error',
                    text: e.message || String(e),
                    source: e.filename || '',
                    line: e.lineno || 0,
                    column: e.colno || 0,
                    timestamp: new Date().toISOString(),
                    stackTrace: e.error ? e.error.stack : null
                });
            });
            window.addEventListener('unhandledrejection', function(e) {
                _post({
                    level: 'error',
                    text: 'Unhandled Promise rejection: ' + (e.reason ? (e.reason.message || String(e.reason)) : 'unknown'),
                    source: '',
                    line: 0,
                    column: 0,
                    timestamp: new Date().toISOString(),
                    stackTrace: e.reason ? e.reason.stack : null
                });
            });
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
