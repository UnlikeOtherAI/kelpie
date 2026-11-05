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
    fun matches(): Boolean {
        val currentRenderer = ViewFrame.capture(renderer)
        val currentOverlay = ViewFrame.capture(overlay)
        val reason =
            when {
                currentRenderer == null -> "RENDERER_UNAVAILABLE"
                currentOverlay == null -> "OVERLAY_UNAVAILABLE"
                !currentRenderer.sameAs(rendererFrame) -> "RENDERER_CHANGED"
                !currentOverlay.sameAs(overlayFrame) -> "OVERLAY_CHANGED"
                renderer.scrollX != scrollX || renderer.scrollY != scrollY -> "SCROLL_CHANGED"
                renderer.scale != scale -> "SCALE_CHANGED"
                else -> null
            }
        if (reason != null) {
            scriptMarkerTrace("frame", reason)
            if (reason == "RENDERER_CHANGED") currentRenderer?.difference(rendererFrame)?.let { scriptMarkerTrace("renderer", it) }
            if (reason == "OVERLAY_CHANGED") currentOverlay?.difference(overlayFrame)?.let { scriptMarkerTrace("overlay", it) }
        }
        return reason == null
    }
    companion object {
        @Suppress("DEPRECATION")
        fun capture(
            renderer: WebView,
            overlay: View,
        ): ScriptOverlayFrame? {
            val rendererFrame = ViewFrame.capture(renderer) ?: run { scriptMarkerTrace("bind", "RENDERER_UNAVAILABLE"); return null }
            val overlayFrame = ViewFrame.capture(overlay) ?: run { scriptMarkerTrace("bind", "OVERLAY_UNAVAILABLE"); return null }
            if (!rendererFrame.sameAs(overlayFrame)) {
                scriptMarkerTrace("bind", "FRAME_PAIR_DIFFERENT")
                rendererFrame.difference(overlayFrame)?.let { scriptMarkerTrace("pair", it) }
                return null
            }
            val scale = renderer.scale
            if (!scale.isFinite() || scale <= 0f) { scriptMarkerTrace("bind", "SCALE_INVALID"); return null }
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
    fun sameAs(other: ViewFrame): Boolean = difference(other) == null

    fun difference(other: ViewFrame): String? =
        when {
            root !== other.root -> "ROOT_IDENTITY"
            token !== other.token -> "WINDOW_IDENTITY"
            width != other.width || height != other.height -> "SIZE"
            screenX != other.screenX || screenY != other.screenY -> "ORIGIN"
            !matrix.contentEquals(other.matrix) -> "TRANSFORM"
            else -> null
        }
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
