package com.kelpie.browser.automation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ScriptPreflightTest {
    private fun script(vararg actions: Map<String, Any?>) = mapOf<String, Any?>("version" to 1, "tabId" to "tab", "actions" to actions.toList())

    private fun refuses(
        code: String,
        value: Map<String, Any?>,
    ) {
        var dispatched = false
        try {
            ScriptPreflight.admit(value)
            dispatched = true
        } catch (failure: ScriptFailure) {
            assertEquals(code, failure.code)
        }
        assertFalse("Admission dispatched a workflow with an unsupported capability", dispatched)
    }

    @Test
    fun noSessionIsValidButUnknownAndForeignSessionsRefuseBeforeEarlierAction() {
        val workflow = script(mapOf("action" to "click", "target" to mapOf("selector" to "#button")))
        assertEquals(workflow, ScriptPreflight.admit(workflow))
        for (id in listOf("unknown", "other-owner-session")) {
            refuses("SESSION_UNSUPPORTED", workflow + ("sessionId" to id))
        }
    }

    @Test
    fun keyboardDefaultsAndUnresolvedBindingsRefuseInFullPreflight() {
        refuses(
            "UNSUPPORTED_SCRIPT_ACTION",
            script(
                mapOf("action" to "navigate", "url" to "https://example.test"),
                mapOf("action" to "press-key", "key" to "Enter"),
            ),
        )
        refuses(
            "UNRESOLVED_SCRIPT_INPUT",
            script(
                mapOf("action" to "fill", "target" to mapOf("selector" to "input"), "text" to mapOf("secret" to "configured")),
            ),
        )
        refuses("UNRESOLVED_SCRIPT_INPUT", script(mapOf("action" to "wait", "ms" to 1)) + ("inputs" to emptyMap<String, Any>()))
    }

    @Test
    fun sensitiveCaptureAndDuplicateOutputsRefuseBeforeMutation() {
        val secret = mapOf("action" to "fill", "target" to mapOf("selector" to "input"), "text" to "private", "sensitive" to true)
        refuses("SENSITIVE_CAPTURE", script(secret) + ("capture" to mapOf("formats" to listOf("gif"))))
        refuses("SENSITIVE_CAPTURE", script(secret, mapOf("action" to "screenshot")))
        refuses(
            "DUPLICATE_SCRIPT_OUTPUT",
            script(
                mapOf("action" to "output", "name" to "same", "source" to "url"),
                mapOf("action" to "output", "name" to "same", "source" to "title"),
            ),
        )
    }
}
