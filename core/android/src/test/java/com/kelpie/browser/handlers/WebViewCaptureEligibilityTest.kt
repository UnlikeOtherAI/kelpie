package com.kelpie.browser.handlers

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WebViewCaptureEligibilityTest {
    private val visible =
        WebViewCaptureEligibility(
            attached = true,
            shown = true,
            windowVisible = true,
            width = 384,
            height = 720,
            visibleWidth = 384,
            visibleHeight = 720,
        )

    @Test
    fun fullyVisibleRendererIsEligible() = assertTrue(visible.canCapture())

    @Test
    fun detachedRendererIsNotEligible() = assertFalse(visible.copy(attached = false).canCapture())

    @Test
    fun hiddenRendererIsNotEligible() = assertFalse(visible.copy(shown = false).canCapture())

    @Test
    fun hiddenWindowIsNotEligible() = assertFalse(visible.copy(windowVisible = false).canCapture())

    @Test
    fun zeroWidthIsNotEligible() = assertFalse(visible.copy(width = 0).canCapture())

    @Test
    fun zeroHeightIsNotEligible() = assertFalse(visible.copy(height = 0).canCapture())

    @Test
    fun clippedRendererIsNotEligible() = assertFalse(visible.copy(visibleHeight = 400).canCapture())

    @Test
    fun clippedHorizontallyIsNotEligible() = assertFalse(visible.copy(visibleWidth = 300).canCapture())

    @Test
    fun oversizedVisibleRectIsNotEligible() = assertFalse(visible.copy(visibleWidth = 400).canCapture())

    @Test
    fun negativeDimensionIsNotEligible() = assertFalse(visible.copy(width = -1).canCapture())
}
