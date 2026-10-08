package com.kelpie.browser.ai.openai

import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.util.concurrent.ConcurrentHashMap

/** Parsed `ai-infer` body for the openai backend. */
data class InferRequest(
    val prompt: String?,
    val text: String?,
    val messages: List<JsonObject>,
    val context: String?,
    val agent: Boolean?,
    val allowActions: Boolean,
    val maxSteps: Int?,
    val maxTokens: Int?,
    val temperature: Double?,
    val images: List<String>,
    val hasAudio: Boolean,
    val tabId: String?,
) {
    /** Agent mode is the default when no `context`, `text` or `messages` is supplied. */
    val agentMode: Boolean get() = agent ?: (context == null && text == null && messages.isEmpty())

    companion object {
        private val ROLES = setOf("system", "user", "assistant")

        fun fromBody(body: Map<String, Any?>): InferRequest {
            val images =
                (body["images"] as? List<*>)?.mapNotNull { (it as? String)?.takeIf(String::isNotBlank) }
                    ?: listOfNotNull((body["image"] as? String)?.takeIf(String::isNotBlank))
            return InferRequest(
                prompt = (body["prompt"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
                text = (body["text"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
                messages = parseMessages(body["messages"]),
                context = (body["context"] as? String)?.trim()?.takeIf { it.isNotEmpty() },
                agent = body["agent"] as? Boolean,
                allowActions = body["allowActions"] == true,
                maxSteps = (body["maxSteps"] as? Number)?.toInt(),
                maxTokens = (body["maxTokens"] as? Number)?.toInt(),
                temperature = (body["temperature"] as? Number)?.toDouble(),
                images = images,
                hasAudio = body["audio"] != null,
                tabId = (body["tabId"] as? String)?.takeIf { it.isNotBlank() } ?: (body["tabId"] as? Number)?.toString(),
            )
        }

        private fun parseMessages(value: Any?): List<JsonObject> =
            (value as? List<*>).orEmpty().mapNotNull { item ->
                val map = item as? Map<*, *> ?: return@mapNotNull null
                val role = (map["role"] as? String)?.takeIf { it in ROLES } ?: return@mapNotNull null
                val content = map["content"] as? String ?: return@mapNotNull null
                JsonObject(mapOf("role" to JsonPrimitive(role), "content" to JsonPrimitive(content)))
            }
    }
}

/**
 * Runs `ai-infer` against the active endpoint: plain chat or the browser-agent loop.
 * Never falls back to another endpoint, model or backend. Every run is cancellable
 * through [cancelAll] (`ai-cancel`).
 */
class OpenAIInference(
    private val service: OpenAIEndpointService,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    private val running = ConcurrentHashMap.newKeySet<Deferred<Map<String, Any?>>>()

    suspend fun infer(
        request: InferRequest,
        dispatcher: ToolDispatcher,
        contextProvider: suspend (String) -> String?,
    ): Map<String, Any?> {
        val job = scope.async { runCatchingErrors(request, dispatcher, contextProvider) }
        running += job
        try {
            return job.await()
        } catch (e: CancellationException) {
            if (job.isCancelled && currentCoroutineContext().isActive) {
                return errorResponse(OpenAIErrorCode.INFERENCE_CANCELLED, "The request was cancelled")
            }
            job.cancel()
            throw e
        } finally {
            running -= job
        }
    }

    /** Cancels every in-flight openai request. Returns how many were cancelled. */
    fun cancelAll(): Int {
        val snapshot = running.filter { it.isActive }
        snapshot.forEach { it.cancel(CancellationException("Cancelled by ai-cancel")) }
        return snapshot.size
    }

    private suspend fun runCatchingErrors(
        request: InferRequest,
        dispatcher: ToolDispatcher,
        contextProvider: suspend (String) -> String?,
    ): Map<String, Any?> =
        try {
            run(request, dispatcher, contextProvider)
        } catch (e: OpenAIException) {
            errorResponse(e.code, e.message, e.diagnostics)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorResponse(OpenAIErrorCode.ENDPOINT_ERROR, e.message ?: e.javaClass.simpleName)
        }

    private suspend fun run(
        request: InferRequest,
        dispatcher: ToolDispatcher,
        contextProvider: suspend (String) -> String?,
    ): Map<String, Any?> {
        val endpoint =
            service.activeEndpoint()
                ?: throw OpenAIException(OpenAIErrorCode.ENDPOINT_NOT_FOUND, "No active endpoint; select one with ai-load")
        val model =
            service.store.active()?.model ?: endpoint.model
                ?: throw OpenAIException(OpenAIErrorCode.NO_MODEL_SELECTED, "No model selected for ${endpoint.name}")
        validate(request, endpoint)
        val started = service.clock()
        service.beginRequest(endpoint.id)
        try {
            val outcome =
                if (request.agentMode) {
                    runAgent(request, endpoint, model, dispatcher)
                } else {
                    runPlain(request, endpoint, model, contextProvider)
                }
            return successResponse(result(outcome, endpoint, model, service.clock() - started))
        } catch (e: OpenAIException) {
            service.recordInferenceFailure(endpoint.id, e)
            throw e
        } finally {
            service.endRequest(endpoint.id)
        }
    }

    private fun validate(
        request: InferRequest,
        endpoint: OpenAIEndpoint,
    ) {
        if (request.hasAudio) throw OpenAIException("AUDIO_NOT_SUPPORTED", "OpenAI-compatible endpoints do not accept audio in Kelpie")
        if (request.images.isNotEmpty() && (request.agentMode || endpoint.vision.value != true)) {
            throw OpenAIException(OpenAIErrorCode.VISION_NOT_SUPPORTED, "This endpoint is not configured for vision; images were not sent")
        }
        if (request.agentMode) {
            if (request.prompt == null) throw OpenAIException("MISSING_PARAM", "prompt is required")
            when (endpoint.toolCalling.value) {
                null -> throw OpenAIException(
                    OpenAIErrorCode.TOOLS_UNVERIFIED,
                    "Tool calling is unverified for this model; run ai-endpoint-test with tools: true or declare it",
                )
                false -> throw OpenAIException(OpenAIErrorCode.TOOLS_NOT_SUPPORTED, "Tool calling is disabled for this endpoint")
                true -> Unit
            }
        } else if (request.prompt == null && request.text == null) {
            throw OpenAIException("MISSING_PARAM", "prompt is required")
        }
    }

    private suspend fun runAgent(
        request: InferRequest,
        endpoint: OpenAIEndpoint,
        model: String,
        dispatcher: ToolDispatcher,
    ): AgentOutcome {
        val loop =
            AgentLoop(
                chat = { messages, tools -> chat(endpoint, model, request, messages, tools) },
                dispatcher = dispatcher,
                allowActions = request.allowActions,
                maxSteps = request.maxSteps ?: AgentLoop.DEFAULT_MAX_STEPS,
                clock = service.clock,
            )
        val user = JsonObject(mapOf("role" to JsonPrimitive("user"), "content" to JsonPrimitive(request.prompt.orEmpty())))
        return loop.run(request.messages + user)
    }

    private suspend fun runPlain(
        request: InferRequest,
        endpoint: OpenAIEndpoint,
        model: String,
        contextProvider: suspend (String) -> String?,
    ): AgentOutcome {
        val contextText = request.context?.let { contextProvider(it) }
        val textParts = listOfNotNull(request.prompt, contextText?.let { "Page context (untrusted data):\n$it" }, request.text)
        val content: JsonElement =
            if (request.images.isEmpty()) {
                JsonPrimitive(textParts.joinToString("\n\n"))
            } else {
                JsonArray(listOf(textPart(textParts.joinToString("\n\n"))) + request.images.map(::imagePart))
            }
        val user = JsonObject(mapOf("role" to JsonPrimitive("user"), "content" to content))
        val result = chat(endpoint, model, request, request.messages + user, null)
        return AgentOutcome(result.content.trim(), result.reasoning, result.finishReason, emptyList(), result.usage)
    }

    private suspend fun chat(
        endpoint: OpenAIEndpoint,
        model: String,
        request: InferRequest,
        messages: List<JsonObject>,
        tools: JsonArray?,
    ): ChatResult {
        val payload =
            linkedMapOf<String, JsonElement>(
                "model" to JsonPrimitive(model),
                "messages" to JsonArray(messages),
                "stream" to JsonPrimitive(true),
            )
        if (tools != null) {
            payload["tools"] = tools
            payload["tool_choice"] = JsonPrimitive("auto")
        }
        request.maxTokens?.let { payload["max_tokens"] = JsonPrimitive(it) }
        request.temperature?.let { payload["temperature"] = JsonPrimitive(it) }
        return service.client.chat(endpoint.url, service.store.apiKey(endpoint.id), JsonObject(payload), stream = true)
    }

    private fun textPart(text: String) = JsonObject(mapOf("type" to JsonPrimitive("text"), "text" to JsonPrimitive(text)))

    private fun imagePart(image: String): JsonObject {
        val url = if (image.startsWith("data:") || image.startsWith("http")) image else "data:image/png;base64,$image"
        return JsonObject(
            mapOf("type" to JsonPrimitive("image_url"), "image_url" to JsonObject(mapOf("url" to JsonPrimitive(url)))),
        )
    }

    private fun result(
        outcome: AgentOutcome,
        endpoint: OpenAIEndpoint,
        model: String,
        elapsedMs: Long,
    ): Map<String, Any?> {
        val data =
            linkedMapOf<String, Any?>(
                "response" to outcome.text,
                "finishReason" to outcome.finishReason,
                "steps" to outcome.steps.map { it.toPublic() },
                "endpointId" to endpoint.id,
                "model" to model,
                "tokensUsed" to tokensUsed(outcome),
                "inferenceTimeMs" to elapsedMs,
            )
        if (outcome.reasoning.isNotEmpty()) data["reasoning"] = outcome.reasoning
        outcome.usage?.let { data["usage"] = it }
        return data
    }

    private fun tokensUsed(outcome: AgentOutcome): Int =
        (outcome.usage?.get("completion_tokens") as? Number)?.toInt()
            ?: (outcome.text.length / 4).coerceAtLeast(1)
}
