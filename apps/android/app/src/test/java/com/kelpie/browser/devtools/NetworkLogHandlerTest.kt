package com.kelpie.browser.devtools

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Deterministic unit tests for [NetworkLogHandler]'s pure status/`since` parsing.
 * These call the companion helpers directly — no `HandlerContext`, network, or IO,
 * so they run on the plain JVM via `testDebugUnitTest`.
 */
class NetworkLogHandlerTest {
    // region parseStatusCategory

    @Test
    fun parseStatusCategoryAcceptsKnownValues() {
        assertEquals("success", NetworkLogHandler.parseStatusCategory("success"))
        assertEquals("error", NetworkLogHandler.parseStatusCategory("error"))
        assertEquals("pending", NetworkLogHandler.parseStatusCategory("pending"))
    }

    @Test
    fun parseStatusCategoryNormalizesCaseAndWhitespace() {
        assertEquals("success", NetworkLogHandler.parseStatusCategory("  Success  "))
    }

    @Test
    fun parseStatusCategoryRejectsUnknownAndNonString() {
        assertNull(NetworkLogHandler.parseStatusCategory("redirect"))
        assertNull(NetworkLogHandler.parseStatusCategory(null))
        assertNull(NetworkLogHandler.parseStatusCategory(200))
    }

    // endregion

    // region matchesStatusCategory

    @Test
    fun successCategoryCovers2xxAnd3xx() {
        assertTrue(NetworkLogHandler.matchesStatusCategory(200, "success"))
        assertTrue(NetworkLogHandler.matchesStatusCategory(204, "success"))
        assertTrue(NetworkLogHandler.matchesStatusCategory(301, "success"))
        assertTrue(NetworkLogHandler.matchesStatusCategory(399, "success"))
    }

    @Test
    fun successCategoryExcludesErrorsAndPending() {
        assertFalse(NetworkLogHandler.matchesStatusCategory(404, "success"))
        assertFalse(NetworkLogHandler.matchesStatusCategory(null, "success"))
        assertFalse(NetworkLogHandler.matchesStatusCategory(0, "success"))
    }

    @Test
    fun errorCategoryCovers4xxAndAbove() {
        assertTrue(NetworkLogHandler.matchesStatusCategory(400, "error"))
        assertTrue(NetworkLogHandler.matchesStatusCategory(500, "error"))
        assertFalse(NetworkLogHandler.matchesStatusCategory(399, "error"))
        assertFalse(NetworkLogHandler.matchesStatusCategory(null, "error"))
    }

    @Test
    fun pendingCategoryMatchesMissingOrZero() {
        assertTrue(NetworkLogHandler.matchesStatusCategory(null, "pending"))
        assertTrue(NetworkLogHandler.matchesStatusCategory(0, "pending"))
        assertFalse(NetworkLogHandler.matchesStatusCategory(200, "pending"))
    }

    @Test
    fun unknownCategoryNeverMatches() {
        assertFalse(NetworkLogHandler.matchesStatusCategory(200, "bogus"))
    }

    // endregion

    // region parseSinceMillis

    @Test
    fun parseSinceFromNumber() {
        assertEquals(1_700_000_000_000L, NetworkLogHandler.parseSinceMillis(1_700_000_000_000L))
        assertEquals(1_700_000_000_000L, NetworkLogHandler.parseSinceMillis(1_700_000_000_000.0))
    }

    @Test
    fun parseSinceFromNumericString() {
        assertEquals(1_700_000_000_000L, NetworkLogHandler.parseSinceMillis(" 1700000000000 "))
    }

    @Test
    fun parseSinceFromIso8601() {
        // 2021-01-01T00:00:00Z == 1609459200000 ms since epoch.
        assertEquals(1_609_459_200_000L, NetworkLogHandler.parseSinceMillis("2021-01-01T00:00:00Z"))
    }

    @Test
    fun parseSinceFromIso8601WithFractionalSeconds() {
        assertEquals(1_609_459_200_500L, NetworkLogHandler.parseSinceMillis("2021-01-01T00:00:00.500Z"))
    }

    @Test
    fun parseSinceReturnsNullForGarbageAndNull() {
        assertNull(NetworkLogHandler.parseSinceMillis(null))
        assertNull(NetworkLogHandler.parseSinceMillis("not-a-date"))
    }

    // endregion

    // region parseIso8601Millis

    @Test
    fun parseIso8601MillisHandlesValidAndInvalid() {
        assertEquals(1_609_459_200_000L, NetworkLogHandler.parseIso8601Millis("2021-01-01T00:00:00Z"))
        assertNull(NetworkLogHandler.parseIso8601Millis("garbage"))
    }

    // endregion
}
