package com.mollotov.browser.handlers

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse
import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

private val mainHandler = Handler(Looper.getMainLooper())

class ScreenshotHandler(private val ctx: HandlerContext) {
    fun register(router: Router) {
        router.register("screenshot") { screenshot(it) }
    }

    private suspend fun screenshot(body: Map<String, Any?>): Map<String, Any?> {
        val wv = ctx.webView ?: return errorResponse("NO_WEBVIEW", "No WebView")
        val format = body["format"] as? String ?: "png"
        val quality = (body["quality"] as? Int) ?: 80

        val bitmap = suspendCoroutine<Bitmap?> { cont ->
            mainHandler.post {
                try {
                    val bmp = Bitmap.createBitmap(wv.width, wv.height, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bmp)
                    wv.draw(canvas)
                    cont.resume(bmp)
                } catch (_: Exception) {
                    cont.resume(null)
                }
            }
        } ?: return errorResponse("SCREENSHOT_FAILED", "Failed to capture screenshot")

        val stream = ByteArrayOutputStream()
        val compressFormat = if (format == "jpeg") Bitmap.CompressFormat.JPEG else Bitmap.CompressFormat.PNG
        bitmap.compress(compressFormat, quality, stream)
        val base64 = Base64.getEncoder().encodeToString(stream.toByteArray())
        bitmap.recycle()

        return successResponse(mapOf(
            "image" to base64,
            "width" to wv.width,
            "height" to wv.height,
            "format" to format,
        ))
    }
}
