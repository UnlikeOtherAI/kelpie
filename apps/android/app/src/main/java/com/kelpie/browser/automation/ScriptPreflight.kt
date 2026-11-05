package com.kelpie.browser.automation

import com.kelpie.browser.ai.openai.OpenAIJson

internal data class ScriptPacedPlan(
    val clearFirst: Boolean,
    val delayMs: Long,
    val scalars: List<String>,
)

/** Platform capability narrowing after the canonical C ABI has validated/defaulted v1. */
object ScriptPreflight {
    val supportedActions =
        setOf(
            "navigate",
            "click",
            "tap",
            "fill",
            "type",
            "scroll",
            "wait",
            "wait-ready",
            "assert",
            "screenshot",
            "commentary",
            "extract",
            "output",
        )

    fun admit(
        normalized: Map<String, Any?>,
        planner: (Map<String, Any?>) -> Map<String, Any?> = ::nativePlan,
    ): Map<String, Any?> {
        if (normalized.containsKey("sessionId")) throw ScriptFailure("SESSION_UNSUPPORTED")
        if ((normalized["inputs"] as? Map<*, *>)?.isNotEmpty() == true) throw ScriptFailure("UNRESOLVED_INPUT")
        val actions = actions(normalized)
        if (actions.any { it["action"] !in supportedActions }) {
            throw ScriptFailure("UNSUPPORTED_SCRIPT_ACTION")
        }
        val names = mutableSetOf<String>()
        for (action in actions) {
            if (action["action"] in setOf("fill", "type") && action["text"] !is String) {
                throw ScriptFailure("UNRESOLVED_INPUT")
            }
            if (action["action"] in setOf("extract", "output") && !names.add(action["name"] as String)) {
                throw ScriptFailure("DUPLICATE_OUTPUT")
            }
        }
        if (actions.any { it["sensitive"] == true } &&
            (normalized["capture"] != null || actions.any { it["action"] == "screenshot" })
        ) {
            throw ScriptFailure("SENSITIVE_CAPTURE_REFUSED")
        }
        val planned =
            actions.map { action ->
                if (!action.containsKey("typingDelayMs")) return@map action
                val request = mapOf("action" to action["action"], "text" to action["text"], "typingDelayMs" to action["typingDelayMs"])
                val result = planner(request)
                val scalars = (result["scalars"] as? List<*>)?.map { it as? String ?: throw ScriptFailure("INVALID_PACED_TYPING") }
                val delay = (result["typingDelayMs"] as? Number)?.toLong()
                val clearFirst = result["clearFirst"] as? Boolean
                if (result["valid"] != true || scalars == null || delay == null || clearFirst == null) {
                    throw ScriptFailure("INVALID_PACED_TYPING")
                }
                action + ("__pacedPlan" to ScriptPacedPlan(clearFirst, delay, scalars))
            }
        return normalized + ("actions" to planned)
    }

    private fun nativePlan(request: Map<String, Any?>): Map<String, Any?> {
        val encoded = OpenAIJson.encode(OpenAIJson.fromAny(request))
        val response = ScriptNative.typingPlan(encoded) ?: throw ScriptFailure("INVALID_PACED_TYPING")
        return OpenAIJson.parseObjectOrNull(response)?.let(OpenAIJson::toMap) ?: throw ScriptFailure("INVALID_PACED_TYPING")
    }

    @Suppress("UNCHECKED_CAST")
    fun actions(script: Map<String, Any?>): List<Map<String, Any?>> = script["actions"] as List<Map<String, Any?>>
}
