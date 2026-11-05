import WebKit

#if DEBUG
/// One-shot experiment. The renderer lease remains held until this callback retires.
@MainActor
final class IOSPostEvaluationProbe: NSObject, WKScriptMessageHandlerWithReply {
    private weak var view: WKWebView?
    private let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let authorize: @MainActor () async throws -> Void
    private let deadline = ProcessInfo.processInfo.systemUptime + 4
    private var hostReturned = false
    private var requested = false
    private var authorized = false
    private var continuation: CheckedContinuation<Any?, Error>?

    init(view: WKWebView, authorize: @escaping @MainActor () async throws -> Void) {
        self.view = view
        self.authorize = authorize
    }

    func evaluate(_ expression: String) async throws -> Any? {
        guard let view else { throw IOSWorkflowFailure("TAB_CHANGED") }
        let controller = view.configuration.userContentController
        let terminationToken = observeTermination(view)
        defer { IOSRendererDeadline.removeTerminationObserver(view, token: terminationToken) }
        let name = "kelpieProbe" + nonce
        controller.addScriptMessageHandler(self, contentWorld: BrowserControlWebKit.world, name: name)
        defer { controller.removeScriptMessageHandler(forName: name, contentWorld: BrowserControlWebKit.world) }
        let script = """
        (()=>{const n="\(nonce)",h=webkit.messageHandlers.\(name),end=performance.now()+3500;
        setTimeout(async()=>{try{
          const permitted=await h.postMessage({nonce:n,phase:"request"});
          if(permitted!==true)return;
          if(performance.now()>end){await h.postMessage({nonce:n,phase:"expired"});return}
          const value=\(expression);
          await h.postMessage({nonce:n,phase:"result",value});
        }catch(e){await h.postMessage({nonce:n,phase:"error"})}},100);
        return true})()
        """
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor [self] in
                try? await Task.sleep(nanoseconds: 4_500_000_000)
                expireIfUnapproved()
            }
            Task { @MainActor [self] in
                do {
                    _ = try await BrowserControlWebKit.evaluate(script, in: view)
                    hostReturned = true
                } catch { finish(.failure(error)) }
            }
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard message.webView === view, message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any], body["nonce"] as? String == nonce,
              let phase = body["phase"] as? String else { replyHandler(nil, "Invalid probe"); return }
        switch phase {
        case "request":
            Task { @MainActor [self] in
                do {
                    guard hostReturned, continuation != nil, !requested,
                          ProcessInfo.processInfo.systemUptime < deadline else {
                        throw IOSWorkflowFailure("TIMEOUT")
                    }
                    requested = true
                    try await authorize()
                    guard continuation != nil, ProcessInfo.processInfo.systemUptime < deadline else {
                        throw IOSWorkflowFailure("TIMEOUT")
                    }
                    authorized = true
                    IOSFrameSampler.diagnostic("postedit-authorized")
                    replyHandler(true, nil)
                } catch {
                    replyHandler(false, nil)
                    finish(.failure(error))
                }
            }
        case "result":
            replyHandler(true, nil)
            guard authorized else { finish(.failure(IOSWorkflowFailure("WEBVIEW_ERROR", mayHaveCompleted: true))); return }
            IOSFrameSampler.diagnostic("postedit-result")
            finish(.success(body["value"]))
        case "expired":
            replyHandler(true, nil)
            finish(.failure(IOSWorkflowFailure("TIMEOUT", mayHaveCompleted: true)))
        case "error":
            replyHandler(true, nil)
            finish(.failure(IOSWorkflowFailure("WEBVIEW_ERROR", mayHaveCompleted: true)))
        default:
            replyHandler(nil, "Invalid probe phase")
        }
    }

    private func observeTermination(_ view: WKWebView) -> UUID {
        IOSRendererDeadline.observeTermination(view) { [weak self] in
            self?.finish(.failure(IOSWorkflowFailure("WEBVIEW_ERROR", mayHaveCompleted: true)))
        }
    }

    var testIsWaiting: Bool { continuation != nil }

    func testAwaitReceipt(authorized: Bool) async throws {
        guard let view else { throw IOSWorkflowFailure("TAB_CHANGED") }
        self.authorized = authorized
        let token = observeTermination(view)
        defer { IOSRendererDeadline.removeTerminationObserver(view, token: token) }
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            self.continuation = continuation
        }
    }

    func expireIfUnapproved() {
        if !authorized { finish(.failure(IOSWorkflowFailure("TIMEOUT"))) }
    }

    private func finish(_ result: Result<Any?, Error>) {
        let current = continuation
        continuation = nil
        current?.resume(with: result)
    }
}
#endif
