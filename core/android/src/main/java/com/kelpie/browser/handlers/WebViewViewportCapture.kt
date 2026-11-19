package com.kelpie.browser.handlers

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorSpace
import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.RenderNode
import android.hardware.HardwareBuffer
import android.media.ImageReader
import android.os.Build
import android.view.View
import android.webkit.WebView
import androidx.annotation.RequiresApi
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.math.roundToInt

private const val VISUAL_STATE_TIMEOUT_MS = 2500L

internal suspend fun <T> captureWebViewViewport(
    webView: WebView,
    consume: suspend (Bitmap) -> T,
): T? =
    withContext(Dispatchers.Main.immediate) {
        if (!webView.canCapture()) return@withContext null
        try {
            val ready = withTimeoutOrNull(VISUAL_STATE_TIMEOUT_MS) { webView.awaitVisualState() }
            if (ready == null || !webView.canCapture()) return@withContext null
            val bitmap = drawViewport(webView) ?: return@withContext null
            try {
                consume(bitmap)
            } finally {
                bitmap.recycle()
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: RuntimeException) {
            null
        } catch (_: OutOfMemoryError) {
            null
        }
    }

private fun WebView.canCapture(): Boolean = isAttachedToWindow && isShown && windowVisibility == View.VISIBLE && width > 0 && height > 0

private suspend fun WebView.awaitVisualState() {
    suspendCancellableCoroutine<Unit> { continuation ->
        postVisualStateCallback(
            0,
            object : WebView.VisualStateCallback() {
                override fun onComplete(requestId: Long) {
                    if (continuation.isActive) continuation.resume(Unit)
                }
            },
        )
    }
}

private fun drawViewport(webView: WebView): Bitmap? {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && webView.isHardwareAccelerated) {
        return drawHardwareViewport(webView)
    }
    val bitmap = Bitmap.createBitmap(webView.width, webView.height, Bitmap.Config.ARGB_8888)
    try {
        webView.draw(Canvas(bitmap))
        return bitmap
    } catch (failure: Throwable) {
        bitmap.recycle()
        throw failure
    }
}

@RequiresApi(Build.VERSION_CODES.Q)
private fun drawHardwareViewport(webView: WebView): Bitmap? {
    val width = webView.width
    val height = webView.height
    val node = RenderNode("Kelpie WebView viewport")
    node.setPosition(0, 0, width, height)
    try {
        val canvas = node.beginRecording()
        try {
            // Record the WebView alone. Activity-window pixels can include UI owned by the host.
            webView.draw(canvas)
        } finally {
            node.endRecording()
        }

        return ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2, HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE).use { reader ->
            val renderer = HardwareRenderer()
            try {
                renderer.setSurface(reader.surface)
                renderer.setContentRoot(node)
                renderer.createRenderRequest().setWaitForPresent(true).syncAndDraw()
                // A fresh reader can only return a frame from this capture.
                reader.acquireLatestImage()?.use { frame ->
                    frame.hardwareBuffer?.use { buffer ->
                        val hardware = Bitmap.wrapHardwareBuffer(buffer, ColorSpace.get(ColorSpace.Named.SRGB))
                        try {
                            hardware?.copy(Bitmap.Config.ARGB_8888, false)
                        } finally {
                            hardware?.recycle()
                        }
                    }
                }
            } finally {
                renderer.destroy()
            }
        }
    } finally {
        node.discardDisplayList()
    }
}

internal suspend fun encodeViewportScreenshot(
    bitmap: Bitmap,
    viewport: ScreenshotViewportMetrics,
    format: String,
    quality: Int,
    resolution: ScreenshotResolution,
): Map<String, Any?>? =
    withContext(Dispatchers.Default) {
        val jpeg = format == "jpeg"
        val compressFormat = if (jpeg) Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG
        val divisor = if (resolution == ScreenshotResolution.VIEWPORT) viewport.devicePixelRatio.coerceAtLeast(1.0) else 1.0
        val width = (bitmap.width / divisor).roundToInt().coerceAtLeast(1)
        val height = (bitmap.height / divisor).roundToInt().coerceAtLeast(1)
        val rendered =
            if (width == bitmap.width && height == bitmap.height) {
                bitmap
            } else {
                Bitmap.createScaledBitmap(bitmap, width, height, true)
            }
        try {
            val stream = ByteArrayOutputStream()
            if (!rendered.compress(compressFormat, quality, stream)) return@withContext null
            mapOf("image" to Base64.getEncoder().encodeToString(stream.toByteArray())) +
                viewport.metadata(width, height, if (jpeg) "jpeg" else "png", resolution)
        } finally {
            if (rendered !== bitmap) rendered.recycle()
        }
    }
