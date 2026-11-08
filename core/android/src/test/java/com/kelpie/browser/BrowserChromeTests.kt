package com.kelpie.browser

import com.kelpie.browser.browser.ChromePalette
import com.kelpie.browser.browser.ChromeScrollPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BrowserChromeTests {
    @Test fun slowFingerMovementAccumulates() {
        val policy = ChromeScrollPolicy()
        assertNull(policy.update(-8f, 50f, 200f, true))
        assertNull(policy.update(-16f, 60f, 200f, true))
        assertEquals(true, policy.update(-20f, 70f, 200f, true))
        assertNull(policy.update(-10f, 60f, 200f, true))
        assertEquals(false, policy.update(0f, 50f, 200f, true))
    }

    @Test fun automationAndOverscrollDoNotChangeChrome() {
        val policy = ChromeScrollPolicy()
        assertNull(policy.update(-100f, 100f, 200f, false))
        assertNull(policy.update(-110f, 110f, 200f, true))
        assertNull(policy.update(-200f, 201f, 200f, true))
        assertNull(policy.update(-210f, 200f, 200f, true))
        assertNull(policy.update(-500f, 5f, 20f, true))
    }

    @Test fun medianIgnoresBrightTextAndTransparency() {
        val navy = 0xff102030.toInt()
        assertEquals(navy, ChromePalette.median(intArrayOf(navy, navy, navy, -1, 0)))
        assertEquals(-1, ChromePalette.median(intArrayOf(0)))
        assertEquals(-1, ChromePalette.foreground(navy))
        assertEquals(ChromePalette.INK, ChromePalette.foreground(-1))
    }
}
