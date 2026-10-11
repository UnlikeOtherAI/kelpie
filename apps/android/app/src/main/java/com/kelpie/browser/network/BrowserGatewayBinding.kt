package com.kelpie.browser.network

import com.kelpie.browser.ai.openai.AgentBrowserPolicy
import com.kelpie.browser.ai.openai.OpenAIJson
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.nativecore.BrowserGatewayNative
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.util.concurrent.ConcurrentHashMap

/** Android adapters invoke existing handlers. Fixed scripts are internal and run in WebView's page realm. */
class BrowserGatewayBinding(
    private val router: Router,
    private val ctx: HandlerContext,
) {
    private val lock = Mutex()
    private val sessions = mutableSetOf<BrowserGatewaySession>()
    private val changedDocuments = ConcurrentHashMap.newKeySet<String>()
    private val methods = router.registeredMethods - AndroidUnsupportedMethods.all - REENTRANT_METHODS
    private val extensions = nativeExtensions().filter { it["method"] in methods }
    private val direct = session(methods, extensions, true, null)

    fun register() {
        router.browserGateway = this
        ctx.browserDocumentChanged = { tabId -> changedDocuments.add(tabId) }
        router.register("browser-control") { request ->
            direct.call(request) ?: errorResponse("GATEWAY_ERROR", "The browser returned no response")
        }
        router.register("mcp") { request -> direct.call(request, mcp = true) ?: emptyMap() }
    }

    suspend fun agentSession(
        allowActions: Boolean,
        tabId: String,
    ): BrowserGatewaySession {
        val admitted = AgentBrowserPolicy.methods(allowActions)
        val descriptors = extensions.filter { descriptor -> descriptor["method"] in admitted }
        val native = admitted + "get-tabs" + if (allowActions) setOf("type") else emptySet()
        return lock.withLock { session(native.intersect(methods), descriptors, allowActions, tabId) }
    }

    private fun session(
        native: Set<String>,
        descriptors: List<Map<String, Any?>>,
        allowActions: Boolean,
        pinned: String?,
    ): BrowserGatewaySession {
        lateinit var gateway: BrowserGatewaySession
        gateway =
            BrowserGatewaySession(
                mapOf(
                    "nativeMethods" to native.toList(),
                    "extensions" to descriptors,
                    "targeting" to "selected",
                    "fixedReader" to true,
                    "allowActions" to allowActions,
                    "requireAuthorization" to true,
                ),
                lock,
                authorize = { request, mutates ->
                    ctx.scriptPlaybackState?.recordingError(request["method"] as? String ?: "browser-control") == null &&
                        BrowserGatewayTabPolicy.permits(
                            request,
                            mutates,
                            allowActions,
                            pinned,
                            ctx.tabStore?.activeTabId?.value ?: "0",
                            ctx.tabStore
                                ?.tabs
                                ?.value
                                ?.map { it.id }
                                ?.toSet() ?: setOf("0"),
                        )
                },
                beforeBegin = {
                    for (tabId in changedDocuments.toList()) {
                        changedDocuments.remove(tabId)
                        sessions.forEach { it.invalidateLocked(tabId) }
                    }
                },
                beforeMutation = { sessions.filter { it !== gateway }.forEach { it.invalidateLocked() } },
                dispatch = { method, params -> execute(method, params, pinned) },
            )
        sessions.add(gateway)
        return gateway
    }

    suspend fun <T> legacy(
        method: String,
        action: suspend () -> T,
    ): T =
        lock.withLock {
            // Methods outside the admitted read catalogue can mutate; invalidate conservatively before dispatch.
            if (method !in READ_METHODS) sessions.forEach { it.invalidateLocked() }
            action()
        }

    private suspend fun execute(
        method: String,
        params: Map<String, Any?>,
        pinned: String?,
    ): Map<String, Any?> =
        withContext(Dispatchers.Main.immediate) {
            val boundary = BrowserGatewayDispatch({ ctx.tabStore?.activeTabId?.value ?: "0" }, { ctx.webView })
            boundary.execute(method, params, pinned) { view ->
                val result = if (view == null) invoke(method, params) else ctx.withBrowserTarget(view) { invoke(method, params) }
                if (pinned != null && method == "get-tabs") {
                    result + (
                        "tabs" to
                            (result["tabs"] as? List<*>)?.filter { (it as? Map<*, *>)?.get("id") == pinned }.orEmpty()
                    )
                } else {
                    result
                }
            }
        }

    private suspend fun invoke(
        method: String,
        params: Map<String, Any?>,
    ): Map<String, Any?> {
        if (method != "browser-control-evaluate") return router.handle(method, params, fromGateway = true).second
        val expression = params["expression"] as? String ?: error("Missing fixed reader")
        if (ctx.webView == null) return errorResponse("NO_WEBVIEW", "No WebView")
        val value = ctx.evaluateJSReturningJSON(expression)
        return if (value.isEmpty()) {
            errorResponse("RENDERER_ERROR", "The fixed reader returned no JSON object")
        } else {
            successResponse(mapOf("result" to value))
        }
    }

    suspend fun readContext(
        tabId: String,
        method: String,
    ): Map<String, Any?> =
        lock.withLock {
            execute(method, mapOf("tabId" to tabId), tabId)
        }

    suspend fun closeSession(session: BrowserGatewaySession) {
        session.close()
        lock.withLock { sessions.remove(session) }
    }

    suspend fun close() {
        ctx.browserDocumentChanged = null
        lock.withLock { sessions.toList() }.forEach { closeSession(it) }
    }

    private fun nativeExtensions(): List<Map<String, Any?>> = (OpenAIJson.parseOrNull(BrowserGatewayNative.extensions()) as? JsonArray).orEmpty().map { OpenAIJson.toMap(it as JsonObject) }

    companion object {
        private val REENTRANT_METHODS = setOf("ai-infer", "ai-record")
        private val READ_METHODS = AgentBrowserPolicy.methods(false) + setOf("get-tabs", "get-current-url", "get-capabilities", "get-device-info")
    }
}
