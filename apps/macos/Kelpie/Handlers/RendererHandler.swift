import Foundation

/// Handles set-renderer and get-renderer endpoints.
/// Triggers cookie migration and engine swap.
struct RendererHandler {
    let context: HandlerContext
    let rendererState: RendererState
    let onSwitch: (RendererState.Engine) async -> Void

    func register(on router: Router) {
        router.register("set-renderer") { body in await setRenderer(body) }
        router.register("get-renderer") { _ in await getRenderer() }
    }

    @MainActor
    private func setRenderer(_ body: [String: Any]) async -> [String: Any] {
        guard let engineStr = body["engine"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "engine is required (webkit|chromium)")
        }
        guard let engine = RendererState.Engine(rawValue: engineStr) else {
            return errorResponse(code: "INVALID_PARAM", message: "engine must be webkit or chromium")
        }
        if engine == rendererState.activeEngine {
            return successResponse(["engine": engine.rawValue, "changed": false])
        }

        await onSwitch(engine)

        return successResponse(["engine": engine.rawValue, "changed": true])
    }

    @MainActor
    private func getRenderer() async -> [String: Any] {
        successResponse([
            "engine": rendererState.activeEngine.rawValue,
            "available": RendererState.Engine.allCases.map(\.rawValue),
        ])
    }
}
