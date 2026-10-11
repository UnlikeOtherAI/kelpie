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
    private val methods = router.registeredMethods - AndroidUnsupportedMethods.all
    private val extensions = nativeExtensions().filter { it["method"] in methods }
    private val direct = session(methods, extensions, true, null)

    fun register() {
        router.browserGateway = this
        ctx.browserGateway = this
        ctx.browserDocumentChanged = { tabId -> changedDocuments.add(tabId) }
        router.register("browser-control") { request ->
            direct.call(request) ?: errorResponse("GATEWAY_ERROR", "The browser returned no response")
        }
        router.register("mcp") { request ->
            if (BrowserGatewayReentrant.permits(request, extensions, REENTRANT_METHODS)) {
                reentrant(request)
            } else {
                direct.call(request, mcp = true) ?: emptyMap()
            }
        }
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
                authorize = { request, mutates -> authorize(request, mutates, allowActions, pinned) },
                beforeBegin = {
                    for (tabId in changedDocuments.toList()) {
                        changedDocuments.remove(tabId)
                        sessions.forEach { it.invalidateLocked(tabId) }
                    }
                },
                beforeMutation = { sessions.filter { it !== gateway }.forEach { it.invalidateLocked() } },
                retirement = ctx.browserRetirement,
                dispatch = { method, params -> execute(method, params, pinned) },
            )
        sessions.add(gateway)
        return gateway
    }

    private fun authorize(
        request: Map<String, Any?>,
        mutates: Boolean,
        allowActions: Boolean,
        pinned: String?,
    ): Boolean =
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

    /** Model inference owns its own lifecycle; only its nested renderer calls acquire the browser lease. */
    private suspend fun reentrant(request: Map<String, Any?>): Map<String, Any?> {
        val gateway =
            BrowserGatewaySession(
                mapOf(
                    "nativeMethods" to methods.intersect(REENTRANT_METHODS).toList(),
                    "extensions" to extensions.filter { it["method"] in REENTRANT_METHODS },
                    "allowActions" to true,
                    "requireAuthorization" to true,
                    "fixedReader" to false,
                ),
                Mutex(),
                authorize = { value, mutates -> authorize(value, mutates, true, null) },
                dispatch = { method, params -> router.handle(method, params, fromGateway = true).second },
                dispatchTimeoutMs = null,
            )
        return try {
            gateway.call(request, mcp = true) ?: emptyMap()
        } finally {
            withContext(kotlinx.coroutines.NonCancellable) { gateway.close() }
        }
    }

    suspend fun <T> legacy(
        method: String,
        action: suspend () -> T,
    ): T =
        withBrowserGatewayLease(lock, ctx.browserRetirement) {
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
            val store = ctx.tabStore
            val boundary = BrowserGatewayDispatch({ store?.activeTabId?.value ?: "0" }, { if (store == null) ctx.webView else store.activeTab?.webView })
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

    /** Captures an owned renderer without changing the visible tab; only the fixed common reader is admitted. */
    suspend fun contextSnapshot(tabId: String?): Map<String, Any?> =
        withContext(Dispatchers.Main.immediate) {
            val store = ctx.tabStore
            val target = tabId ?: store?.activeTabId?.value ?: "0"
            val view =
                if (store == null && target == "0") {
                    ctx.webView
                } else {
                    store
                        ?.tabs
                        ?.value
                        ?.firstOrNull { it.id == target }
                        ?.webView
                }
            if (view == null) return@withContext errorResponse("TAB_NOT_FOUND", "The context tab is unavailable")

            fun owned(): Boolean = if (store == null) ctx.webView === view else store.tabs.value.any { it.id == target && it.webView === view }
            val gateway =
                BrowserGatewaySession(
                    mapOf(
                        "nativeMethods" to listOf("get-current-url"),
                        "extensions" to emptyList<Any>(),
                        "targeting" to "direct",
                        "fixedReader" to true,
                        "allowActions" to false,
                        "requireAuthorization" to true,
                    ),
                    lock,
                    authorize = { request, mutates -> !mutates && request["method"] == "tab.snapshot" && request["tabId"] == target && owned() },
                    retirement = ctx.browserRetirement,
                    dispatch = { method, params ->
                        if (method != "browser-control-evaluate" || !owned()) {
                            errorResponse("TAB_NOT_FOUND", "The context tab changed")
                        } else {
                            ctx.withBrowserTarget(view) {
                                val result = invoke(method, params)
                                if (owned()) result else errorResponse("TAB_NOT_FOUND", "The context tab changed")
                            }
                        }
                    },
                )
            try {
                gateway
                    .call(
                        mapOf(
                            "version" to 1,
                            "method" to "tab.snapshot",
                            "tabId" to target,
                            "params" to mapOf("maxChars" to 12000, "maxElements" to 200),
                        ),
                    ).orEmpty()
            } finally {
                withContext(kotlinx.coroutines.NonCancellable) { gateway.close() }
            }
        }

    suspend fun closeSession(session: BrowserGatewaySession) {
        session.close()
        lock.withLock { sessions.remove(session) }
    }

    suspend fun close() {
        ctx.browserDocumentChanged = null
        if (ctx.browserGateway === this) ctx.browserGateway = null
        lock.withLock { sessions.toList() }.forEach { closeSession(it) }
    }

    private fun nativeExtensions(): List<Map<String, Any?>> = (OpenAIJson.parseOrNull(BrowserGatewayNative.extensions()) as? JsonArray).orEmpty().map { OpenAIJson.toMap(it as JsonObject) }

    companion object {
        private val REENTRANT_METHODS = setOf("ai-infer", "ai-record", "ai-cancel", "abort-script", "get-script-status")
        private val READ_METHODS = AgentBrowserPolicy.methods(false) + setOf("get-tabs", "get-current-url", "get-capabilities", "get-device-info")
    }
}
