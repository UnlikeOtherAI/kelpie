package com.kelpie.browser.ai

import com.kelpie.browser.network.errorResponse

typealias AIBackendInfer = suspend (Map<String, Any?>) -> Map<String, Any?>

/**
 * Routes `ai-infer` to exactly one backend. A failure from the selected backend is
 * returned as-is: Kelpie never retries on, or silently falls back to, another backend.
 */
class AIInferDispatch(
    private val backends: Map<String, AIBackendInfer>,
) {
    suspend fun infer(
        backend: String,
        body: Map<String, Any?>,
    ): Map<String, Any?> {
        val handler = backends[backend] ?: return errorResponse("NO_MODEL_LOADED", "Load a model first with ai-load")
        return handler(body)
    }
}
