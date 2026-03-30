package com.mollotov.browser.devtools

import com.mollotov.browser.handlers.HandlerContext
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse

class ConsoleHandler(private val ctx: HandlerContext) {
    private val consoleMessages = mutableListOf<Map<String, Any?>>()

    fun register(router: Router) {
        router.register("get-console-messages") { getConsoleMessages(it) }
        router.register("get-js-errors") { getJSErrors() }
        router.register("clear-console") { clearConsole() }
    }

    fun addMessage(message: Map<String, Any?>) {
        consoleMessages.add(message)
        if (consoleMessages.size > 5000) consoleMessages.removeFirst()
    }

    private fun getConsoleMessages(body: Map<String, Any?>): Map<String, Any?> {
        val level = body["level"] as? String
        val limit = (body["limit"] as? Int) ?: 100
        val filtered = if (level != null) consoleMessages.filter { it["level"] == level } else consoleMessages
        val limited = filtered.takeLast(limit)
        return successResponse(mapOf("messages" to limited, "count" to limited.size, "hasMore" to (filtered.size > limit)))
    }

    private fun getJSErrors(): Map<String, Any?> {
        val errors = consoleMessages.filter { it["level"] == "error" }
        return successResponse(mapOf(
            "errors" to errors.map { it + ("type" to "console-error") },
            "count" to errors.size,
        ))
    }

    private fun clearConsole(): Map<String, Any?> {
        val count = consoleMessages.size
        consoleMessages.clear()
        return successResponse(mapOf("cleared" to count))
    }

    companion object {
        /** JavaScript to inject for console capture. Posts messages via Android bridge. */
        const val BRIDGE_SCRIPT = """
(function() {
    var _origConsole = {};
    ['log','warn','error','info','debug'].forEach(function(level) {
        _origConsole[level] = console[level];
        console[level] = function() {
            var args = Array.from(arguments).map(function(a) {
                try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
                catch(e) { return String(a); }
            });
            var msg = JSON.stringify({
                level: level,
                text: args.join(' '),
                timestamp: new Date().toISOString(),
                source: '',
                line: 0,
                column: 0
            });
            if (window.MollotovBridge) window.MollotovBridge.onConsoleMessage(msg);
            _origConsole[level].apply(console, arguments);
        };
    });
    window.addEventListener('error', function(e) {
        var msg = JSON.stringify({
            level: 'error',
            text: e.message || String(e),
            source: e.filename || '',
            line: e.lineno || 0,
            column: e.colno || 0,
            timestamp: new Date().toISOString()
        });
        if (window.MollotovBridge) window.MollotovBridge.onConsoleMessage(msg);
    });
    window.addEventListener('unhandledrejection', function(e) {
        var msg = JSON.stringify({
            level: 'error',
            text: 'Unhandled Promise rejection: ' + (e.reason ? (e.reason.message || String(e.reason)) : 'unknown'),
            source: '',
            line: 0,
            column: 0,
            timestamp: new Date().toISOString()
        });
        if (window.MollotovBridge) window.MollotovBridge.onConsoleMessage(msg);
    });
})();
"""
    }
}
