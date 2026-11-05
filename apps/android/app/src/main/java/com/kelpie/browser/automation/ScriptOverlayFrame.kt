package com.kelpie.browser.automation

import android.graphics.Matrix
import android.os.IBinder
import android.view.View
import android.webkit.WebView

/** Native renderer and presentation pinned at marker admission, on the main thread. */
internal class ScriptOverlayFrame private constructor(
    private val renderer: WebView,
    private val overlay: View,
    private val rendererFrame: ViewFrame,
    private val overlayFrame: ViewFrame,
    private val scrollX: Int,
    private val scrollY: Int,
    private val scale: Float,
) {
    @Suppress("DEPRECATION")
    fun matches(): Boolean =
        ViewFrame.capture(renderer)?.sameAs(rendererFrame) == true &&
            ViewFrame.capture(overlay)?.sameAs(overlayFrame) == true &&
            renderer.scrollX == scrollX &&
            renderer.scrollY == scrollY &&
            renderer.scale == scale

    companion object {
        @Suppress("DEPRECATION")
        fun capture(
            renderer: WebView,
            overlay: View,
        ): ScriptOverlayFrame? {
            val rendererFrame = ViewFrame.capture(renderer) ?: return null
            val overlayFrame = ViewFrame.capture(overlay) ?: return null
            if (!rendererFrame.sameAs(overlayFrame)) return null
            val scale = renderer.scale
            if (!scale.isFinite() || scale <= 0f) return null
            return ScriptOverlayFrame(
                renderer,
                overlay,
                rendererFrame,
                overlayFrame,
                renderer.scrollX,
                renderer.scrollY,
                scale,
            )
        }
    }
}

private class ViewFrame(
    val root: View,
    val token: IBinder,
    val width: Int,
    val height: Int,
    val screenX: Int,
    val screenY: Int,
    val matrix: FloatArray,
) {
    fun sameAs(other: ViewFrame): Boolean =
        root === other.root &&
            token === other.token &&
            width == other.width &&
            height == other.height &&
            screenX == other.screenX &&
            screenY == other.screenY &&
            matrix.contentEquals(other.matrix)

    companion object {
        fun capture(view: View): ViewFrame? {
            if (!view.isAttachedToWindow || !view.isShown || view.width <= 0 || view.height <= 0) return null
            val token = view.windowToken ?: return null
            val location = IntArray(2)
            view.getLocationOnScreen(location)
            val transform = Matrix()
            view.transformMatrixToGlobal(transform)
            if (!transform.isAffine) return null
            val values = FloatArray(9)
            transform.getValues(values)
            if (values.any { !it.isFinite() }) return null
            return ViewFrame(view.rootView, token, view.width, view.height, location[0], location[1], values)
        }
    }
}
