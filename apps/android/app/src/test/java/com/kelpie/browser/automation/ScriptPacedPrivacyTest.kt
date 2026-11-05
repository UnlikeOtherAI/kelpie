package com.kelpie.browser.automation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptPacedPrivacyTest {
    @Test
    fun acknowledgedFinalNavigationProtectsLiteralWithoutInventingInputFailure() {
        var protected = false
        checkPacedPostMutation(mapOf("ok" to true, "sensitivityKnown" to false), true, false) { protected = true }
        assertTrue(protected)
    }

    @Test
    fun unknownBeforeAnotherScalarOrDuringCaptureRefuses() {
        for ((finalStep, captures) in listOf(false to false, true to true)) {
            var protected = false
            val error =
                runCatching {
                    checkPacedPostMutation(mapOf("ok" to true, "sensitivityKnown" to false), finalStep, captures) { protected = true }
                }.exceptionOrNull() as ScriptFailure
            assertTrue(protected)
            assertEquals("INPUT_UNCERTAIN", error.code)
            assertTrue(error.mayHaveCompleted)
        }
    }
}
