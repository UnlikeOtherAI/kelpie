package com.kelpie.browser.automation

import com.kelpie.browser.ai.openai.OpenAIJson

/** Private provenance only; matching and structural projection stay in core-automation. */
class ScriptRedactor(
    private val native: (String) -> String? = { ScriptNative.redactOutputs(it) },
) {
    private val values = linkedSetOf<String>()

    @Synchronized
    fun add(value: String) {
        if (value.isNotEmpty()) values.add(value)
    }

    @Synchronized
    fun clear() {
        values.clear()
    }

    @Synchronized
    fun redact(
        outputs: Map<String, Any?>,
        extractionNames: List<String>,
    ): Map<String, Any?> {
        if (outputs.isEmpty()) return emptyMap()
        val request =
            OpenAIJson.encode(
                OpenAIJson.fromAny(
                    mapOf(
                        "outputs" to outputs,
                        "extractionNames" to extractionNames,
                        "secrets" to values.toList(),
                    ),
                ),
            )
        val response =
            native(request)?.let(OpenAIJson::parseObjectOrNull)?.let(OpenAIJson::toMap)
                ?: throw ScriptFailure("OUTPUT_REDACTION_FAILED")
        if (response["ok"] != true) throw ScriptFailure("OUTPUT_REDACTION_FAILED")
        @Suppress("UNCHECKED_CAST")
        return response["outputs"] as? Map<String, Any?> ?: throw ScriptFailure("OUTPUT_REDACTION_FAILED")
    }
}
