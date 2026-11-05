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
            "UNRESOLVED_INPUT",
            script(
                mapOf("action" to "fill", "target" to mapOf("selector" to "input"), "text" to mapOf("secret" to "configured")),
            ),
        )
        val emptyDeclarations = script(mapOf("action" to "wait", "ms" to 1)) + ("inputs" to emptyMap<String, Any>())
        assertEquals(emptyDeclarations, ScriptPreflight.admit(emptyDeclarations))
        refuses("UNRESOLVED_INPUT", script(mapOf("action" to "wait", "ms" to 1)) + ("inputs" to mapOf("name" to mapOf("type" to "string"))))
    }

    @Test
    fun everyPacedEditIsPlannedBeforeAdmissionAndInvalidPlansRefuse() {
        val actions =
            listOf(
                mapOf("action" to "wait", "ms" to 1),
                mapOf("action" to "fill", "target" to mapOf("selector" to "input"), "text" to "a\uD83C\uDF0A", "typingDelayMs" to 50),
                mapOf("action" to "type", "target" to mapOf("selector" to "input"), "text" to "b", "typingDelayMs" to 20),
            )
        val requests = mutableListOf<Map<String, Any?>>()
        val accepted =
            ScriptPreflight.admit(script(*actions.toTypedArray())) { request ->
                requests.add(request)
                mapOf(
                    "valid" to true,
                    "clearFirst" to (request["action"] == "fill"),
                    "typingDelayMs" to request["typingDelayMs"],
                    "scalars" to if (request["action"] == "fill") listOf("a", "\uD83C\uDF0A") else listOf("b"),
                )
            }
        assertEquals(2, requests.size)
        assertEquals(setOf("action", "text", "typingDelayMs"), requests.first().keys)
        val plans = ScriptPreflight.actions(accepted).drop(1).map { it["__pacedPlan"] as ScriptPacedPlan }
        assertEquals(listOf("a", "\uD83C\uDF0A"), plans.first().scalars)
        assertEquals(true, plans.first().clearFirst)
        assertEquals(false, plans.last().clearFirst)
        var dispatched = false
        try {
            ScriptPreflight.admit(script(*actions.toTypedArray())) { mapOf("valid" to false) }
            dispatched = true
        } catch (failure: ScriptFailure) {
            assertEquals("INVALID_PACED_TYPING", failure.code)
        }
        assertFalse("An invalid paced plan must refuse before any action", dispatched)
    }

    @Test
    fun sensitiveCaptureAndDuplicateOutputsRefuseBeforeMutation() {
        val secret = mapOf("action" to "fill", "target" to mapOf("selector" to "input"), "text" to "private", "sensitive" to true)
        refuses("SENSITIVE_CAPTURE_REFUSED", script(secret) + ("capture" to mapOf("formats" to listOf("gif"))))
        refuses("SENSITIVE_CAPTURE_REFUSED", script(secret, mapOf("action" to "screenshot")))
        refuses(
            "DUPLICATE_OUTPUT",
            script(
                mapOf("action" to "output", "name" to "same", "source" to "url"),
                mapOf("action" to "output", "name" to "same", "source" to "title"),
            ),
        )
    }
}
