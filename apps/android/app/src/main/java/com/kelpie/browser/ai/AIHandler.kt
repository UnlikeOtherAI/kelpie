package com.kelpie.browser.ai

import android.content.Context
import android.os.SystemClock
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

private val aiJson = Json { ignoreUnknownKeys = true; isLenient = true }

class AIHandler(private val appContext: Context) {
    private val platformEngine by lazy { PlatformAIEngine(appContext) }
    private val recorder by lazy { AudioRecorder(appContext) }

    fun register(router: Router) {
        router.register("ai-status") { aiStatus() }
        router.register("ai-load") { aiLoad(it) }
        router.register("ai-unload") { aiUnload() }
        router.register("ai-infer") { aiInfer(it) }
        router.register("ai-record") { aiRecord(it) }
    }

    private fun aiStatus(): Map<String, Any?> {
        val backend = currentBackend()
        val model = currentModel()
        val data = linkedMapOf<String, Any?>(
            "loaded" to (model != null),
            "backend" to backend,
            "capabilities" to capabilitiesFor(backend, model),
        )
        if (model != null) {
            data["model"] = model
        }
        if (backend == AIState.OLLAMA_BACKEND) {
            data["ollamaEndpoint"] = AIState.ollamaEndpoint
        }
        return successResponse(data)
    }

    private suspend fun aiLoad(body: Map<String, Any?>): Map<String, Any?> {
        val requestedModel = (body["model"] as? String)?.trim().orEmpty()
        val start = SystemClock.elapsedRealtime()

        if (requestedModel.isEmpty() || requestedModel == AIState.PLATFORM_MODEL_ID) {
            if (!AIState.isAvailable) {
                return errorResponse(
                    "PLATFORM_AI_UNAVAILABLE",
                    "Platform AI is not available on this device",
                )
            }

            AIState.backend = AIState.PLATFORM_BACKEND
            AIState.activeModel = null

            return successResponse(
                mapOf(
                    "model" to AIState.PLATFORM_MODEL_ID,
                    "backend" to AIState.PLATFORM_BACKEND,
                    "loadTimeMs" to (SystemClock.elapsedRealtime() - start),
                ),
            )
        }

        if (!requestedModel.startsWith("ollama:")) {
            return errorResponse(
                "MODEL_NOT_FOUND",
                "Android supports the platform backend or ollama: model IDs",
            )
        }

        val endpoint = normalizeEndpoint(
            (body["ollamaEndpoint"] as? String)?.trim().takeUnless { it.isNullOrEmpty() }
                ?: AIState.ollamaEndpoint
                ?: AIState.DEFAULT_OLLAMA_ENDPOINT,
        )
        val ollamaModel = requestedModel.removePrefix("ollama:")

        val installedModels = try {
            fetchOllamaModels(endpoint)
        } catch (_: IOException) {
            return errorResponse("OLLAMA_NOT_AVAILABLE", "Ollama is not running at $endpoint")
        } catch (e: Exception) {
            return errorResponse("AI_INFERENCE_FAILED", e.message ?: "Failed to probe Ollama")
        }

        if (ollamaModel !in installedModels) {
            return errorResponse(
                "OLLAMA_MODEL_NOT_FOUND",
                "Ollama model '$ollamaModel' is not installed at $endpoint",
            )
        }

        AIState.backend = AIState.OLLAMA_BACKEND
        AIState.activeModel = ollamaModel
        AIState.ollamaEndpoint = endpoint

        return successResponse(
            mapOf(
                "model" to ollamaModel,
                "backend" to AIState.OLLAMA_BACKEND,
                "loadTimeMs" to (SystemClock.elapsedRealtime() - start),
            ),
        )
    }

    private fun aiUnload(): Map<String, Any?> {
        AIState.backend = AIState.PLATFORM_BACKEND
        AIState.activeModel = null

        return successResponse(
            mapOf(
                "backend" to currentBackend(),
                "model" to currentModel(),
            ),
        )
    }

    private suspend fun aiInfer(body: Map<String, Any?>): Map<String, Any?> {
        return when (currentBackend()) {
            AIState.OLLAMA_BACKEND -> inferWithOllama(body)
            AIState.PLATFORM_BACKEND -> inferWithPlatform(body)
            else -> errorResponse("NO_MODEL_LOADED", "Load a model first with ai-load")
        }
    }

    private fun aiRecord(body: Map<String, Any?>): Map<String, Any?> {
        val action = (body["action"] as? String)?.trim().orEmpty().ifEmpty { "status" }
        return try {
            when (action) {
                "start" -> {
                    recorder.start()
                    successResponse(mapOf("recording" to true, "elapsedMs" to 0))
                }
                "stop" -> {
                    val result = recorder.stop()
                    successResponse(
                        mapOf(
                            "recording" to false,
                            "audio" to android.util.Base64.encodeToString(result.audio, android.util.Base64.NO_WRAP),
                            "durationMs" to result.durationMs,
                        ),
                    )
                }
                "status" -> {
                    successResponse(
                        mapOf(
                            "recording" to recorder.isRecording,
                            "elapsedMs" to recorder.elapsedMs,
                        ),
                    )
                }
                else -> errorResponse("INVALID_PARAM", "action must be start, stop, or status")
            }
        } catch (e: SecurityException) {
            errorResponse("MIC_PERMISSION_DENIED", "Microphone permission not granted")
        } catch (e: IllegalStateException) {
            val code = when {
                e.message?.contains("ALREADY_ACTIVE") == true -> "RECORDING_ALREADY_ACTIVE"
                e.message?.contains("NO_RECORDING") == true -> "NO_RECORDING_ACTIVE"
                else -> "RECORDING_FAILED"
            }
            errorResponse(code, e.message ?: "Recording failed")
        }
    }

    private suspend fun inferWithPlatform(body: Map<String, Any?>): Map<String, Any?> {
        if (!AIState.isAvailable) {
            return errorResponse(
                "PLATFORM_AI_UNAVAILABLE",
                "Platform AI is not available on this device",
            )
        }
        if (body["image"] != null || body["images"] != null) {
            return errorResponse("VISION_NOT_SUPPORTED", "Platform AI on Android is text-only for now")
        }
        if (body["audio"] != null) {
            return errorResponse(
                "AUDIO_NOT_SUPPORTED",
                "Platform AI on Android does not accept audio input yet",
            )
        }

        val prompt = buildPrompt(body)
            ?: return errorResponse("MISSING_PARAM", "prompt is required")
        val start = SystemClock.elapsedRealtime()

        return try {
            val response = platformEngine.infer(prompt)
            successResponse(
                mapOf(
                    "response" to response,
                    "tokensUsed" to estimateTokens(response),
                    "inferenceTimeMs" to (SystemClock.elapsedRealtime() - start),
                ),
            )
        } catch (e: UnsupportedOperationException) {
            errorResponse("PLATFORM_AI_NOT_WIRED", e.message ?: "Platform AI is not yet wired")
        } catch (e: Exception) {
            errorResponse("AI_INFERENCE_FAILED", e.message ?: "Platform AI inference failed")
        }
    }

    private suspend fun inferWithOllama(body: Map<String, Any?>): Map<String, Any?> {
        val endpoint = AIState.ollamaEndpoint
            ?: return errorResponse("OLLAMA_NOT_AVAILABLE", "Ollama endpoint is not configured")
        val model = AIState.activeModel
            ?: return errorResponse("NO_MODEL_LOADED", "Load a model first with ai-load")

        if (body["audio"] != null) {
            return errorResponse(
                "AUDIO_NOT_SUPPORTED",
                "Android does not proxy audio requests to Ollama yet",
            )
        }

        val prompt = buildPrompt(body)
            ?: return errorResponse("MISSING_PARAM", "prompt is required")
        val messages = parseMessages(body["messages"])
        val images = extractImages(body)
        val start = SystemClock.elapsedRealtime()

        return try {
            val isChat = messages.isNotEmpty()
            val response = if (isChat) {
                postJson(
                    url = "$endpoint/api/chat",
                    payload = buildChatRequest(model, messages, prompt, body),
                )
            } else {
                postJson(
                    url = "$endpoint/api/generate",
                    payload = buildGenerateRequest(model, prompt, images, body),
                )
            }

            val responseText = if (isChat) {
                val message = response["message"] as? Map<*, *>
                message?.get("content") as? String
            } else {
                response["response"] as? String
            }?.trim().orEmpty()

            val tokensUsed = (response["eval_count"] as? Number)?.toInt() ?: estimateTokens(responseText)
            successResponse(
                mapOf(
                    "response" to responseText,
                    "tokensUsed" to tokensUsed,
                    "inferenceTimeMs" to (SystemClock.elapsedRealtime() - start),
                ),
            )
        } catch (_: IOException) {
            errorResponse("OLLAMA_DISCONNECTED", "Lost connection to Ollama during inference")
        } catch (e: Exception) {
            errorResponse("AI_INFERENCE_FAILED", e.message ?: "Ollama inference failed")
        }
    }

    private fun currentBackend(): String {
        return AIState.backend
    }

    private fun currentModel(): String? {
        return when (currentBackend()) {
            AIState.OLLAMA_BACKEND -> AIState.activeModel
            AIState.PLATFORM_BACKEND -> if (AIState.isAvailable) AIState.PLATFORM_MODEL_ID else null
            else -> null
        }
    }

    private fun capabilitiesFor(backend: String, model: String?): List<String> {
        return when (backend) {
            AIState.OLLAMA_BACKEND -> if (looksVisionCapable(model)) listOf("text", "vision") else listOf("text")
            AIState.PLATFORM_BACKEND -> if (AIState.isAvailable) listOf("text") else emptyList()
            else -> emptyList()
        }
    }

    private fun looksVisionCapable(model: String?): Boolean {
        if (model == null) return false
        val lowercase = model.lowercase()
        return listOf("llava", "vision", "moondream", "minicpm-v").any { lowercase.contains(it) }
    }

    private fun buildPrompt(body: Map<String, Any?>): String? {
        val prompt = (body["prompt"] as? String)?.trim().orEmpty()
        val text = (body["text"] as? String)?.trim().orEmpty()

        if (prompt.isEmpty() && text.isEmpty()) return null
        if (prompt.isEmpty()) return text
        if (text.isEmpty()) return prompt
        return "$prompt\n\n$text"
    }

    private fun extractImages(body: Map<String, Any?>): List<String> {
        val explicitImages = (body["images"] as? List<*>)
            ?.mapNotNull { it as? String }
            ?.filter { it.isNotBlank() }
            .orEmpty()
        if (explicitImages.isNotEmpty()) {
            return explicitImages
        }

        val singleImage = (body["image"] as? String)?.takeIf { it.isNotBlank() }
        return if (singleImage != null) listOf(singleImage) else emptyList()
    }

    private fun parseMessages(value: Any?): List<Map<String, String>> {
        val rawMessages = value as? List<*> ?: return emptyList()
        return rawMessages.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val role = map["role"] as? String ?: return@mapNotNull null
            val content = map["content"] as? String ?: return@mapNotNull null
            mapOf("role" to role, "content" to content)
        }
    }

    private fun buildGenerateRequest(
        model: String,
        prompt: String,
        images: List<String>,
        body: Map<String, Any?>,
    ): Map<String, Any?> {
        val request = linkedMapOf<String, Any?>(
            "model" to model,
            "prompt" to prompt,
            "stream" to false,
        )
        if (images.isNotEmpty()) {
            request["images"] = images
        }
        buildOllamaOptions(body)?.let { request["options"] = it }
        return request
    }

    private fun buildChatRequest(
        model: String,
        messages: List<Map<String, String>>,
        prompt: String,
        body: Map<String, Any?>,
    ): Map<String, Any?> {
        val requestMessages = messages.toMutableList()
        requestMessages.add(mapOf("role" to "user", "content" to prompt))

        val request = linkedMapOf<String, Any?>(
            "model" to model,
            "messages" to requestMessages,
            "stream" to false,
        )
        buildOllamaOptions(body)?.let { request["options"] = it }
        return request
    }

    private fun buildOllamaOptions(body: Map<String, Any?>): Map<String, Any?>? {
        val options = linkedMapOf<String, Any?>()

        val maxTokens = body["maxTokens"] as? Number
        if (maxTokens != null) {
            options["num_predict"] = maxTokens.toInt()
        }

        val temperature = body["temperature"] as? Number
        if (temperature != null) {
            options["temperature"] = temperature.toDouble()
        }

        return options.takeIf { it.isNotEmpty() }
    }

    private suspend fun fetchOllamaModels(endpoint: String): List<String> {
        val response = getJson("$endpoint/api/tags")
        val models = response["models"] as? List<*> ?: return emptyList()
        return models.mapNotNull { item ->
            val model = item as? Map<*, *> ?: return@mapNotNull null
            model["name"] as? String
        }
    }

    private suspend fun getJson(url: String): Map<String, Any?> = withContext(Dispatchers.IO) {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 3_000
            readTimeout = 10_000
            doInput = true
        }

        try {
            val body = readConnectionBody(connection)
            if (connection.responseCode !in 200..299) {
                throw IOException("HTTP ${connection.responseCode}: $body")
            }
            parseJsonObject(body)
        } finally {
            connection.disconnect()
        }
    }

    private suspend fun postJson(url: String, payload: Map<String, Any?>): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 3_000
                readTimeout = 30_000
                doInput = true
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Accept", "application/json")
            }

            try {
                connection.outputStream.bufferedWriter().use { writer ->
                    writer.write(mapToJsonString(payload))
                }

                val body = readConnectionBody(connection)
                if (connection.responseCode !in 200..299) {
                    throw IOException("HTTP ${connection.responseCode}: $body")
                }
                parseJsonObject(body)
            } finally {
                connection.disconnect()
            }
        }

    private fun readConnectionBody(connection: HttpURLConnection): String {
        val stream = if (connection.responseCode in 200..299) {
            connection.inputStream
        } else {
            connection.errorStream
        } ?: return ""

        return stream.bufferedReader().use { it.readText() }
    }

    private fun mapToJsonString(map: Map<String, Any?>): String {
        return aiJson.encodeToString(JsonElement.serializer(), mapToJsonObject(map))
    }

    private fun mapToJsonObject(map: Map<String, Any?>): JsonObject {
        return JsonObject(map.entries.associate { (key, value) -> key to anyToJsonElement(value) })
    }

    @Suppress("UNCHECKED_CAST")
    private fun anyToJsonElement(value: Any?): JsonElement = when (value) {
        null -> JsonNull
        is Boolean -> JsonPrimitive(value)
        is Int -> JsonPrimitive(value)
        is Long -> JsonPrimitive(value)
        is Double -> JsonPrimitive(value)
        is Float -> JsonPrimitive(value)
        is String -> JsonPrimitive(value)
        is Map<*, *> -> mapToJsonObject(value as Map<String, Any?>)
        is List<*> -> JsonArray(value.map { anyToJsonElement(it) })
        else -> JsonPrimitive(value.toString())
    }

    private fun parseJsonObject(text: String): Map<String, Any?> {
        if (text.isBlank()) return emptyMap()
        val element = aiJson.parseToJsonElement(text)
        return jsonObjectToMap(element.jsonObject)
    }

    private fun jsonObjectToMap(obj: JsonObject): Map<String, Any?> {
        return obj.entries.associate { (key, value) -> key to jsonElementToAny(value) }
    }

    private fun jsonElementToAny(element: JsonElement): Any? = when (element) {
        is JsonNull -> null
        is JsonPrimitive -> when {
            element.isString -> element.content
            element.booleanOrNull != null -> element.boolean
            element.intOrNull != null -> element.int
            element.doubleOrNull != null -> element.double
            else -> element.content
        }
        is JsonObject -> jsonObjectToMap(element)
        is JsonArray -> element.map { jsonElementToAny(it) }
    }

    private fun estimateTokens(text: String): Int {
        return (text.length / 4.0).toInt().coerceAtLeast(1)
    }

    private fun normalizeEndpoint(endpoint: String): String {
        return endpoint.trim().trimEnd('/')
    }
}
