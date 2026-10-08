package com.kelpie.browser.ai.openai

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.CancellationException

/**
 * Device HTTP methods for OpenAI-compatible endpoints plus the openai branches of
 * `ai-load`, `ai-status` and `ai-infer`. API keys are accepted on save but never returned.
 */
class OpenAIEndpointsHandler(
    private val runtime: () -> OpenAIRuntimeParts,
    private val agentTools: AgentToolBridge,
) {
    fun register(router: Router) {
        router.register("ai-endpoints") { guard { runtime().service.listPublic() } }
        router.register("ai-endpoint-save") { body -> guard { save(body) } }
        router.register("ai-endpoint-remove") { body -> guard { remove(body) } }
        router.register("ai-endpoint-models") { body -> guard { models(body) } }
        router.register("ai-endpoint-test") { body -> guard { test(body) } }
        router.register("ai-endpoint-health") { body -> guard { health(body) } }
        router.register("ai-cancel") { guard { mapOf("cancelled" to runtime().inference.cancelAll()) } }
    }

    /** `ai-load {backend: "openai", endpoint, model?}`. */
    suspend fun load(body: Map<String, Any?>): Map<String, Any?> =
        guard {
            val endpoint = (body["endpoint"] as? String) ?: (body["endpointId"] as? String)
            val result = runtime().service.activate(endpoint, body["model"] as? String)
            runtime().monitor.refresh()
            result
        }

    fun status(): Map<String, Any?> = successResponse(runtime().service.statusPublic())

    suspend fun infer(body: Map<String, Any?>): Map<String, Any?> {
        val request = InferRequest.fromBody(body)
        val dispatcher =
            try {
                agentTools.pinnedDispatcher(request.tabId)
            } catch (e: OpenAIException) {
                return errorResponse(e.code, e.message, e.diagnostics)
            }
        return runtime().inference.infer(request, dispatcher, agentTools::pageContext)
    }

    /** ai-unload: forget the persisted selection so it is not restored at launch. */
    fun unload() {
        runtime().service.clearSelection()
        runtime().monitor.refresh()
    }

    private fun save(body: Map<String, Any?>): Map<String, Any?> {
        val saved = runtime().service.save(EndpointBodyParser.saveInput(body))
        runtime().monitor.refresh()
        return mapOf("endpoint" to runtime().service.endpointPublic(saved))
    }

    private fun remove(body: Map<String, Any?>): Map<String, Any?> {
        val removed = runtime().service.remove(body["id"] as? String ?: "")
        runtime().monitor.refresh()
        return mapOf("removed" to removed)
    }

    private suspend fun models(body: Map<String, Any?>): Map<String, Any?> {
        val result = runtime().service.discover(body["id"] as? String ?: "")
        val data = linkedMapOf<String, Any?>("models" to result.models.map { it.toPublic() })
        result.warning?.let { data["warning"] = it }
        return data
    }

    private suspend fun test(body: Map<String, Any?>): Map<String, Any?> =
        runtime().tester.test(
            id = body["id"] as? String,
            model = body["model"] as? String,
            generate = body["generate"] as? Boolean ?: true,
            tools = body["tools"] as? Boolean ?: false,
        )

    private suspend fun health(body: Map<String, Any?>): Map<String, Any?> = mapOf("health" to runtime().service.health(body["id"] as? String, body["refresh"] == true))

    private suspend fun guard(block: suspend () -> Map<String, Any?>): Map<String, Any?> =
        try {
            successResponse(block())
        } catch (e: CancellationException) {
            throw e
        } catch (e: OpenAIException) {
            errorResponse(e.code, e.message, e.diagnostics)
        }
}

/** The runtime pieces the handler needs; lets tests supply fakes without Android. */
class OpenAIRuntimeParts(
    val service: OpenAIEndpointService,
    val inference: OpenAIInference,
    val tester: EndpointTester,
    val monitor: HealthMonitor,
)

/** Android-side tab pinning and page-context gathering for agent and plain runs. */
interface AgentToolBridge {
    /** Pins [tabId] (or the active tab) and returns a dispatcher bound to it. */
    suspend fun pinnedDispatcher(tabId: String?): ToolDispatcher

    /** Returns page context for `context` (`page_text`, `dom`, `accessibility`) as text. */
    suspend fun pageContext(mode: String): String?
}

/** Parses `ai-endpoint-save` bodies. `null` in `capabilities` clears a user override. */
object EndpointBodyParser {
    fun saveInput(body: Map<String, Any?>): EndpointSaveInput {
        val capabilities = body["capabilities"] as? Map<*, *> ?: emptyMap<String, Any?>()
        return EndpointSaveInput(
            id = (body["id"] as? String)?.takeIf { it.isNotBlank() },
            name = body["name"] as? String ?: "",
            baseURL =
                body["baseURL"] as? String
                    ?: throw OpenAIException(OpenAIErrorCode.INVALID_ENDPOINT_URL, "baseURL is required"),
            apiKey = body["apiKey"] as? String,
            clearApiKey = body["clearApiKey"] == true,
            model = if (body.containsKey("model")) Patch(stringOrInvalid(body["model"], "model")) else null,
            contextWindow = patch(capabilities, "contextWindow") { (it as? Number)?.toInt() },
            vision = patch(capabilities, "vision") { it as? Boolean },
            toolCalling = patch(capabilities, "toolCalling") { it as? Boolean },
            jsonSchema = patch(capabilities, "jsonSchema") { it as? Boolean },
        )
    }

    private fun <T> patch(
        capabilities: Map<*, *>,
        key: String,
        convert: (Any) -> T?,
    ): Patch<T>? {
        if (!capabilities.containsKey(key)) return null
        val raw = capabilities[key] ?: return Patch(null)
        val value = (if (raw is Map<*, *>) raw["value"] else raw) ?: return Patch(null)
        return Patch(convert(value) ?: throw OpenAIException("INVALID_PARAM", "capabilities.$key has the wrong type"))
    }

    private fun stringOrInvalid(
        value: Any?,
        key: String,
    ): String? {
        if (value == null) return null
        return value as? String ?: throw OpenAIException("INVALID_PARAM", "$key must be a string")
    }
}
