package com.kelpie.browser.handlers

/**
 * The native browser must not mistake an active tab ID for a drawable WebView.
 * This small, Android-independent policy is also exercised by JVM unit tests.
 */
internal data class WebViewCaptureEligibility(
    val attached: Boolean,
    val shown: Boolean,
    val windowVisible: Boolean,
    val width: Int,
    val height: Int,
    val visibleWidth: Int,
    val visibleHeight: Int,
) {
    fun canCapture(): Boolean =
        attached &&
            shown &&
            windowVisible &&
            width > 0 &&
            height > 0 &&
            visibleWidth == width &&
            visibleHeight == height
}
