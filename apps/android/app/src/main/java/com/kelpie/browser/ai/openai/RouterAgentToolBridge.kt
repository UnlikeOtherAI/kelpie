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
            val catalogResult = catalog?.get("result") as? Map<*, *> ?: error("Missing gateway catalog")
            val definitions =
                (catalogResult["tools"] as? List<*>).orEmpty().map { item ->
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
                    val result =
                        text?.let { OpenAIJson.parseObjectOrNull(it)?.let(OpenAIJson::toMap) }
                            ?: mapOf("ok" to false, "error" to "Invalid gateway tool result")
                    if ((result["error"] as? Map<*, *>)?.get("mayHaveCompleted") == true) {
                        throw OpenAIException("ACTION_UNCERTAIN", "The action may have completed. This run stopped; observe and reconcile in a later request.", diagnostics = result)
                    }
                    return result
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

    override suspend fun contextDispatcher(tabId: String?): ToolDispatcher {
        val target = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main.immediate) {
            val id = tabId ?: ctx.tabStore?.activeTabId?.value ?: "0"
            if (ctx.tabStore != null && ctx.tabStore?.tabs?.value?.none { it.id == id } == true) {
                throw OpenAIException("TAB_NOT_FOUND", "Tab $id not found")
            }
            id
        }
        return object : ToolDispatcher {
            override val pinnedTabId = target
            override suspend fun dispatch(method: String, args: Map<String, Any?>): Map<String, Any?> =
                throw OpenAIException("UNSUPPORTED", "Plain inference does not expose browser tools")
        }
    }

    override suspend fun pageContext(mode: String, tabId: String?): String? {
        com.kelpie.browser.ai.AIPageContext.validateMode(mode)
        val result = router.browserGateway?.contextSnapshot(tabId)
            ?: throw OpenAIException("AI_UNAVAILABLE", "Browser router is unavailable")
        return com.kelpie.browser.ai.AIPageContext.evidence(result)
    }
}
