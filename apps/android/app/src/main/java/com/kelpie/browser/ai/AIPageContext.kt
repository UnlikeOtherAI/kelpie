package com.kelpie.browser.ai

import com.kelpie.browser.ai.openai.OpenAIException
import com.kelpie.browser.ai.openai.RouterAgentToolBridge

/** Models consume bounded common observations; rich HTTP extraction remains a separate API. */
object AIPageContext {
    suspend fun prepare(body: Map<String, Any?>, bridge: RouterAgentToolBridge?): Map<String, Any?> {
        AIConversation.messages(body)
        val mode = body["context"] as? String ?: return body
        val available = bridge ?: throw OpenAIException("AI_UNAVAILABLE", "Browser router is unavailable")
        return body + ("text" to available.pageContext(mode, body["tabId"] as? String))
    }

    fun validateMode(mode: String) {
        when (mode) {
            "page_text", "dom", "accessibility", "accessibility_tree" -> Unit
            "screenshot" -> throw OpenAIException("VISION_NOT_SUPPORTED", "Screenshot context is not sent to OpenAI-compatible endpoints")
            else -> throw OpenAIException("INVALID_PARAM", "context must be page_text, dom or accessibility")
        }
    }

    fun evidence(result: Map<String, Any?>): String {
        if (result["ok"] != true) {
            val error = result["error"] as? Map<*, *>
            throw OpenAIException(error?.get("code") as? String ?: "EVAL_ERROR", error?.get("message") as? String ?: "Could not read page context")
        }
        val value = result["value"] as? Map<*, *>
        val elements = value?.get("elements") as? List<*>
        if (value?.get("title") !is String || value["url"] !is String || value["text"] !is String || value["truncated"] !is Boolean || elements == null) {
            throw OpenAIException("EVAL_ERROR", "Invalid common page snapshot")
        }
        return AIConversation.pageEvidence(mapOf(
            "title" to value["title"], "url" to value["url"], "content" to value["text"],
            "truncated" to value["truncated"], "accessibleLabels" to elements.mapNotNull { (it as? Map<*, *>)?.get("name") as? String },
        ))
    }
}
