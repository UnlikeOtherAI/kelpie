package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.successResponse

class ConsoleHandler(
    private val context: HandlerContext,
) {
    fun register(router: Router) {
        router.register("get-console-messages") { body -> getConsoleMessages(body) }
        router.register("get-js-errors") { getJSErrors() }
        router.register("clear-console") { clearConsole() }
    }

    private fun getConsoleMessages(body: Map<String, Any?>): Map<String, Any?> {
        val level = body["level"] as? String
        val limit = body["limit"] as? Int ?: 100

        var messages = context.snapshotConsoleMessages()
        if (level != null) {
            messages = messages.filter { it["level"] == level }
        }
        val limited = messages.takeLast(limit)
        return successResponse(
            mapOf(
                "messages" to limited,
                "count" to limited.size,
                "hasMore" to (messages.size > limit),
            ),
        )
    }

    private fun getJSErrors(): Map<String, Any?> {
        val errors =
            context.snapshotConsoleMessages().filter { it["level"] == "error" }
        return successResponse(
            mapOf(
                "errors" to errors.map { it + ("type" to "console-error") },
                "count" to errors.size,
            ),
        )
    }

    private fun clearConsole(): Map<String, Any?> = successResponse(mapOf("cleared" to context.clearConsoleMessages()))

    companion object {
        const val BRIDGE_SCRIPT =
            """
            (function() {
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
                            var lines = stack.split('\n');
                            if (lines.length > 2) {
                                var match = lines[2].match(/(https?:\/\/[^:]+):?(\d+)?:?(\d+)?/);
                                if (match) {
                                    msg.source = match[1] || '';
                                    msg.line = parseInt(match[2]) || 0;
                                    msg.column = parseInt(match[3]) || 0;
                                }
                                msg.stackTrace = lines.slice(2).join('\n');
                            }
                        } catch(e) {}
                        if (window.KelpieBridge) window.KelpieBridge.onConsoleMessage(JSON.stringify(msg));
                        _origConsole[level].apply(console, arguments);
                    };
                });
                window.addEventListener('error', function(e) {
                    if (window.KelpieBridge) window.KelpieBridge.onConsoleMessage(JSON.stringify({
                        level: 'error',
                        text: e.message || String(e),
                        source: e.filename || '',
                        line: e.lineno || 0,
                        column: e.colno || 0,
                        timestamp: new Date().toISOString(),
                        stackTrace: e.error ? e.error.stack : null
                    }));
                });
                window.addEventListener('unhandledrejection', function(e) {
                    if (window.KelpieBridge) window.KelpieBridge.onConsoleMessage(JSON.stringify({
                        level: 'error',
                        text: 'Unhandled Promise rejection: ' + (e.reason ? (e.reason.message || String(e.reason)) : 'unknown'),
                        source: '',
                        line: 0,
                        column: 0,
                        timestamp: new Date().toISOString(),
                        stackTrace: e.reason ? e.reason.stack : null
                    }));
                });
            })();
            """
    }
}
