package com.kelpie.browser.handlers

import com.kelpie.browser.FeatureFlags

class Snapshot3DHandler(
    private val context: HandlerContext,
    private val featureFlagEnabled: () -> Boolean,
) {
    fun register(router: com.kelpie.browser.network.Router) {
        router.register("snapshot-3d-enter") { enter() }
        router.register("snapshot-3d-exit") { exit() }
        router.register("snapshot-3d-status") { status() }
    }

    private suspend fun enter(): Map<String, Any?> {
        if (!featureFlagEnabled()) {
            return com.kelpie.browser.network.errorResponse(
                "FEATURE_DISABLED",
                "3D inspector is disabled in Settings",
            )
        }
        if (context.isIn3DInspector) {
            return com.kelpie.browser.network.errorResponse("ALREADY_ACTIVE", "3D inspector is already active")
        }

        return try {
            context.evaluateJS(Snapshot3DBridge.ENTER_SCRIPT)
            val active = context.evaluateJS("!!window.__m3d")
            if (active.contains("true")) {
                context.isIn3DInspector = true
                com.kelpie.browser.network.successResponse()
            } else {
                com.kelpie.browser.network.errorResponse("ACTIVATION_FAILED", "3D inspector script did not activate")
            }
        } catch (error: Exception) {
            com.kelpie.browser.network.errorResponse("JS_ERROR", error.localizedMessage ?: "JavaScript error")
        }
    }

    private suspend fun exit(): Map<String, Any?> {
        if (!context.isIn3DInspector) {
            return com.kelpie.browser.network.successResponse()
        }

        return try {
            context.evaluateJS(Snapshot3DBridge.EXIT_SCRIPT)
            context.mark3DInspectorInactive()
            com.kelpie.browser.network.successResponse()
        } catch (error: Exception) {
            com.kelpie.browser.network.errorResponse("JS_ERROR", error.localizedMessage ?: "JavaScript error")
        }
    }

    private fun status(): Map<String, Any?> =
        com.kelpie.browser.network.successResponse(mapOf("active" to context.isIn3DInspector))
}
