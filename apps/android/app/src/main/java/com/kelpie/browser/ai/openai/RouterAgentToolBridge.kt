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
        val pinned = tabStore?.activeTabId?.value ?: tabId
        return PinnedTabDispatcher(router, pinned) { ctx.tabStore?.activeTabId?.value }
    }

    override suspend fun pageContext(mode: String): String? {
        val method =
            when (mode) {
                "page_text" -> "get-page-text"
                "dom" -> "get-dom"
                "accessibility", "accessibility_tree" -> "get-accessibility-tree"
                "screenshot" -> throw OpenAIException(OpenAIErrorCode.VISION_NOT_SUPPORTED, "Screenshot context is not sent to OpenAI-compatible endpoints")
                else -> throw OpenAIException("INVALID_PARAM", "context must be page_text, dom or accessibility")
            }
        val (_, result) = router.handle(method, emptyMap())
        if (result["success"] != true) return null
        val payload = if (mode == "page_text") result["content"] ?: result else result - "success"
        val text = payload as? String ?: OpenAIJson.encode(OpenAIJson.fromAny(payload))
        return AgentLoop.truncate(text, MAX_CONTEXT_CHARS)
    }

    private companion object {
        const val MAX_CONTEXT_CHARS = 32_000
    }
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
