package com.kelpie.browser.automation

import com.kelpie.browser.ai.openai.OpenAIJson
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ScriptRedactorAdapterTest {
    @Test
    fun sendsPrivateProvenanceToAuthoritativeNativeProjector() {
        val requests = mutableListOf<Map<String, Any?>>()
        val redactor =
            ScriptRedactor { encoded ->
                requests += OpenAIJson.toMap(checkNotNull(OpenAIJson.parseObjectOrNull(encoded)))
                """{"ok":true,"outputs":{"nested":{"safe":"[REDACTED]"}}}"""
            }
        redactor.add("Aa b+!")
        redactor.add("Aa b+!")
        val output = redactor.redact(mapOf("nested" to mapOf("Aa%20b%2b!" to "private")), listOf("nested"))
        assertEquals(mapOf("safe" to "[REDACTED]"), output["nested"])
        assertEquals(listOf("Aa b+!"), requests.single()["secrets"])
        assertEquals(listOf("nested"), requests.single()["extractionNames"])
        assertEquals(mapOf("nested" to mapOf("Aa%20b%2b!" to "private")), requests.single()["outputs"])
        redactor.clear()
        redactor.redact(mapOf("url" to "https://example.test"), emptyList())
        assertEquals(emptyList<String>(), requests.last()["secrets"])
        assertEquals(emptyList<String>(), requests.last()["extractionNames"])
    }

    @Test
    fun nativeFailureNeverReturnsRawOutputs() {
        for (response in listOf(null, "", "{}", """{"ok":false,"error":{"code":"REDACTION_LIMIT"}}""", """{"ok":true,"outputs":"bad"}""")) {
            var refused = false
            try {
                ScriptRedactor { response }.redact(mapOf("secret" to "private"), emptyList())
            } catch (error: ScriptFailure) {
                refused = true
                assertEquals("SCRIPT_OUTPUT_REDACTION_FAILED", error.code)
                assertFalse(error.message.orEmpty().contains("private"))
            }
            assertEquals(true, refused)
        }
        var invoked = false
        val redactor =
            ScriptRedactor {
                invoked = true
                null
            }
        assertEquals(emptyMap<String, Any?>(), redactor.redact(emptyMap(), emptyList()))
        assertFalse(invoked)
    }
}
