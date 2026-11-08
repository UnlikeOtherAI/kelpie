package com.kelpie.browser.handlers

import android.webkit.WebView
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse

class WebSocketHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("get-websockets") { getWebSockets() }
        router.register("get-websocket-messages") { getWebSocketMessages(it) }
    }

    private suspend fun getWebSockets(): Map<String, Any?> =
        try {
            val connections = ctx.evaluateJSReturningArray(webSocketsScript())
            successResponse(mapOf("connections" to connections, "count" to connections.size))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }

    private suspend fun getWebSocketMessages(body: Map<String, Any?>): Map<String, Any?> {
        val connectionIndex = body["connectionIndex"] as? Int
        val limit = ((body["limit"] as? Int) ?: 100).coerceIn(1, 500)

        return try {
            val messages = ctx.evaluateJSReturningArray(webSocketMessagesScript(connectionIndex, limit))
            successResponse(mapOf("messages" to messages, "count" to messages.size))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private fun webSocketsScript(): String =
        """
        (function() {
            var sockets = Array.isArray(window.__kelpieWebSockets) ? window.__kelpieWebSockets : [];
            return sockets
                .filter(function(socket) {
                    return socket && socket.readyState !== WebSocket.CLOSED;
                })
                .map(function(socket) {
                    return {
                        url: socket.url || '',
                        readyState: socket.readyState || 0,
                        protocol: socket.protocol || '',
                        messagesSent: socket.messagesSent || 0,
                        messagesReceived: socket.messagesReceived || 0,
                        createdAt: socket.createdAt || ''
                    };
                });
        })()
        """.trimIndent()

    private fun webSocketMessagesScript(
        connectionIndex: Int?,
        limit: Int,
    ): String {
        val indexValue = connectionIndex?.toString() ?: "null"
        return buildString {
            append("(function() {")
            append("var sockets = Array.isArray(window.__kelpieWebSockets) ? window.__kelpieWebSockets : [];")
            append("var active = sockets.filter(function(socket) {")
            append("return socket && socket.readyState !== WebSocket.CLOSED;")
            append("});")
            append("var selected = $indexValue === null ? active : active.filter(function(_, index) {")
            append("return index === $indexValue;")
            append("});")
            append("var messages = [];")
            append("selected.forEach(function(socket) {")
            append("var activeIndex = active.indexOf(socket);")
            append("(socket.lastMessages || []).forEach(function(message) {")
            append("messages.push({")
            append("connectionIndex: activeIndex,")
            append("direction: message.direction || 'received',")
            append("data: message.data || '',")
            append("timestamp: message.timestamp || socket.createdAt || ''")
            append("});")
            append("});")
            append("});")
            append("if (messages.length > $limit) {")
            append("messages = messages.slice(messages.length - $limit);")
            append("}")
            append("return messages;")
            append("})()")
        }
    }

    companion object {
        private const val DOCUMENT_START_ALLOWED_ORIGIN = "*"

        val isDocumentStartSupported: Boolean
            get() = WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)

        fun installBridge(webView: WebView) {
            if (!isDocumentStartSupported) return
            WebViewCompat.addDocumentStartJavaScript(webView, BRIDGE_SCRIPT, setOf(DOCUMENT_START_ALLOWED_ORIGIN))
        }

        val BRIDGE_SCRIPT =
            """
            (function() {
                if (window.__kelpieWebSocketBridgeInstalled) return;
                window.__kelpieWebSocketBridgeInstalled = true;

                var NativeWebSocket = window.WebSocket;
                if (!NativeWebSocket) return;

                var DEFAULT_MESSAGE_LIMIT = 50;
                var MAX_MESSAGE_LIMIT = 200;
                var MESSAGE_PREVIEW_LIMIT = 2000;
                var MAX_CONNECTIONS = 200;

                if (!Array.isArray(window.__kelpieWebSockets)) window.__kelpieWebSockets = [];
                if (typeof window.__kelpieWebSocketMessageLimit !== 'number' || window.__kelpieWebSocketMessageLimit < 1) {
                    window.__kelpieWebSocketMessageLimit = DEFAULT_MESSAGE_LIMIT;
                }
                if (typeof window.__kelpieNextWebSocketId !== 'number' || window.__kelpieNextWebSocketId < 1) {
                    window.__kelpieNextWebSocketId = 1;
                }

                function messageLimit() {
                    var raw = window.__kelpieWebSocketMessageLimit;
                    if (typeof raw !== 'number' || !isFinite(raw) || raw < 1) return DEFAULT_MESSAGE_LIMIT;
                    return Math.min(Math.floor(raw), MAX_MESSAGE_LIMIT);
                }

                function previewText(value) {
                    return value.length > MESSAGE_PREVIEW_LIMIT ? value.substring(0, MESSAGE_PREVIEW_LIMIT) : value;
                }

                function normalizeData(data) {
                    if (typeof data === 'string') return previewText(data);
                    if (data instanceof ArrayBuffer) return '[ArrayBuffer ' + data.byteLength + ' bytes]';
                    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(data)) {
                        return '[' + ((data && data.constructor && data.constructor.name) || 'TypedArray') + ' ' + data.byteLength + ' bytes]';
                    }
                    if (typeof Blob !== 'undefined' && data instanceof Blob) {
                        return '[Blob ' + (data.type || 'application/octet-stream') + ' ' + data.size + ' bytes]';
                    }
                    if (data == null) return '';
                    try {
                        return previewText(typeof data === 'object' ? JSON.stringify(data) : String(data));
                    } catch (error) {
                        return previewText(String(data));
                    }
                }

                function syncState(record, socket) {
                    try { record.readyState = socket.readyState; } catch (error) {}
                    try { record.protocol = socket.protocol || ''; } catch (error) {}
                }

                function appendMessage(record, direction, data) {
                    if (!Array.isArray(record.lastMessages)) record.lastMessages = [];
                    record.lastMessages.push({
                        direction: direction,
                        data: normalizeData(data),
                        timestamp: new Date().toISOString()
                    });
                    var limit = messageLimit();
                    if (record.lastMessages.length > limit) {
                        record.lastMessages.splice(0, record.lastMessages.length - limit);
                    }
                }

                function trimConnections() {
                    var sockets = window.__kelpieWebSockets;
                    if (sockets.length <= MAX_CONNECTIONS) return;

                    for (var index = sockets.length - 1; index >= 0 && sockets.length > MAX_CONNECTIONS; index--) {
                        if (sockets[index] && sockets[index].readyState === NativeWebSocket.CLOSED) {
                            sockets.splice(index, 1);
                        }
                    }

                    if (sockets.length > MAX_CONNECTIONS) {
                        sockets.splice(0, sockets.length - MAX_CONNECTIONS);
                    }
                }

                function createRecord(socket, url) {
                    var record = {
                        id: window.__kelpieNextWebSocketId++,
                        url: String(url || ''),
                        readyState: socket.readyState,
                        protocol: socket.protocol || '',
                        createdAt: new Date().toISOString(),
                        messagesSent: 0,
                        messagesReceived: 0,
                        lastMessages: []
                    };
                    window.__kelpieWebSockets.push(record);
                    trimConnections();
                    return record;
                }

                function WrappedWebSocket(url, protocols) {
                    var socket = arguments.length > 1 ? new NativeWebSocket(url, protocols) : new NativeWebSocket(url);
                    var record = createRecord(socket, url);
                    var originalSend = socket.send;

                    socket.send = function(data) {
                        record.messagesSent += 1;
                        syncState(record, socket);
                        appendMessage(record, 'sent', data);
                        return originalSend.apply(socket, arguments);
                    };

                    socket.addEventListener('open', function() {
                        syncState(record, socket);
                    });
                    socket.addEventListener('close', function() {
                        syncState(record, socket);
                    });
                    socket.addEventListener('error', function() {
                        syncState(record, socket);
                    });
                    socket.addEventListener('message', function(event) {
                        record.messagesReceived += 1;
                        syncState(record, socket);
                        appendMessage(record, 'received', event.data);
                    });

                    return socket;
                }

                WrappedWebSocket.prototype = NativeWebSocket.prototype;
                try { Object.setPrototypeOf(WrappedWebSocket, NativeWebSocket); } catch (error) {}
                ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function(key) {
                    WrappedWebSocket[key] = NativeWebSocket[key];
                });
                WrappedWebSocket.toString = function() {
                    return NativeWebSocket.toString();
                };

                try {
                    Object.defineProperty(window, 'WebSocket', {
                        value: WrappedWebSocket,
                        configurable: true,
                        writable: true
                    });
                } catch (error) {
                    window.WebSocket = WrappedWebSocket;
                }
            })();
            """.trimIndent()
    }
}
