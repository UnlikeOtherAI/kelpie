package com.kelpie.browser.automation

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptDispatchDeadlineTest {
    @Test
    fun startedMutationWithoutAcknowledgementRefusesAndProtectsLiteral() =
        runBlocking {
            val classification = ScriptTargetClassification()
            var protected = false
            val failure =
                runCatching {
                    withScriptDispatchDeadline(20, true, classification, { protected = true }) {
                        classification.started()
                        delay(10_000)
                    }
                }.exceptionOrNull() as ScriptFailure
            assertEquals("INPUT_UNCERTAIN", failure.code)
            assertTrue(failure.mayHaveCompleted)
            assertTrue(protected)
        }

    @Test
    fun cancellationDoesNotBecomeTimeoutFailure() =
        runBlocking {
            val classification = ScriptTargetClassification()
            val started = CompletableDeferred<Unit>()
            var protected = false
            val job =
                launch {
                    withScriptDispatchDeadline(10_000, true, classification, { protected = true }) {
                        classification.started()
                        started.complete(Unit)
                        delay(10_000)
                    }
                }
            started.await()
            job.cancelAndJoin()
            assertTrue(job.isCancelled)
            assertTrue(protected)
        }

    @Test
    fun malformedSuccessIsNotAValidAcknowledgement() {
        var protected = false
        val error = runCatching { requireScriptDispatchReceipt(mapOf("ok" to true)) { protected = true } }.exceptionOrNull() as ScriptFailure
        assertEquals("INPUT_UNCERTAIN", error.code)
        assertTrue(error.mayHaveCompleted)
        assertTrue(protected)
    }

    @Test
    fun explicitlyKnownNonSensitiveReceiptDoesNotActivateProtection() =
        runBlocking {
            val classification = ScriptTargetClassification()
            var protected = false
            classification.started()
            classification.received(false, true)
            val value = withScriptDispatchDeadline(1000, true, classification, { protected = true }) { "acknowledged" }
            assertEquals("acknowledged", value)
            assertFalse(protected)
        }
}
