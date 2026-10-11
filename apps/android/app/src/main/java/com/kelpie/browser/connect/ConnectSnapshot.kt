package com.kelpie.browser.connect

import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.nativecore.BrowserGatewayNative
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import org.json.JSONObject

/** Fixed shared reader, registered only in the job-owned router. */
class ConnectSnapshot(
    private val context: HandlerContext,
) {
    fun register(router: Router) {
        router.register("connect-snapshot") { body ->
            try {
                val maxChars = ((body["maxChars"] as? Number)?.toInt() ?: 16000).coerceIn(64, 16000)
                val options = JSONObject(mapOf("prefix" to "observed", "maxElements" to 150, "maxChars" to maxChars, "includeShadow" to false))
                val expression = JSONObject(BrowserGatewayNative.selectorSnapshotExpression(options.toString())).getString("expression")
                successResponse(context.evaluateJSReturningJSON(expression))
            } catch (_: Exception) {
                errorResponse("SNAPSHOT_UNAVAILABLE", "Pinned page snapshot unavailable")
            }
        }
    }
}
