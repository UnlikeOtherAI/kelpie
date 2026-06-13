package com.kelpie.browser.handlers

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlin.math.max
import kotlin.math.roundToInt

private val screenshotMainHandler = Handler(Looper.getMainLooper())

enum class ScreenshotResolution(
    val wireValue: String,
) {
    NATIVE("native"),
    VIEWPORT("viewport"),
    ;

    companion object {
        fun parse(raw: Any?): ScreenshotResolution? =
            when (raw) {
                null -> NATIVE
                is String -> entries.firstOrNull { it.wireValue == raw }
                else -> null
            }
    }
}

data class ScreenshotViewportMetrics(
    val viewportWidth: Int,
    val viewportHeight: Int,
    val devicePixelRatio: Double,
) {
    fun metadata(
        imageWidth: Int,
        imageHeight: Int,
        format: String,
        resolution: ScreenshotResolution,
    ): Map<String, Any> {
        val scaleX = if (viewportWidth > 0) imageWidth.toDouble() / viewportWidth.toDouble() else 1.0
        val scaleY = if (viewportHeight > 0) imageHeight.toDouble() / viewportHeight.toDouble() else 1.0
        return mapOf(
            "width" to imageWidth,
            "height" to imageHeight,
            "format" to format,
            "resolution" to resolution.wireValue,
            "coordinateSpace" to "viewport-css-pixels",
            "viewportWidth" to viewportWidth,
            "viewportHeight" to viewportHeight,
            "devicePixelRatio" to devicePixelRatio,
            "imageScaleX" to scaleX,
            "imageScaleY" to scaleY,
        )
    }
}

class ScreenshotHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("screenshot") { screenshot(it) }
    }

    private suspend fun screenshot(body: Map<String, Any?>): Map<String, Any?> {
        val fullPage = body["fullPage"] as? Boolean ?: false
        val format = body["format"] as? String ?: "png"
        val quality = (body["quality"] as? Int) ?: 80
        val resolution =
            ScreenshotResolution.parse(body["resolution"])
                ?: return errorResponse("INVALID_PARAMS", "resolution must be 'native' or 'viewport'")

        val payload =
            if (fullPage) {
                captureFullPagePayload(format, quality, resolution)
            } else {
                ctx.captureScreenshotPayload(format, quality, resolution)
            } ?: return errorResponse("SCREENSHOT_FAILED", "Failed to capture screenshot")
        return successResponse(payload)
    }

    /**
     * Captures the full scrollable document, not just the viewport.
     *
     * The Android System WebView is not CDP-driven, so we use the WebView-native
     * approach: size a Bitmap to the full content height and let `WebView.draw`
     * paint the entire document into it in a single pass. This avoids the seams
     * a scroll-and-stitch path would introduce. Resolution scaling, encoding, and
     * the response metadata block mirror the viewport path in
     * [HandlerContext.captureScreenshotPayload].
     */
    private suspend fun captureFullPagePayload(
        format: String,
        quality: Int,
        resolution: ScreenshotResolution,
    ): Map<String, Any?>? {
        val wv = ctx.webView ?: return null
        val normalizedFormat = if (format == "jpeg") "jpeg" else "png"
        val viewport = ctx.viewportMetrics()
        val bitmap = drawFullContent(wv) ?: return null

        val rendered =
            if (resolution == ScreenshotResolution.VIEWPORT) {
                val targetWidth = max((bitmap.width / max(viewport.devicePixelRatio, 1.0)).roundToInt(), 1)
                val targetHeight = max((bitmap.height / max(viewport.devicePixelRatio, 1.0)).roundToInt(), 1)
                if (targetWidth == bitmap.width && targetHeight == bitmap.height) {
                    bitmap
                } else {
                    Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
                }
            } else {
                bitmap
            }

        return try {
            val stream = ByteArrayOutputStream()
            val compressFormat =
                if (normalizedFormat == "jpeg") {
                    Bitmap.CompressFormat.JPEG
                } else {
                    Bitmap.CompressFormat.PNG
                }
            rendered.compress(compressFormat, quality, stream)
            mapOf("image" to Base64.getEncoder().encodeToString(stream.toByteArray())) +
                viewport.metadata(
                    imageWidth = rendered.width,
                    imageHeight = rendered.height,
                    format = normalizedFormat,
                    resolution = resolution,
                )
        } finally {
            if (rendered !== bitmap) {
                rendered.recycle()
            }
            bitmap.recycle()
        }
    }

    /**
     * Draws the entire WebView document into a Bitmap sized to the full content
     * height. `WebView.contentHeight` is reported in CSS pixels, so it is scaled
     * by the display density to get device pixels. The viewport height is the
     * lower bound so a page shorter than the viewport still produces a valid frame.
     */
    private suspend fun drawFullContent(wv: WebView): Bitmap? =
        suspendCoroutine { cont ->
            screenshotMainHandler.post {
                try {
                    val density = wv.resources.displayMetrics.density
                    val width = max(wv.width, 1)
                    val contentHeight = (wv.contentHeight * density).roundToInt()
                    val fullHeight = max(contentHeight, wv.height).coerceAtLeast(1)
                    val bmp = Bitmap.createBitmap(width, fullHeight, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bmp)
                    wv.draw(canvas)
                    cont.resume(bmp)
                } catch (_: Exception) {
                    cont.resume(null)
                }
            }
        }
}
