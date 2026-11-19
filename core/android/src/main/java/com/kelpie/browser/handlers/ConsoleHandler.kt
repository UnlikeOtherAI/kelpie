package com.kelpie.browser.handlers

import com.kelpie.browser.devtools.NetworkLogHandler
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.successResponse

class ConsoleHandler(
    private val context: HandlerContext,
) {
    fun register(router: Router) {
        router.register("get-console-messages") { body -> getConsoleMessages(body) }
        router.register("get-js-errors") { getJSErrors(it) }
        router.register("clear-console") { clearConsole(it) }
    }

    private fun getConsoleMessages(body: Map<String, Any?>): Map<String, Any?> {
        val level = body["level"] as? String
        val limit = (body["limit"] as? Int ?: 100).coerceAtLeast(0)
        val since = NetworkLogHandler.parseSinceMillis(body["since"])
        val tab = context.diagnosticTab(body) ?: return missingDiagnosticTab()

        var messages = tab.diagnostics.snapshotConsole()
        if (since != null) {
            messages =
                messages.filter {
                    val timestamp = it["timestamp"] as? String
                    timestamp?.let { NetworkLogHandler.parseIso8601Millis(it) }?.let { millis -> millis >= since } == true
                }
        }
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

    private fun getJSErrors(body: Map<String, Any?>): Map<String, Any?> {
        val tab = context.diagnosticTab(body) ?: return missingDiagnosticTab()
        val errors =
            tab.diagnostics.snapshotConsole().filter { it["level"] == "error" }
        return successResponse(
            mapOf(
                "errors" to errors.map { if ("type" in it) it else it + ("type" to "console-error") },
                "count" to errors.size,
            ),
        )
    }

    private fun clearConsole(body: Map<String, Any?>): Map<String, Any?> {
        val tab = context.diagnosticTab(body) ?: return missingDiagnosticTab()
        return successResponse(mapOf("cleared" to tab.diagnostics.clearConsole()))
    }

    companion object {
        const val BRIDGE_SCRIPT =
            """
            (function() {
                if (console.log.__kelpieInstrumented) return;
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
                console.log.__kelpieInstrumented = true;
                window.addEventListener('error', function(e) {
                    if (window.KelpieBridge) window.KelpieBridge.onConsoleMessage(JSON.stringify({
                        level: 'error',
                        type: 'uncaught-exception',
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
                        type: 'unhandled-rejection',
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
