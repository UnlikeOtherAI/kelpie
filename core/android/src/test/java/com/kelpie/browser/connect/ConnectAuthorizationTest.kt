package com.kelpie.browser.connect

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class ConnectAuthorizationTest {
    @Test
    fun cancelledAndReplacementJobsCannotBorrowAuthority() {
        val command = mapOf("jobId" to "job", "attemptId" to "first", "deadline" to "2030-01-01T00:00:00.123Z")
        val authority = requireNotNull(ConnectAuthorization.from(command))
        val now = Instant.parse("2029-01-01T00:00:00Z")
        assertTrue(authority.matches(command, now))
        assertFalse(authority.matches(null, now))
        assertFalse(authority.matches(mapOf("jobId" to "job", "attemptId" to "replacement"), now))
        assertFalse(authority.matches(mapOf("jobId" to "other", "attemptId" to "first"), now))
        assertFalse(authority.matches(command, authority.deadline))
        assertNull(ConnectAuthorization.from(command + ("deadline" to "invalid")))
    }
}
