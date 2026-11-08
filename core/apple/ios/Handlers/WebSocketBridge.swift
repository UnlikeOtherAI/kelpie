import WebKit

/// JavaScript bridge that wraps WebSocket and stores recent connection state in page memory.
enum WebSocketBridge {
    static var bridgeScript: WKUserScript {
        WKUserScript(source: bridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    static let bridgeSource = """
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
    """
}
