package com.kelpie.browser.automation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptPacedPrivacyTest {
    @Test
    fun acknowledgedFinalNavigationProtectsLiteralWithoutInventingInputFailure() {
        var protected = false
        checkPacedPostMutation(mapOf("ok" to true, "sensitive" to false, "sensitivityKnown" to false), true, false) { protected = true }
        assertTrue(protected)
    }

    @Test
    fun unknownBeforeAnotherScalarOrDuringCaptureRefuses() {
        for ((finalStep, captures) in listOf(false to false, true to true)) {
            var protected = false
            val error =
                runCatching {
                    checkPacedPostMutation(mapOf("ok" to true, "sensitive" to false, "sensitivityKnown" to false), finalStep, captures) { protected = true }
                }.exceptionOrNull() as ScriptFailure
            assertTrue(protected)
            assertEquals("INPUT_UNCERTAIN", error.code)
            assertTrue(error.mayHaveCompleted)
        }
    }

    @Test
    fun malformedSensitivityNeverAuthorizesAnotherScalar() {
        for (result in listOf(mapOf("ok" to true, "sensitivityKnown" to true), mapOf("ok" to true, "sensitivityKnown" to true, "sensitive" to "false"))) {
            for ((finalStep, captures) in listOf(false to false, true to true)) {
                var protected = false
                val error = runCatching { checkPacedPostMutation(result, finalStep, captures) { protected = true } }.exceptionOrNull() as ScriptFailure
                assertTrue(protected)
                assertEquals("INPUT_UNCERTAIN", error.code)
                assertTrue(error.mayHaveCompleted)
            }
            var protected = false
            val finalError = runCatching { checkPacedPostMutation(result, true, false) { protected = true } }.exceptionOrNull() as ScriptFailure
            assertTrue(protected)
            assertEquals("INPUT_UNCERTAIN", finalError.code)
        }
    }

    @Test
    fun explicitSensitiveTrueIsKnownEvenWithoutKnownFlag() {
        checkPacedPostMutation(mapOf("ok" to true, "sensitive" to true, "sensitivityKnown" to false), false, false) {
            throw AssertionError("known positive must not be treated as unknown")
        }
        val error =
            runCatching {
                checkPacedPostMutation(mapOf("ok" to true, "sensitive" to true, "sensitivityKnown" to false), false, true) {}
            }.exceptionOrNull() as ScriptFailure
        assertEquals("SENSITIVE_CAPTURE_REFUSED", error.code)
    }

    @Test
    fun postMutationSuccessWithErrorIsMalformed() {
        var protected = false
        val error =
            runCatching {
                checkPacedPostMutation(mapOf("ok" to true, "error" to "CONTRADICTION", "sensitive" to false, "sensitivityKnown" to false), true, false) { protected = true }
            }.exceptionOrNull() as ScriptFailure
        assertTrue(protected)
        assertEquals("INPUT_UNCERTAIN", error.code)
    }

    @Test
    fun postMutationFailureCannotBeSwallowedAtFinalScalar() {
        for (status in listOf(false, "true")) {
            var protected = false
            val error =
                runCatching {
                    checkPacedPostMutation(mapOf("ok" to status, "sensitive" to false, "sensitivityKnown" to false), true, false) { protected = true }
                }.exceptionOrNull() as ScriptFailure
            assertTrue(protected)
            assertEquals("INPUT_UNCERTAIN", error.code)
        }
    }
}
