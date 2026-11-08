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

    /**
     * Bounded tool-calling check (mirrors Swift `runToolProbe`): only a `get_time` call whose
     * parsed arguments carry a non-empty string `timezone` counts as evidence. Any other
     * outcome, including a failed request, records `toolCalling: false` with source `test`.
     */
    private suspend fun toolCalling(
        endpoint: OpenAIEndpoint,
        model: String,
    ): Map<String, Any?> {
        val payload =
            request(
                model,
                "Use the $PROBE_TOOL tool with timezone \"UTC\". Do not answer in text.",
                extra =
                    mapOf(
                        "tools" to JsonArray(listOf(probeToolDefinition())),
                        "max_tokens" to JsonPrimitive(TOOL_PROBE_MAX_TOKENS),
                        "temperature" to JsonPrimitive(0),
                    ),
            )
        val (ok, detail) =
            try {
                val chat = service.client.chat(endpoint.url, service.store.apiKey(endpoint.id), payload, stream = false)
                judgeToolProbe(chat)
            } catch (e: CancellationException) {
                throw e
            } catch (e: OpenAIException) {
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

    companion object {
        const val PROBE_TOOL = "get_time"
        private const val TOOL_PROBE_MAX_TOKENS = 512

        /** Only a well-formed `get_time` call with a non-empty `timezone` counts as tool-calling evidence. */
        fun judgeToolProbe(chat: ChatResult): Pair<Boolean, String> {
            val call = chat.toolCalls.firstOrNull() ?: return false to "The model answered without calling the tool."
            val timezone = OpenAIJson.string(call.parsedArguments()?.get("timezone"))?.trim()
            if (call.name != PROBE_TOOL || timezone.isNullOrEmpty()) {
                return false to
                    "The model's tool call was not a valid $PROBE_TOOL call with a timezone (${call.name}: ${call.arguments.take(80)})."
            }
            return true to "Called $PROBE_TOOL with timezone $timezone."
        }

        fun probeToolDefinition(): JsonObject {
            val parameters =
                JsonObject(
                    mapOf(
                        "type" to JsonPrimitive("object"),
                        "properties" to JsonObject(mapOf("timezone" to JsonObject(mapOf("type" to JsonPrimitive("string"))))),
                        "required" to JsonArray(listOf(JsonPrimitive("timezone"))),
                    ),
                )
            val function =
                JsonObject(
                    mapOf(
                        "name" to JsonPrimitive(PROBE_TOOL),
                        "description" to JsonPrimitive("Returns the current time in a timezone."),
                        "parameters" to parameters,
                    ),
                )
            return JsonObject(mapOf("type" to JsonPrimitive("function"), "function" to function))
        }

        private const val GENERATION_MAX_TOKENS = 32
        private const val TEXT_PREVIEW_CHARS = 200
    }
}
