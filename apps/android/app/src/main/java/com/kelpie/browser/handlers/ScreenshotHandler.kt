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
import kotlin.math.min
import kotlin.math.roundToInt

private val screenshotMainHandler = Handler(Looper.getMainLooper())

/**
 * Hard upper bound on the captured full-page height in device pixels. A tall
 * page (e.g. an infinite-scroll feed reporting 60000+ CSS pixels) would
 * otherwise allocate hundreds of MB in a single `Bitmap`, throwing
 * `OutOfMemoryError`. The page is captured up to this height and truncated past
 * it; the truncation is surfaced via the response metadata.
 */
private const val MAX_FULL_PAGE_PX = 16384

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

/** A full-page capture: the stitched bitmap plus the CSS height it spans. */
private class FullContentCapture(
    val bitmap: Bitmap,
    val contentHeightCss: Int,
    val truncated: Boolean,
)

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
     * The Android System WebView is not CDP-driven, so the document is captured
     * by scrolling viewport-by-viewport and compositing each tile into a single
     * target bitmap. This bounds peak memory to the target bitmap plus one
     * viewport draw, and — unlike a single oversized `WebView.draw` — guarantees
     * off-screen content is actually painted. Resolution scaling, encoding, and
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
        val capture = drawFullContent(wv) ?: return null
        val bitmap = capture.bitmap

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
            val baseMetadata =
                viewport.metadata(
                    imageWidth = rendered.width,
                    imageHeight = rendered.height,
                    format = normalizedFormat,
                    resolution = resolution,
                )
            // The full-page image spans the whole document, so the shared
            // viewport-based `imageScaleY` is meaningless. Rewrite it against the
            // full captured CSS content height so a consumer can map full-page
            // image pixels back to CSS coordinates.
            val imageScaleY =
                if (capture.contentHeightCss > 0) {
                    rendered.height.toDouble() / capture.contentHeightCss.toDouble()
                } else {
                    1.0
                }
            val fullPageMetadata =
                baseMetadata +
                    mapOf(
                        "contentHeight" to capture.contentHeightCss,
                        "imageScaleY" to imageScaleY,
                        "truncated" to capture.truncated,
                    )
            mapOf("image" to Base64.getEncoder().encodeToString(stream.toByteArray())) + fullPageMetadata
        } finally {
            if (rendered !== bitmap) {
                rendered.recycle()
            }
            bitmap.recycle()
        }
    }

    /**
     * Scrolls the WebView through the document one viewport at a time, drawing
     * each tile into a single target bitmap sized to the full content height
     * (capped at [MAX_FULL_PAGE_PX]). The original scroll position is restored.
     *
     * The bitmap allocation and per-tile draws are guarded against
     * [OutOfMemoryError]: an oversized page that slips past the cap (or a device
     * under heap pressure) frees any partial bitmap and resumes with `null`, so
     * the handler returns a clean `SCREENSHOT_FAILED` instead of crashing the app.
     */
    private suspend fun drawFullContent(wv: WebView): FullContentCapture? =
        suspendCoroutine { cont ->
            screenshotMainHandler.post {
                var bmp: Bitmap? = null
                val originalScrollY = wv.scrollY
                val originalScrollX = wv.scrollX
                try {
                    val density = wv.resources.displayMetrics.density
                    val width = max(wv.width, 1)
                    val viewportHeight = max(wv.height, 1)
                    val contentHeightPx = (wv.contentHeight * density).roundToInt()
                    val desiredHeight = max(contentHeightPx, viewportHeight).coerceAtLeast(1)
                    val cap = max(min(desiredHeight, heapBoundedCap(width)), viewportHeight)
                    val fullHeight = min(desiredHeight, cap)
                    val truncated = fullHeight < desiredHeight

                    bmp = Bitmap.createBitmap(width, fullHeight, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bmp)
                    stitchViewportTiles(wv, canvas, fullHeight, viewportHeight)

                    val contentHeightCss = max((fullHeight / density).roundToInt(), 1)
                    cont.resume(FullContentCapture(bmp, contentHeightCss, truncated))
                } catch (_: Throwable) {
                    // Catches OutOfMemoryError (an Error, not Exception) from the
                    // bitmap allocation or any per-tile draw, plus any runtime fault.
                    bmp?.recycle()
                    cont.resume(null)
                } finally {
                    wv.scrollTo(originalScrollX, originalScrollY)
                }
            }
        }

    /**
     * Draws the document into [canvas] one viewport-tall band at a time, scrolling
     * the WebView so each band paints its real (possibly off-screen) content.
     *
     * The final band is clamped to `maxScrollY` so it ends flush with the page
     * edge (`maxScrollY + viewportHeight == fullHeight`); its overlap with the
     * previous band repaints identical document content, so no clipping is needed.
     */
    private fun stitchViewportTiles(
        wv: WebView,
        canvas: Canvas,
        fullHeight: Int,
        viewportHeight: Int,
    ) {
        val maxScrollY = max(fullHeight - viewportHeight, 0)
        var top = 0
        while (top < fullHeight) {
            val scrollY = min(top, maxScrollY)
            wv.scrollTo(wv.scrollX, scrollY)
            val save = canvas.save()
            // Place this band so the WebView's painted viewport lands at `scrollY`.
            canvas.translate(0f, scrollY.toFloat())
            wv.draw(canvas)
            canvas.restoreToCount(save)
            if (scrollY >= maxScrollY) break
            top += viewportHeight
        }
    }

    /**
     * Upper bound on full-page height derived from available heap, so we never
     * attempt a target allocation that obviously will not fit. Reserves the
     * bitmap to at most a quarter of max heap (leaving room for the encode buffer
     * and a viewport draw), never exceeding [MAX_FULL_PAGE_PX].
     */
    private fun heapBoundedCap(width: Int): Int {
        val maxHeapBytes = Runtime.getRuntime().maxMemory()
        val budgetBytes = maxHeapBytes / 4
        val bytesPerRow = max(width, 1).toLong() * 4L
        val heapCap = (budgetBytes / bytesPerRow).toInt().coerceAtLeast(1)
        return min(heapCap, MAX_FULL_PAGE_PX)
    }
}
