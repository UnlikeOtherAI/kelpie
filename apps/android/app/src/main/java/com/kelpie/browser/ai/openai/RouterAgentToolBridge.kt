package com.kelpie.browser.ai.openai

import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.network.Router
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Every model call uses a per-run shared gateway with the existing semantic-tool permissions. */
class RouterAgentToolBridge(
    private val router: Router,
    private val ctx: HandlerContext,
) : AgentToolBridge {
    override suspend fun pinnedDispatcher(
        tabId: String?,
        allowActions: Boolean,
    ): ToolDispatcher {
        val pinned = pin(tabId, allowActions)
        val binding = checkNotNull(router.browserGateway)
        val session = binding.agentSession(allowActions, pinned)
        try {
            val catalog = session.call(mapOf("jsonrpc" to "2.0", "id" to 1, "method" to "tools/list"), mcp = true)
            val result = catalog?.get("result") as? Map<*, *> ?: error("Missing gateway catalog")
            val definitions =
                (result["tools"] as? List<*>).orEmpty().map { item ->
                    val tool = item as Map<*, *>
                    JsonObject(
                        mapOf(
                            "type" to JsonPrimitive("function"),
                            "function" to
                                OpenAIJson.fromAny(
                                    mapOf("name" to tool["name"], "description" to tool["description"], "parameters" to tool["inputSchema"]),
                                ),
                        ),
                    )
                }
            return object : ToolDispatcher {
                override val tools = JsonArray(definitions)
                override val pinnedTabId = pinned

                override suspend fun dispatch(
                    method: String,
                    args: Map<String, Any?>,
                ): Map<String, Any?> {
                    val response =
                        session
                            .call(
                                mapOf(
                                    "jsonrpc" to "2.0",
                                    "id" to 1,
                                    "method" to "tools/call",
                                    "params" to mapOf("name" to method, "arguments" to args),
                                ),
                                mcp = true,
                            ).orEmpty()
                    val payload = response["result"] as? Map<*, *> ?: return response
                    val text =
                        (payload["content"] as? List<*>)
                            ?.mapNotNull { it as? Map<*, *> }
                            ?.firstOrNull { it["type"] == "text" }
                            ?.get("text") as? String
                    return text?.let { OpenAIJson.parseObjectOrNull(it)?.let(OpenAIJson::toMap) }
                        ?: mapOf("ok" to false, "error" to "Invalid gateway tool result")
                }

                override suspend fun close() {
                    binding.closeSession(session)
                }
            }
        } catch (error: Exception) {
            kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) { binding.closeSession(session) }
            throw error
        }
    }

    private suspend fun pin(
        tabId: String?,
        allowActions: Boolean,
    ): String {
        val store = ctx.tabStore
        if (tabId != null && store != null && store.activeTabId.value != tabId) {
            if (!allowActions) throw OpenAIException("TAB_CHANGED", "Read-only inference cannot switch tabs")
            val result = router.handle("switch-tab", mapOf("tabId" to tabId)).second
            if (result["success"] != true) throw OpenAIException("TAB_NOT_FOUND", "No tab with id $tabId")
        }
        return store?.activeTabId?.value ?: tabId ?: "0"
    }

    override suspend fun pageContext(
        mode: String,
        tabId: String?,
    ): String? {
        val pinned = pin(tabId, false)
        val method =
            when (mode) {
                "page_text" -> "get-page-text"
                "dom" -> "get-dom"
                "accessibility", "accessibility_tree" -> "get-accessibility-tree"
                "screenshot" -> throw OpenAIException(OpenAIErrorCode.VISION_NOT_SUPPORTED, "Screenshot context is not sent to OpenAI-compatible endpoints")
                else -> throw OpenAIException("INVALID_PARAM", "context must be page_text, dom or accessibility")
            }
        val result = router.browserGateway?.readContext(pinned, method) ?: return null
        if (result["success"] != true) throw OpenAIException("TAB_CHANGED", "Could not read the pinned tab")
        val payload = if (mode == "page_text") result["content"] ?: result else result - "success"
        val text = payload as? String ?: OpenAIJson.encode(OpenAIJson.fromAny(payload))
        return AgentLoop.truncate(text, 24_000)
    }
}
