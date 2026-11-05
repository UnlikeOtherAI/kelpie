package com.kelpie.browser.automation

import com.kelpie.browser.handlers.WebViewGuardRejected
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptNavigationGuardTest {
    @Test
    fun rejectedCallbackRechecksExplicitStopWithoutRetry() =
        runBlocking {
            var attempts = 0
            var guards = 0
            val error =
                runCatching {
                    recheckNavigationGuard<Unit>(
                        stopRequested = { true },
                        guard = {
                            guards++
                            throw ScriptFailure("SCRIPT_ABORTED", true)
                        },
                        operation = {
                            attempts++
                            throw WebViewGuardRejected()
                        },
                    )
                }.exceptionOrNull() as ScriptFailure
            assertEquals(1, attempts)
            assertEquals(1, guards)
            assertEquals("SCRIPT_ABORTED", error.code)
            assertTrue(error.mayHaveCompleted)
        }

    @Test
    fun rejectedCallbackPreservesRevocationAndUnrelatedFailureIsNotRechecked() =
        runBlocking {
            val revoked =
                runCatching {
                    recheckNavigationGuard<Unit>(
                        stopRequested = { true },
                        guard = { throw ScriptFailure("SCRIPT_AUTHORIZATION_REVOKED", true) },
                        operation = { throw WebViewGuardRejected() },
                    )
                }.exceptionOrNull() as ScriptFailure
            assertEquals("SCRIPT_AUTHORIZATION_REVOKED", revoked.code)
            val rejected = WebViewGuardRejected()
            var unstoppedGuards = 0
            val unstopped =
                runCatching {
                    recheckNavigationGuard<Unit>(
                        stopRequested = { false },
                        guard = { unstoppedGuards++ },
                        operation = { throw rejected },
                    )
                }.exceptionOrNull()
            assertSame(rejected, unstopped)
            assertEquals(0, unstoppedGuards)
            val original = IllegalStateException("unrelated")
            var guards = 0
            val actual =
                runCatching {
                    recheckNavigationGuard<Unit>(
                        stopRequested = { true },
                        guard = { guards++ },
                        operation = { throw original },
                    )
                }.exceptionOrNull()
            assertSame(original, actual)
            assertEquals(0, guards)
        }
}
