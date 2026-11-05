package com.kelpie.browser.automation

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptTargetClassificationTest {
    @Test
    fun preEvaluationRefusalDoesNotMakeTheLiteralSensitive() {
        assertFalse(ScriptTargetClassification().unknown())
    }

    @Test
    fun startedEvaluationWithoutMetadataRequiresConservativeProtection() {
        val state = ScriptTargetClassification()
        state.started()
        state.received(null)
        assertTrue(state.unknown())
    }

    @Test
    fun explicitFalseSurvivesLaterGuardFailureOrCancellation() {
        val state = ScriptTargetClassification()
        state.started()
        state.received(false)
        assertFalse(state.unknown())
    }

    @Test
    fun clickResolutionAndNonDispatchRecheckCannotCertifyMissingClassification() {
        for (stage in listOf("initial click resolution", "intermediate click recheck")) {
            val state = ScriptTargetClassification()
            state.started()
            state.received(null)
            assertTrue(stage, state.unknown())
            state.received(false)
            assertFalse(stage, state.unknown())
        }
    }
    @Test
    fun explicitTrueIsClassifiedRatherThanMissingMetadata() {
        val state = ScriptTargetClassification()
        state.started()
        state.received(true)
        assertFalse(state.unknown())
    }
}
