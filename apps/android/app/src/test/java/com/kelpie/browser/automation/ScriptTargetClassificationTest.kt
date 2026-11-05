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
        state.received(null, null)
        assertTrue(state.unknown())
    }

    @Test
    fun explicitFalseSurvivesLaterGuardFailureOrCancellation() {
        val state = ScriptTargetClassification()
        state.started()
        state.received(false, true)
        assertFalse(state.unknown())
    }

    @Test
    fun clickResolutionAndNonDispatchRecheckCannotCertifyMissingClassification() {
        for (stage in listOf("initial click resolution", "intermediate click recheck")) {
            val state = ScriptTargetClassification()
            state.started()
            state.received(null, null)
            assertTrue(stage, state.unknown())
            state.received(false, true)
            assertFalse(stage, state.unknown())
        }
    }

    @Test
    fun falseWithoutKnownProvenanceCannotCertifyMissingTokenOrLegacyResult() {
        for (known in listOf(null, false)) {
            val state = ScriptTargetClassification()
            state.started()
            state.received(false, known)
            assertTrue(state.unknown())
        }
    }

    @Test
    fun explicitTrueIsClassifiedRatherThanMissingMetadata() {
        val state = ScriptTargetClassification()
        state.started()
        state.received(true, null)
        assertFalse(state.unknown())
    }
}
