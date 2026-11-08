import WebKit

struct WebSocketHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("get-websockets") { _ in await getWebSockets() }
        router.register("get-websocket-messages") { body in await getWebSocketMessages(body) }
    }

    @MainActor
    private func getWebSockets() async -> [String: Any] {
        do {
            let connections = try await context.evaluateJSReturningArray(webSocketsScript())
            return successResponse([
                "connections": connections,
                "count": connections.count
            ])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getWebSocketMessages(_ body: [String: Any]) async -> [String: Any] {
        let connectionIndex = body["connectionIndex"] as? Int
        let limit = min(max(body["limit"] as? Int ?? 100, 1), 500)

        do {
            let messages = try await context.evaluateJSReturningArray(webSocketMessagesScript(connectionIndex: connectionIndex, limit: limit))
            return successResponse([
                "messages": messages,
                "count": messages.count
            ])
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    private func webSocketsScript() -> String {
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
        """
    }

    private func webSocketMessagesScript(connectionIndex: Int?, limit: Int) -> String {
        let indexValue = connectionIndex.map(String.init) ?? "null"
        return """
        (function() {
            var sockets = Array.isArray(window.__kelpieWebSockets) ? window.__kelpieWebSockets : [];
            var active = sockets.filter(function(socket) {
                return socket && socket.readyState !== WebSocket.CLOSED;
            });
            var selected = \(indexValue) === null ? active : active.filter(function(_, index) {
                return index === \(indexValue);
            });
            var messages = [];

            selected.forEach(function(socket) {
                var activeIndex = active.indexOf(socket);
                (socket.lastMessages || []).forEach(function(message) {
                    messages.push({
                        connectionIndex: activeIndex,
                        direction: message.direction || 'received',
                        data: message.data || '',
                        timestamp: message.timestamp || socket.createdAt || ''
                    });
                });
            });

            if (messages.length > \(limit)) {
                messages = messages.slice(messages.length - \(limit));
            }
            return messages;
        })()
        """
    }
}
