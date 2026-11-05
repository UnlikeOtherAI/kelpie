package com.kelpie.browser.automation

import org.junit.Assert.assertEquals
import org.junit.Test

class ScriptCaptureScheduleTest {
    @Test
    fun advancesAcrossOrdinaryOverrunAndExactBoundary() {
        val normal = ScriptCaptureSchedule.advance(previous = 100, now = 140, period = 50)
        assertEquals(150L, normal.next)
        assertEquals(0L, normal.missed)
        assertEquals(0L, normal.oldPolicyExcess)

        val boundary = ScriptCaptureSchedule.advance(previous = 100, now = 150, period = 50)
        assertEquals(200L, boundary.next)
        assertEquals(1L, boundary.missed)
        assertEquals(0L, boundary.oldPolicyExcess)

        val overrun = ScriptCaptureSchedule.advance(previous = 100, now = 273, period = 50)
        assertEquals(300L, overrun.next)
        assertEquals(3L, overrun.missed)
        assertEquals(23L, overrun.oldPolicyExcess)
    }
}
