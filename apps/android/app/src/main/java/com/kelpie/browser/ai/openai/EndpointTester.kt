package com.kelpie.browser.ai.openai

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * `ai-endpoint-test`: probe, then optionally a tiny generation and a bounded
 * tool-calling check. Tool-calling evidence is stored with `source: "test"`.
 */
class EndpointTester(
    private val service: OpenAIEndpointService,
) {
    suspend fun test(
        id: String?,
        model: String?,
        generate: Boolean,
        tools: Boolean,
    ): Map<String, Any?> {
        val endpoint = service.resolve(id)
        val selected = model?.trim()?.takeIf { it.isNotEmpty() } ?: endpoint.model
        val outcome = service.probe(endpoint, selected)
        val result = linkedMapOf<String, Any?>()
        val online = service.healthOf(endpoint.id).state.online
        if (generate) result["generation"] = guarded(endpoint, selected, online) { generation(endpoint, selected!!) }
        if (tools) result["toolCalling"] = guarded(endpoint, selected, online) { toolCalling(endpoint, selected!!) }
        result["health"] = service.healthPublic(endpoint.id)
        result["models"] = (outcome as? ProbeOutcome.Discovered)?.models?.map { it.toPublic() } ?: emptyList<Any>()
        if (outcome is ProbeOutcome.Discovered && outcome.models.isEmpty()) {
            result["warning"] = OpenAIEndpointService.EMPTY_MODELS_WARNING
        }
        return result
    }

    private suspend fun guarded(
        endpoint: OpenAIEndpoint,
        model: String?,
        online: Boolean,
        block: suspend () -> Map<String, Any?>,
    ): Map<String, Any?> {
        if (model == null) return failure(OpenAIErrorCode.NO_MODEL_SELECTED, "No model selected", 0)
        if (!online) return failure(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "The endpoint is offline", 0)
        val started = service.clock()
        service.beginRequest(endpoint.id)
        return try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: OpenAIException) {
            service.recordInferenceFailure(endpoint.id, e)
            failure(e.code, e.message, service.clock() - started)
        } finally {
            service.endRequest(endpoint.id)
        }
    }

    private suspend fun generation(
        endpoint: OpenAIEndpoint,
        model: String,
    ): Map<String, Any?> {
        val started = service.clock()
        val payload =
            request(model, "Reply with the single word: ready", extra = mapOf("max_tokens" to JsonPrimitive(GENERATION_MAX_TOKENS)))
        val chat = service.client.chat(endpoint.url, service.store.apiKey(endpoint.id), payload, stream = false)
        service.recordGeneration(endpoint.id, model)
        return linkedMapOf(
            "ok" to true,
            "latencyMs" to (service.clock() - started),
            "text" to AgentLoop.truncate(chat.content.trim(), TEXT_PREVIEW_CHARS),
        )
    }

    private suspend fun toolCalling(
        endpoint: OpenAIEndpoint,
        model: String,
    ): Map<String, Any?> {
        val probeTool = AgentTools.all.first { it.name == PROBE_TOOL }
        val payload =
            request(
                model,
                "Call the $PROBE_TOOL tool now. Do not answer in text.",
                extra = mapOf("tools" to JsonArray(listOf(probeTool.definition())), "tool_choice" to JsonPrimitive("auto")),
            )
        val (ok, detail) =
            try {
                val chat = service.client.chat(endpoint.url, service.store.apiKey(endpoint.id), payload, stream = false)
                val called = chat.toolCalls.any { it.name == PROBE_TOOL }
                called to if (called) "The model returned a $PROBE_TOOL tool call" else "The model answered without calling the tool"
            } catch (e: OpenAIException) {
                if (e.code != OpenAIErrorCode.TOOLS_NOT_SUPPORTED) throw e
                false to e.message
            }
        val current = service.store.get(endpoint.id) ?: endpoint
        service.store.put(current.copy(testedToolCalling = ok, testedToolCallingModel = model))
        service.bump()
        return linkedMapOf("ok" to ok, "detail" to detail)
    }

    private fun request(
        model: String,
        prompt: String,
        extra: Map<String, JsonElement>,
    ): JsonObject {
        val message = JsonObject(mapOf("role" to JsonPrimitive("user"), "content" to JsonPrimitive(prompt)))
        return JsonObject(
            mapOf(
                "model" to JsonPrimitive(model),
                "messages" to JsonArray(listOf(message)),
                "stream" to JsonPrimitive(false),
            ) + extra,
        )
    }

    private fun failure(
        code: String,
        message: String,
        latencyMs: Long,
    ): Map<String, Any?> =
        linkedMapOf(
            "ok" to false,
            "latencyMs" to latencyMs,
            "detail" to message,
            "error" to mapOf("code" to code, "message" to message),
        )

    private companion object {
        const val PROBE_TOOL = "get_current_url"
        const val GENERATION_MAX_TOKENS = 32
        const val TEXT_PREVIEW_CHARS = 200
    }
}
