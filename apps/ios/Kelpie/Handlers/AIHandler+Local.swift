import Foundation

extension AIHandler {
    func inferWithLocal(_ body: [String: Any]) async -> [String: Any] {
        await LocalInference.shared.execute("infer", body: body)
    }

    @MainActor
    func preparePageContext(_ input: [String: Any]) async throws -> [String: Any] {
        var body = input
        _ = try AIConversation.messages(body)
        guard let mode = body["context"] as? String else { return body }
        guard ["page_text", "dom", "accessibility"].contains(mode) else {
            throw AIHandlerError(code: "INVALID_PARAM", message: "context must be page_text, dom or accessibility")
        }
        guard let router else { throw AIHandlerError(code: "AI_UNAVAILABLE", message: "Browser router is unavailable") }
        body["text"] = try AIConversation.commonEvidence(await router.pageObservation(tabId: body["tabId"] as? String))
        return body
    }
}
