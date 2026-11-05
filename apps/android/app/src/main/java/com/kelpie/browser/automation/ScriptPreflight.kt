package com.kelpie.browser.automation

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

    fun admit(normalized: Map<String, Any?>): Map<String, Any?> {
        if (normalized.containsKey("sessionId")) throw ScriptFailure("SESSION_UNSUPPORTED")
        if ((normalized["inputs"] as? Map<*, *>)?.isNotEmpty() == true) throw ScriptFailure("UNRESOLVED_INPUT")
        val actions = actions(normalized)
        if (actions.any { it["action"] !in supportedActions || it.containsKey("typingDelayMs") }) {
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
        return normalized
    }

    @Suppress("UNCHECKED_CAST")
    fun actions(script: Map<String, Any?>): List<Map<String, Any?>> = script["actions"] as List<Map<String, Any?>>
}
