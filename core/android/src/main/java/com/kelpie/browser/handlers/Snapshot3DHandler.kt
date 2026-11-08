package com.kelpie.browser.handlers

class Snapshot3DHandler(
    private val context: HandlerContext,
    private val featureFlagEnabled: () -> Boolean,
) {
    fun register(router: com.kelpie.browser.network.Router) {
        router.register("snapshot-3d-enter") { enter() }
        router.register("snapshot-3d-exit") { exit() }
        router.register("snapshot-3d-status") { status() }
        router.register("snapshot-3d-set-mode") { body -> setMode(body) }
        router.register("snapshot-3d-zoom") { body -> zoom(body) }
        router.register("snapshot-3d-reset-view") { resetView() }
    }

    private suspend fun enter(): Map<String, Any?> {
        if (!featureFlagEnabled()) {
            return com.kelpie.browser.network.errorResponse(
                "FEATURE_DISABLED",
                "3D inspector is disabled in Settings",
            )
        }
        if (context.isIn3DInspector) {
            return com.kelpie.browser.network
                .errorResponse("ALREADY_ACTIVE", "3D inspector is already active")
        }

        return try {
            context.evaluateJS(Snapshot3DBridge.ENTER_SCRIPT)
            val active = context.evaluateJS("!!window.__m3d")
            if (active.contains("true")) {
                context.isIn3DInspector = true
                com.kelpie.browser.network
                    .successResponse()
            } else {
                com.kelpie.browser.network
                    .errorResponse("ACTIVATION_FAILED", "3D inspector script did not activate")
            }
        } catch (error: Exception) {
            com.kelpie.browser.network
                .errorResponse("JS_ERROR", error.localizedMessage ?: "JavaScript error")
        }
    }

    private suspend fun exit(): Map<String, Any?> {
        if (!context.isIn3DInspector) {
            return com.kelpie.browser.network
                .successResponse()
        }

        return try {
            context.evaluateJS(Snapshot3DBridge.EXIT_SCRIPT)
            context.mark3DInspectorInactive()
            com.kelpie.browser.network
                .successResponse()
        } catch (error: Exception) {
            com.kelpie.browser.network
                .errorResponse("JS_ERROR", error.localizedMessage ?: "JavaScript error")
        }
    }

    private fun status(): Map<String, Any?> =
        com.kelpie.browser.network
            .successResponse(mapOf("active" to context.isIn3DInspector))

    private suspend fun setMode(body: Map<String, Any?>): Map<String, Any?> {
        if (!context.isIn3DInspector) {
            return com.kelpie.browser.network
                .errorResponse("NOT_ACTIVE", "3D inspector is not active")
        }
        val requested = (body["mode"] as? String ?: "rotate").lowercase()
        if (requested != "rotate" && requested != "scroll") {
            return com.kelpie.browser.network
                .errorResponse("INVALID_MODE", "mode must be 'rotate' or 'scroll'")
        }
        return try {
            val applied = context.evaluateJS(Snapshot3DBridge.setModeScript(requested))
            val normalized =
                when {
                    applied.contains("rotate") -> "rotate"
                    applied.contains("scroll") -> "scroll"
                    else -> requested
                }
            com.kelpie.browser.network
                .successResponse(mapOf("mode" to normalized))
        } catch (error: Exception) {
            com.kelpie.browser.network
                .errorResponse("JS_ERROR", error.localizedMessage ?: "JavaScript error")
        }
    }

    private suspend fun zoom(body: Map<String, Any?>): Map<String, Any?> {
        if (!context.isIn3DInspector) {
            return com.kelpie.browser.network
                .errorResponse("NOT_ACTIVE", "3D inspector is not active")
        }
        val delta: Double =
            when {
                body["delta"] is Number -> (body["delta"] as Number).toDouble()
                body["direction"] is String ->
                    when ((body["direction"] as String).lowercase()) {
                        "in" -> 0.1
                        "out" -> -0.1
                        else -> return com.kelpie.browser.network.errorResponse(
                            "INVALID_DIRECTION",
                            "direction must be 'in' or 'out'",
                        )
                    }
                else -> return com.kelpie.browser.network.errorResponse(
                    "MISSING_PARAM",
                    "Provide 'delta' (number) or 'direction' ('in'|'out')",
                )
            }
        return try {
            context.evaluateJS(Snapshot3DBridge.zoomByScript(delta))
            com.kelpie.browser.network
                .successResponse(mapOf("delta" to delta))
        } catch (error: Exception) {
            com.kelpie.browser.network
                .errorResponse("JS_ERROR", error.localizedMessage ?: "JavaScript error")
        }
    }

    private suspend fun resetView(): Map<String, Any?> {
        if (!context.isIn3DInspector) {
            return com.kelpie.browser.network
                .errorResponse("NOT_ACTIVE", "3D inspector is not active")
        }
        return try {
            context.evaluateJS(Snapshot3DBridge.RESET_VIEW_SCRIPT)
            com.kelpie.browser.network
                .successResponse()
        } catch (error: Exception) {
            com.kelpie.browser.network
                .errorResponse("JS_ERROR", error.localizedMessage ?: "JavaScript error")
        }
    }
}
