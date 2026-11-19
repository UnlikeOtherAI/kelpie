package com.kelpie.browser.handlers

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrollJavaScriptTest {
    @Test
    fun positiveScrollDeltaIsOneExecutableExpression() {
        val script = ScrollJavaScript.byDelta(0.0, 880.0)
        assertTrue(script.startsWith("(function(){"))
        assertTrue(script.endsWith("})()"))
        assertTrue(script.contains("window.scrollBy(0.0,880.0)"))
        assertTrue(script.contains("return{scrollX:window.scrollX,scrollY:window.scrollY}"))
        assertFalse(script.contains("); ({"))
    }

    @Test
    fun horizontalAndNegativeScrollPreserveSignedValues() {
        val script = ScrollJavaScript.byDelta(-25.0, -120.0)
        assertTrue(script.contains("window.scrollBy(-25.0,-120.0)"))
    }

    @Test
    fun scrollToTopReturnsActualScrollState() {
        val script = ScrollJavaScript.edge(true)
        assertTrue(script.contains("window.scrollTo(0,0)"))
        assertTrue(script.contains("scrollY:window.scrollY"))
        assertFalse(script.contains("scrollY:0}"))
    }

    @Test
    fun scrollToBottomReturnsActualScrollState() {
        val script = ScrollJavaScript.edge(false)
        assertTrue(script.contains("window.scrollTo(0,document.documentElement.scrollHeight)"))
        assertTrue(script.endsWith("})()"))
    }
}
