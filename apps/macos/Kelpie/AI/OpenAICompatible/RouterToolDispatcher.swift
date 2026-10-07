import Foundation

/// Runs agent tool calls through Kelpie's own HTTP router so they get the same
/// tab resolution, validation and script-recording gate as API callers.
struct RouterToolDispatcher: OpenAIToolDispatching {
    let router: Router

    func dispatch(method: String, body: [String: Any]) async -> [String: Any] {
        await router.handle(method: method, body: body).json
    }
}
