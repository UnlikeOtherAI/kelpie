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
        val error = runCatching { requireScriptDispatchReceipt(mapOf("ok" to true), "expected") { protected = true } }.exceptionOrNull() as ScriptFailure
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

    @Test
    fun acknowledgementMustMatchTokenAndExplicitCompletionStatus() {
        val valid = mapOf("ok" to true, "token" to "expected", "mayHaveCompleted" to true, "inputGuarantee" to "synthetic-coordinate")
        requireScriptDispatchReceipt(valid, "expected") { throw AssertionError("valid receipt") }
        val invalid =
            listOf(
                valid - "token",
                valid + ("token" to "other"),
                valid - "mayHaveCompleted",
                valid + ("mayHaveCompleted" to "true"),
                valid + ("ok" to "true"),
            )
        for (receipt in invalid) {
            var protected = false
            val error = runCatching { requireScriptDispatchReceipt(receipt, "expected") { protected = true } }.exceptionOrNull() as ScriptFailure
            assertEquals("INPUT_UNCERTAIN", error.code)
            assertTrue(error.mayHaveCompleted)
            assertTrue(protected)
        }
    }

    @Test
    fun malformedCallbackCanBeProtectedBeforeLaterGuardFailure() {
        val malformed = mapOf("ok" to true, "token" to "other", "mayHaveCompleted" to true, "inputGuarantee" to "synthetic-coordinate")
        var protected = false
        val original = IllegalStateException("authority revoked")
        val caught =
            runCatching {
                protectMalformedScriptReceipt(malformed, "expected") { protected = true }
                throw original
            }.exceptionOrNull()
        assertTrue(protected)
        assertTrue(caught === original)
    }
}
