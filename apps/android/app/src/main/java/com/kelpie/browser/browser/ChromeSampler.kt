package com.kelpie.browser.browser

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import android.webkit.WebView

/** Bounded captures of the visible hardware surface; never reads page scripts. */
class ChromeSampler(private val window: Window) {
    private val handler = Handler(Looper.getMainLooper())
    private var generation = 0
    private var pending: Runnable? = null

    fun cancel() {
        generation++
        pending?.let(handler::removeCallbacks)
        pending = null
    }

    fun request(tab: BrowserTab) {
        cancel()
        val request = generation
        val url = tab.currentUrl
        val task = Runnable {
            pending = null
            capture(tab.webView, topOnly = true) { bitmap ->
                if (bitmap != null) {
                    if (request == generation && tab.currentUrl == url) {
                        val pixels = IntArray(bitmap.width * bitmap.height)
                        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
                        tab.chromeColor = ChromePalette.median(pixels)
                    }
                    bitmap.recycle()
                }
            }
        }
        pending = task
        handler.postDelayed(task, 150)
    }

    fun capture(view: WebView, topOnly: Boolean = false, result: (Bitmap?) -> Unit) {
        if (!view.isAttachedToWindow || view.width <= 0 || view.height <= 0) return result(null)
        val rect = Rect()
        if (!view.getGlobalVisibleRect(rect)) return result(null)
        // PixelCopy expects coordinates relative to the Window, not the screen.
        val location = IntArray(2)
        window.decorView.getLocationOnScreen(location)
        rect.offset(-location[0], -location[1])
        if (topOnly) rect.bottom = rect.top + minOf(12, rect.height())
        val width = if (topOnly) 64 else 240
        val height = if (topOnly) 4 else (width * rect.height() / rect.width()).coerceIn(1, 480)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(window, rect, bitmap, { status ->
                if (status == PixelCopy.SUCCESS) result(bitmap) else {
                    bitmap.recycle()
                    result(null)
                }
            }, handler)
        } catch (_: IllegalArgumentException) {
            bitmap.recycle()
            result(null)
        }
    }
}
