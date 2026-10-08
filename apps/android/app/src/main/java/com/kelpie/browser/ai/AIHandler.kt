package com.kelpie.browser.ai

import android.content.Context
import android.os.SystemClock
import com.kelpie.browser.ai.openai.OpenAIEndpointsHandler
import com.kelpie.browser.ai.openai.OpenAIRuntime
import com.kelpie.browser.ai.openai.RouterAgentToolBridge
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.io.IOException

class AIHandler(
    private val appContext: Context,
    private val ctx: HandlerContext,
) {
    private val platformEngine by lazy { PlatformAIEngine(appContext) }
    private val recorder by lazy { AudioRecorder(appContext) }
    private var openAI: OpenAIEndpointsHandler? = null

    fun register(router: Router) {
        OpenAIRuntime.initialize(appContext)
        openAI =
            OpenAIEndpointsHandler(runtime = { OpenAIRuntime.parts() }, agentTools = RouterAgentToolBridge(router, ctx))
                .also { it.register(router) }
        router.register("ai-status") { if (AIState.backend == "native") LocalInference.execute("status") else aiStatus() }
        router.register("ai-load") { aiLoad(it) }
        router.register("ai-unload") { aiUnload() }
        router.register("ai-infer") { aiInfer(it) }
        router.register("ai-record") { aiRecord(it) }
        router.register("ai-catalog") { aiCatalog() }
        router.register("ai-fitness") { aiFitness(it) }
        router.register("ai-cancel") {
            LocalInference.cancel()
            successResponse(mapOf("cancelled" to OpenAIRuntime.parts().inference.cancelAll()))
        }
    }

    private fun aiCatalog(): Map<String, Any?> {
        val manager =
            ctx.aiManager
                ?: return errorResponse("AI_UNAVAILABLE", "AI manager is not initialized")
        val token = AIState.huggingFaceToken
        if (token.isEmpty()) {
            return errorResponse(
                "AUTH_REQUIRED",
                "HuggingFace API key required. Set it in Settings before downloading models.",
            )
        }
        manager.hfToken = token
        return successResponse(mapOf("models" to AIHttpJson.parseJsonArray(manager.listApprovedModels())))
    }

    private fun aiFitness(body: Map<String, Any?>): Map<String, Any?> {
        val modelId = (body["model"] as? String)?.trim().orEmpty()
        if (modelId.isEmpty()) {
            return errorResponse("MISSING_PARAM", "model is required")
        }
        val manager =
            ctx.aiManager
                ?: return errorResponse("AI_UNAVAILABLE", "AI manager is not initialized")
        val token = AIState.huggingFaceToken
        if (token.isEmpty()) {
            return errorResponse(
                "AUTH_REQUIRED",
                "HuggingFace API key required. Set it in Settings before downloading models.",
            )
        }
        manager.hfToken = token
        val ramGB = (body["ramGB"] as? Number)?.toDouble() ?: 0.0
        val diskGB = (body["diskGB"] as? Number)?.toDouble() ?: 0.0
        return successResponse(AIHttpJson.parseJsonObject(manager.modelFitness(modelId, ramGB, diskGB)))
    }

    private fun aiStatus(): Map<String, Any?> {
        val backend = currentBackend()
        if (backend == AIState.OPENAI_BACKEND) return requireOpenAI().status()
        val model = currentModel()
        val data =
            linkedMapOf<String, Any?>(
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
        if (body["backend"] == "native") return LocalInference.load(appContext, body)
        if (body["backend"] == AIState.OPENAI_BACKEND) return requireOpenAI().load(body)
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
            val token = AIState.huggingFaceToken
            if (token.isEmpty()) {
                return errorResponse(
                    "AUTH_REQUIRED",
                    "HuggingFace API key required. Set it in Settings before downloading models.",
                )
            }
            ctx.aiManager?.hfToken = token
            return errorResponse(
                "MODEL_NOT_FOUND",
                "Android supports the platform backend or ollama: model IDs",
            )
        }

        val endpoint =
            normalizeEndpoint(
                (body["ollamaEndpoint"] as? String)?.trim().takeUnless { it.isNullOrEmpty() }
                    ?: AIState.ollamaEndpoint
                    ?: AIState.DEFAULT_OLLAMA_ENDPOINT,
            )
        val ollamaModel = requestedModel.removePrefix("ollama:")

        val installedModels =
            try {
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

    private suspend fun aiUnload(): Map<String, Any?> {
        LocalInference.cancel()
        val local = LocalInference.execute("unload")
        if (local["success"] != true) return local
        requireOpenAI().unload()
        AIState.backend = AIState.PLATFORM_BACKEND
        AIState.activeModel = null

        return successResponse(
            mapOf(
                "backend" to currentBackend(),
                "model" to currentModel(),
            ),
        )
    }

    /** Exactly one backend serves each request; a failing backend never falls back to another. */
    private val inferDispatch by lazy {
        AIInferDispatch(
            mapOf<String, AIBackendInfer>(
                AIState.OLLAMA_BACKEND to ::inferWithOllama,
                AIState.PLATFORM_BACKEND to ::inferWithPlatform,
                AIState.OPENAI_BACKEND to { body -> requireOpenAI().infer(body) },
                "native" to { body -> LocalInference.execute("infer", body) },
            ),
        )
    }

    private suspend fun aiInfer(body: Map<String, Any?>): Map<String, Any?> = inferDispatch.infer(currentBackend(), body)

    private fun requireOpenAI(): OpenAIEndpointsHandler = openAI ?: error("AIHandler.register must run before AI requests")

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
            val code =
                when {
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

        val prompt =
            buildPrompt(body)
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
        val endpoint =
            AIState.ollamaEndpoint
                ?: return errorResponse("OLLAMA_NOT_AVAILABLE", "Ollama endpoint is not configured")
        val model =
            AIState.activeModel
                ?: return errorResponse("NO_MODEL_LOADED", "Load a model first with ai-load")

        if (body["audio"] != null) {
            return errorResponse(
                "AUDIO_NOT_SUPPORTED",
                "Android does not proxy audio requests to Ollama yet",
            )
        }

        val prompt =
            buildPrompt(body)
                ?: return errorResponse("MISSING_PARAM", "prompt is required")
        val messages = parseMessages(body["messages"])
        val images = extractImages(body)
        val start = SystemClock.elapsedRealtime()

        return try {
            val isChat = messages.isNotEmpty()
            val response =
                if (isChat) {
                    AIHttpJson.postJson(
                        url = "$endpoint/api/chat",
                        payload = buildChatRequest(model, messages, prompt, body),
                    )
                } else {
                    AIHttpJson.postJson(
                        url = "$endpoint/api/generate",
                        payload = buildGenerateRequest(model, prompt, images, body),
                    )
                }

            val responseText =
                if (isChat) {
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

    private fun currentBackend(): String = AIState.backend

    private fun currentModel(): String? =
        when (currentBackend()) {
            AIState.OLLAMA_BACKEND -> AIState.activeModel
            AIState.PLATFORM_BACKEND -> if (AIState.isAvailable) AIState.PLATFORM_MODEL_ID else null
            else -> null
        }

    private fun capabilitiesFor(
        backend: String,
        model: String?,
    ): List<String> =
        when (backend) {
            AIState.OLLAMA_BACKEND -> if (looksVisionCapable(model)) listOf("text", "vision") else listOf("text")
            AIState.PLATFORM_BACKEND -> if (AIState.isAvailable) listOf("text") else emptyList()
            else -> emptyList()
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
        val explicitImages =
            (body["images"] as? List<*>)
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
        val request =
            linkedMapOf<String, Any?>(
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

        val request =
            linkedMapOf<String, Any?>(
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
        val response = AIHttpJson.getJson("$endpoint/api/tags")
        val models = response["models"] as? List<*> ?: return emptyList()
        return models.mapNotNull { item ->
            val model = item as? Map<*, *> ?: return@mapNotNull null
            model["name"] as? String
        }
    }

    private fun estimateTokens(text: String): Int = (text.length / 4.0).toInt().coerceAtLeast(1)

    private fun normalizeEndpoint(endpoint: String): String = endpoint.trim().trimEnd('/')
}
