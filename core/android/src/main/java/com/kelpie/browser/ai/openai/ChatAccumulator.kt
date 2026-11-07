package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** A tool call assembled from (possibly fragmented) deltas. Arguments are parsed only at the end. */
data class AssembledToolCall(
    val index: Int,
    val id: String?,
    val name: String,
    val arguments: String,
) {
    /** The parsed argument object, or null when the model produced malformed JSON. Empty means `{}`. */
    fun parsedArguments(): JsonObject? {
        if (arguments.isBlank()) return JsonObject(emptyMap())
        return OpenAIJson.parseObjectOrNull(arguments)
    }
}

/** The outcome of one chat completion. Reasoning is kept apart from the answer. */
data class ChatResult(
    val content: String,
    val reasoning: String,
    val toolCalls: List<AssembledToolCall>,
    val finishReason: String?,
    val usage: Map<String, Any?>?,
)

/**
 * Accumulates OpenAI chat-completion stream frames for choice 0. Also parses
 * non-streaming responses so both paths share one result model.
 */
class ChatAccumulator(
    private val apiKey: String? = null,
) {
    private val content = StringBuilder()
    private val reasoning = StringBuilder()
    private val toolCalls = sortedMapOf<Int, ToolCallBuilder>()
    private var finishReason: String? = null
    private var usage: Map<String, Any?>? = null

    var sawDone: Boolean = false
        private set

    /** Consumes the `data` payload of one SSE event. Returns true once `[DONE]` arrives. */
    fun consume(data: String): Boolean {
        val trimmed = data.trim()
        if (trimmed == DONE) {
            sawDone = true
            return true
        }
        if (trimmed.isEmpty()) return false
        val frame =
            OpenAIJson.parseObjectOrNull(trimmed)
                ?: throw OpenAIException(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, "The stream contained a frame that is not JSON")
        consumeFrame(frame)
        return false
    }

    /** Validates termination: `[DONE]` or a recorded `finish_reason`, else `ENDPOINT_STREAM_TRUNCATED`. */
    fun finish(): ChatResult {
        if (!sawDone && finishReason == null) {
            throw OpenAIException(OpenAIErrorCode.ENDPOINT_STREAM_TRUNCATED, "The stream ended before the model finished")
        }
        return result()
    }

    fun result(): ChatResult =
        ChatResult(
            content = content.toString(),
            reasoning = reasoning.toString(),
            toolCalls = toolCalls.values.map { it.build() },
            finishReason = finishReason,
            usage = usage,
        )

    private fun consumeFrame(frame: JsonObject) {
        frame["error"]?.let { throwServerError(it) }
        OpenAIJson.objectOrNull(frame["usage"])?.let { usage = OpenAIJson.toMap(it) }
        val choice = firstChoice(frame) ?: return
        OpenAIJson.objectOrNull(choice["delta"])?.let(::consumeMessage)
        OpenAIJson.string(choice["finish_reason"])?.let { finishReason = it }
    }

    /** Parses a whole non-streaming `chat/completions` body. */
    fun consumeCompleteResponse(body: String): ChatResult {
        val root =
            OpenAIJson.parseObjectOrNull(body)
                ?: throw OpenAIException(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, "The response is not a JSON object")
        root["error"]?.let { throwServerError(it) }
        OpenAIJson.objectOrNull(root["usage"])?.let { usage = OpenAIJson.toMap(it) }
        val choice =
            firstChoice(root)
                ?: throw OpenAIException(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, "The response has no choices")
        OpenAIJson.objectOrNull(choice["message"])?.let(::consumeMessage)
        OpenAIJson.string(choice["finish_reason"])?.let { finishReason = it }
        return result()
    }

    private fun firstChoice(frame: JsonObject): JsonObject? {
        val choices = frame["choices"] as? JsonArray ?: return null
        return choices.mapNotNull { it as? JsonObject }.firstOrNull { (OpenAIJson.int(it["index"]) ?: 0) == 0 }
    }

    private fun consumeMessage(message: JsonObject) {
        OpenAIJson.string(message["content"])?.let { content.append(it) }
        (OpenAIJson.string(message["reasoning_content"]) ?: OpenAIJson.string(message["reasoning"]))
            ?.let { reasoning.append(it) }
        OpenAIJson.arrayOrNull(message["tool_calls"])?.forEachIndexed { position, element ->
            consumeToolCall(position, element)
        }
    }

    private fun consumeToolCall(
        position: Int,
        element: JsonElement,
    ) {
        val call = element as? JsonObject ?: return
        val index = OpenAIJson.int(call["index"]) ?: position
        val builder = toolCalls.getOrPut(index) { ToolCallBuilder(index) }
        OpenAIJson.string(call["id"])?.takeIf { it.isNotEmpty() && builder.id == null }?.let { builder.id = it }
        val function = OpenAIJson.objectOrNull(call["function"]) ?: return
        OpenAIJson.string(function["name"])?.let { builder.appendName(it) }
        when (val arguments = function["arguments"]) {
            null -> Unit
            is JsonObject -> builder.arguments.append(OpenAIJson.encode(arguments))
            else -> OpenAIJson.string(arguments)?.let { builder.arguments.append(it) }
        }
    }

    private fun throwServerError(error: JsonElement): Nothing {
        val raw = OpenAIJson.objectOrNull(error)?.let { OpenAIJson.encode(JsonObject(mapOf("error" to it))) } ?: error.toString()
        throw OpenAIException(OpenAIErrorCode.ENDPOINT_ERROR, ServerErrorText.sanitize(raw, apiKey))
    }

    private class ToolCallBuilder(
        val index: Int,
    ) {
        var id: String? = null
        val name = StringBuilder()
        val arguments = StringBuilder()

        /** Servers that repeat the full name on every delta keep the first one; split names are concatenated. */
        fun appendName(fragment: String) {
            if (fragment.isEmpty() || name.toString() == fragment) return
            name.append(fragment)
        }

        fun build() = AssembledToolCall(index, id, name.toString(), arguments.toString())
    }

    companion object {
        const val DONE = "[DONE]"
    }
}
