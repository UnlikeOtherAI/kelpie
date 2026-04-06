import Foundation

struct Snapshot3DHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("snapshot-3d-enter") { _ in await enter() }
        router.register("snapshot-3d-exit") { _ in await exit() }
        router.register("snapshot-3d-status") { _ in await status() }
        router.register("snapshot-3d-set-mode") { body in await setMode(body) }
        router.register("snapshot-3d-zoom") { body in await zoom(body) }
        router.register("snapshot-3d-reset-view") { _ in await resetView() }
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

    @MainActor
    private func setMode(_ body: [String: Any]) async -> [String: Any] {
        guard context.isIn3DInspector else {
            return errorResponse(code: "NOT_ACTIVE", message: "3D inspector is not active")
        }
        let requested = (body["mode"] as? String ?? "rotate").lowercased()
        guard requested == "rotate" || requested == "scroll" else {
            return errorResponse(code: "INVALID_MODE", message: "mode must be 'rotate' or 'scroll'")
        }
        do {
            let applied = try await context.evaluateJSReturningString(Snapshot3DBridge.setModeScript(requested))
            let normalized = applied == "rotate" || applied == "scroll" ? applied : requested
            return successResponse(["mode": normalized])
        } catch {
            return errorResponse(code: "JS_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func zoom(_ body: [String: Any]) async -> [String: Any] {
        guard context.isIn3DInspector else {
            return errorResponse(code: "NOT_ACTIVE", message: "3D inspector is not active")
        }
        let delta: Double
        if let value = body["delta"] as? Double {
            delta = value
        } else if let direction = body["direction"] as? String {
            switch direction.lowercased() {
            case "in": delta = 0.1
            case "out": delta = -0.1
            default:
                return errorResponse(code: "INVALID_DIRECTION", message: "direction must be 'in' or 'out'")
            }
        } else {
            return errorResponse(code: "MISSING_PARAM", message: "Provide 'delta' (number) or 'direction' ('in'|'out')")
        }
        do {
            try await context.evaluateJS(Snapshot3DBridge.zoomByScript(delta))
            return successResponse(["delta": delta])
        } catch {
            return errorResponse(code: "JS_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func resetView() async -> [String: Any] {
        guard context.isIn3DInspector else {
            return errorResponse(code: "NOT_ACTIVE", message: "3D inspector is not active")
        }
        do {
            try await context.evaluateJS(Snapshot3DBridge.resetViewScript)
            return successResponse()
        } catch {
            return errorResponse(code: "JS_ERROR", message: error.localizedDescription)
        }
    }
}
