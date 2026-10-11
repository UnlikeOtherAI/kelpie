import Foundation

/// Owns one shared native coordinator, including opaque references and MCP state.
/// Only generated reader steps reach the private renderer callback.
@MainActor
final class BrowserControlGateway {
    typealias Dispatch = @MainActor (String, [String: Any], Bool) async -> [String: Any]
    typealias Authorize = @MainActor ([String: Any], Bool) -> Bool
    private let handle: KelpieBrowserGatewayRef?
    private let dispatch: Dispatch
    private let authorize: Authorize
    private let mutatingMethods: Set<String>
    private var navigationObserver: NSObjectProtocol?
    private let lease: BrowserControlLease?
    private let timeoutNanoseconds: UInt64

    init(
        methods: [String],
        extensions: [[String: Any]],
        targeting: String,
        allowActions: Bool,
        lease: BrowserControlLease? = nil,
        timeoutNanoseconds: UInt64 = 30_000_000_000,
        dispatch: @escaping Dispatch,
        authorize: @escaping Authorize
    ) {
        self.timeoutNanoseconds = timeoutNanoseconds
        self.lease = lease
        self.dispatch = dispatch
        self.authorize = authorize
        mutatingMethods = Set(extensions.filter { $0["mutates"] as? Bool ?? true }.compactMap { $0["method"] as? String })
        let config: [String: Any] = [
            "nativeMethods": methods, "extensions": extensions, "targeting": targeting,
            "fixedReader": true, "allowActions": allowActions, "requireAuthorization": true
        ]
        handle = Self.encode(config).withCString { kelpie_browser_gateway_create($0) }
        navigationObserver = NotificationCenter.default.addObserver(forName: .kelpieBrowserDocumentChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    deinit {
        if let navigationObserver { NotificationCenter.default.removeObserver(navigationObserver) }
        kelpie_browser_gateway_destroy(handle)
    }

    func invalidate(tabId: String? = nil) {
        if let tabId { tabId.withCString { kelpie_browser_gateway_invalidate_refs(handle, $0) } } else { kelpie_browser_gateway_invalidate_refs(handle, nil) }
    }

    func invalidates(method: String) -> Bool { mutatingMethods.contains(method) }

    func request(_ body: [String: Any], mcp: Bool = false) async -> [String: Any] {
        guard lease?.begin() != false else {
            let failure: [String: Any] = ["version": 1, "ok": false, "error": ["code": "BUSY", "message": "A browser operation is pending", "mayHaveCompleted": false]]
            return mcp ? ["jsonrpc": "2.0", "id": body["id"] ?? NSNull(), "error": ["code": -32000, "message": "A browser operation is pending"]] : failure
        }
        var ownsLease = true
        defer { if ownsLease { lease?.end() } }
        guard handle != nil else {
            let error: [String: Any] = ["code": "UNAVAILABLE", "message": "Browser coordinator is unavailable", "mayHaveCompleted": false]
            return mcp
                ? ["jsonrpc": "2.0", "id": body["id"] ?? NSNull(), "error": ["code": -32603, "message": "Browser coordinator is unavailable"]]
                : ["version": 1, "ok": false, "error": error]
        }
        var step = Self.decode(Self.encode(body).withCString {
            mcp ? kelpie_browser_gateway_begin_mcp(handle, $0) : kelpie_browser_gateway_begin(handle, $0)
        })
        while true {
            switch step["kind"] as? String {
            case "complete":
                // JSON-RPC notifications have no body; the HTTP layer emits an empty 202 response.
                let response = step["response"] as? [String: Any] ?? [:]
                return response
            case "authorize":
                let request = step["request"] as? [String: Any] ?? [:]
                let mutates = step["mutates"] as? Bool ?? true
                step = advance(["success": authorize(request, mutates)])
            case "dispatch":
                guard !Task.isCancelled else { return cancel() }
                let method = step["method"] as? String ?? ""
                let params = step["params"] as? [String: Any] ?? [:]
                let mutates = step["mutates"] as? Bool ?? true
                if method == "ai-infer" {
                    // Product inference owns its existing model/run deadlines. Its
                    // nested browser calls each acquire the shared admission lease.
                    // Holding it across inference would block its own tool loop.
                    lease?.end()
                    ownsLease = false
                    let result = await dispatch(method, params, mutates)
                    guard !Task.isCancelled else { return cancel() }
                    step = advance(result)
                    continue
                }
                guard let result = await boundedDispatch(method: method, params: params, mutates: mutates) else {
                    return cancel()
                }
                guard !Task.isCancelled else {
                    return cancel()
                }
                step = advance(result)
            default:
                return cancel()
            }
        }
    }

    func toolDefinitions() async -> [[String: Any]] {
        let list = await request(["jsonrpc": "2.0", "id": 1, "method": "tools/list"], mcp: true)
        let tools = (list["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        return tools.map { tool in
            ["type": "function", "function": [
                "name": tool["name"] ?? "", "description": tool["description"] ?? "",
                "parameters": tool["inputSchema"] ?? [:]
            ] as [String: Any]]
        }
    }

    func callTool(name: String, arguments: [String: Any]) async -> [String: Any] {
        let response = await request([
            "jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ], mcp: true)
        return response["result"] as? [String: Any] ?? response
    }

    private func advance(_ result: [String: Any]) -> [String: Any] {
        Self.decode(Self.encode(result).withCString { kelpie_browser_gateway_advance(handle, $0) })
    }

    private func cancel() -> [String: Any] {
        Self.decode(kelpie_browser_gateway_cancel(handle))["response"] as? [String: Any] ?? [:]
    }

    /// A late renderer completion cannot advance a cancelled coordinator or replay a command.
    private func boundedDispatch(method: String, params: [String: Any], mutates: Bool) async -> [String: Any]? {
        let completion = BrowserDispatchCompletion()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.attach(continuation)
                guard !Task.isCancelled else { completion.finish(nil); return }
                // The callback owns a pending lease independently of the HTTP/AI task.
                // A deadline can end the response, but cannot retire renderer work.
                lease?.retainPending()
                Task { @MainActor in
                    let result = await dispatch(method, params, mutates)
                    lease?.retirePending()
                    completion.finish(result)
                }
                completion.timer = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: timeoutNanoseconds) } catch { return }
                    completion.finish(nil)
                }
            }
        } onCancel: {
            Task { @MainActor in completion.finish(nil) }
        }
    }

    nonisolated static func canonicalResult(_ result: [String: Any]) -> [String: Any] {
        let content = result["content"] as? [[String: Any]] ?? []
        guard let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else { return [:] }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    static func encode(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func decode(_ value: UnsafeMutablePointer<CChar>?) -> [String: Any] {
        guard let value else { return [:] }
        defer { kelpie_mcp_free_string(value) }
        return (try? JSONSerialization.jsonObject(with: Data(String(cString: value).utf8))) as? [String: Any] ?? [:]
    }

    static func extensions(platform: Int32, methods: [String]) -> [[String: Any]] {
        let registry = kelpie_mcp_registry_create()
        defer { kelpie_mcp_registry_destroy(registry) }
        guard let value = kelpie_mcp_registry_tools_for_platform(registry, platform) else { return [] }
        defer { kelpie_mcp_free_string(value) }
        let tools = (try? JSONSerialization.jsonObject(with: Data(String(cString: value).utf8))) as? [[String: Any]] ?? []
        return tools.filter { methods.contains($0["method"] as? String ?? "") }
    }
}

@MainActor
private final class BrowserDispatchCompletion {
    private var continuation: CheckedContinuation<[String: Any]?, Never>?
    var timer: Task<Void, Never>?
    func attach(_ continuation: CheckedContinuation<[String: Any]?, Never>) { self.continuation = continuation }
    func finish(_ result: [String: Any]?) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        timer = nil
        continuation.resume(returning: result)
    }
}

final class BrowserControlLease: @unchecked Sendable {
    private let lock = NSLock()
    private var activeRequest = false
    private var pendingCallbacks = 0
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !activeRequest && pendingCallbacks == 0 else { return false }
        activeRequest = true
        return true
    }
    func retainPending() {
        lock.lock()
        pendingCallbacks += 1
        lock.unlock()
    }
    func retirePending() {
        lock.lock()
        pendingCallbacks -= 1
        lock.unlock()
    }
    func end() {
        lock.lock()
        activeRequest = false
        lock.unlock()
    }
}

@MainActor
final class WeakBrowserGateway {
    weak var gateway: BrowserControlGateway?
    init(_ gateway: BrowserControlGateway) { self.gateway = gateway }
}

extension Notification.Name {
    static let kelpieBrowserDocumentChanged = Notification.Name("kelpie.browserDocumentChanged")
}
