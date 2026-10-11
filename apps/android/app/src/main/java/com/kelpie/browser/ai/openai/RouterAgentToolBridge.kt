package com.kelpie.browser.ai.openai

import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.network.Router

/**
 * Routes agent tool calls through Kelpie's existing router methods, so handler
 * validation and the script-recording gate apply exactly as for HTTP callers.
 *
 * Android handlers act on the active tab, so the run pins a tab id up front: a
 * caller-supplied `tabId` is switched to once (via `switch-tab`), and every tool call
 * verifies the pinned tab is still the active one before touching the page.
 */
class RouterAgentToolBridge(
    private val router: Router,
    private val ctx: HandlerContext,
) : AgentToolBridge {
    override suspend fun pinnedDispatcher(tabId: String?): ToolDispatcher {
        val tabStore = ctx.tabStore
        if (tabId != null && tabStore != null && tabStore.activeTabId.value != tabId) {
            val (_, result) = router.handle("switch-tab", mapOf("tabId" to tabId))
            if (result["success"] != true) {
                val error = result["error"] as? Map<*, *>
                throw OpenAIException(error?.get("code") as? String ?: "TAB_NOT_FOUND", error?.get("message") as? String ?: "No tab with id $tabId")
            }
        }
        val pinned = tabId ?: tabStore?.activeTabId?.value
        return PinnedTabDispatcher(router, pinned) { ctx.tabStore?.activeTabId?.value }
    }

    /** Page context handlers target captured WebViews directly and can read background tabs. */
    fun pageDispatcher(tabId: String?): ToolDispatcher {
        val captured = tabId ?: ctx.tabStore?.activeTabId?.value
        return ToolDispatcher { method, args ->
            router.handle(method, if (captured == null) args else args + ("tabId" to captured)).second
        }
    }

    override suspend fun pageContext(mode: String): String? =
        com.kelpie.browser.ai.AIPageContext.evidence(mode, pinnedDispatcher(null))

}

/** Dispatches through the router with the pinned tab injected; refuses if the user switched tabs. */
class PinnedTabDispatcher(
    private val router: Router,
    private val pinnedTabId: String?,
    private val activeTabId: () -> String?,
) : ToolDispatcher {
    override suspend fun dispatch(
        method: String,
        args: Map<String, Any?>,
    ): Map<String, Any?> {
        if (pinnedTabId != null && activeTabId() != pinnedTabId) {
            return mapOf(
                "success" to false,
                "error" to mapOf("code" to "TAB_CHANGED", "message" to "The pinned tab is no longer active; the run will not act on another tab"),
            )
        }
        val body = if (pinnedTabId != null) args + ("tabId" to pinnedTabId) else args
        return router.handle(method, body).second
    }
}
