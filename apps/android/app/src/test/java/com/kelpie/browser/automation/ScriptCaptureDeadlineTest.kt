package com.kelpie.browser.automation

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptCaptureDeadlineTest {
    @Test
    fun snapshotDeadlineIsCaptureFailure() =
        runBlocking {
            var timedOut = false
            val error = runCatching { withCaptureDeadline(20, { timedOut = true }) { delay(10_000) } }.exceptionOrNull()
            assertTrue(timedOut)
            assertEquals("CAPTURE_FAILED", (error as ScriptFailure).code)
        }

    @Test
    fun parentCancellationIsNotSnapshotTimeout() =
        runBlocking {
            var timedOut = false
            var cancelled = false
            val started = CompletableDeferred<Unit>()
            val job =
                launch {
                    try {
                        withCaptureDeadline(10_000, { timedOut = true }) {
                            started.complete(Unit)
                            delay(10_000)
                        }
                    } catch (error: CancellationException) {
                        cancelled = true
                        throw error
                    }
                }
            started.await()
            job.cancelAndJoin()
            assertTrue(cancelled)
            assertFalse(timedOut)
        }

    @Test
    fun parentDeadlineRemainsParentCancellation() =
        runBlocking {
            var timedOut = false
            val error =
                runCatching {
                    withTimeout(20) { withCaptureDeadline(10_000, { timedOut = true }) { delay(10_000) } }
                }.exceptionOrNull()
            assertTrue(error is CancellationException)
            assertFalse(timedOut)
        }
}
