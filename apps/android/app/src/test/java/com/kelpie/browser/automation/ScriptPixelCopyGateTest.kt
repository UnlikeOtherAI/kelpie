package com.kelpie.browser.automation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScriptPixelCopyGateTest {
    @Test
    fun slotRefusesAnotherCopyUntilRetired() {
        assertTrue(ScriptPixelCopySlot.acquire())
        try {
            assertFalse(ScriptPixelCopySlot.acquire())
        } finally {
            ScriptPixelCopySlot.release()
        }
        assertTrue(ScriptPixelCopySlot.acquire())
        ScriptPixelCopySlot.release()
    }

    @Test
    fun timeoutQuarantinesUntilLateCallbackWithoutPublishing() {
        var recycled = 0
        var released = 0
        val gate = ScriptPixelCopyGate({ recycled++ }, { released++ })
        gate.abandon()
        assertEquals(0, recycled)
        assertEquals(0, released)
        assertFalse(gate.claim())
        gate.complete()
        assertEquals(1, recycled)
        assertEquals(1, released)
        assertFalse(gate.claim())
        gate.abandon()
        assertEquals(1, recycled)
        assertEquals(1, released)
    }

    @Test
    fun cancellationAfterCallbackRecyclesAndSuccessfulClaimTransfersOwnership() {
        var recycled = 0
        var released = 0
        val cancelled = ScriptPixelCopyGate({ recycled++ }, { released++ })
        cancelled.complete()
        cancelled.abandon()
        assertFalse(cancelled.claim())
        assertEquals(1, recycled)
        assertEquals(1, released)

        val successful = ScriptPixelCopyGate({ recycled++ }, { released++ })
        successful.complete()
        assertTrue(successful.claim())
        successful.abandon()
        assertEquals(1, recycled)
        assertEquals(2, released)
    }
}
