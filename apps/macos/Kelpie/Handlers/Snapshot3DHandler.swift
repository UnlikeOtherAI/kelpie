import Foundation

struct Snapshot3DHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("snapshot-3d-enter") { _ in await enter() }
        router.register("snapshot-3d-exit") { _ in await exit() }
        router.register("snapshot-3d-status") { _ in await status() }
    }

    @MainActor
    private func enter() async -> [String: Any] {
        guard FeatureFlags.is3DInspectorEnabled else {
            return errorResponse(
                code: "FEATURE_DISABLED",
                message: "3D inspector is not enabled. Enable in Settings or set KELPIE_3D_INSPECTOR=1"
            )
        }
        guard !context.isIn3DInspector else {
            return errorResponse(code: "ALREADY_ACTIVE", message: "3D inspector is already active")
        }

        do {
            try await context.evaluateJS(Snapshot3DBridge.enterScript)
            let active = try await context.evaluateJSReturningString("window.__m3d ? 'true' : 'false'")
            if active == "true" {
                context.isIn3DInspector = true
                return successResponse()
            }
            return errorResponse(code: "ACTIVATION_FAILED", message: "3D inspector script did not activate")
        } catch {
            return errorResponse(code: "JS_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func exit() async -> [String: Any] {
        guard context.isIn3DInspector else {
            return successResponse()
        }

        do {
            try await context.evaluateJS(Snapshot3DBridge.exitScript)
            context.mark3DInspectorInactive(notify: true)
            return successResponse()
        } catch {
            return errorResponse(code: "JS_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func status() async -> [String: Any] {
        successResponse(["active": context.isIn3DInspector])
    }
}
