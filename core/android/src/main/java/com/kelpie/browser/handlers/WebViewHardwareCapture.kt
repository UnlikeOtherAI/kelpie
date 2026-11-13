package com.kelpie.browser.handlers

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Choreographer
import android.view.PixelCopy
import android.view.View
import android.webkit.WebView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * Capture visible WebView pixels from the hardware-composited Activity window.
 * No hidden/zero-size WebView is silently rendered into an empty Bitmap.
 *
 * A background tab without a drawable surface intentionally has no screenshot.
 * Supporting true unattended rendering needs a separately designed render surface.
 */
internal object WebViewHardwareCapture {
    private const val VISUAL_TIMEOUT_MS = 2500L
    private const val COPY_TIMEOUT_MS = 3500L
    private val callbackHandler = Handler(Looper.getMainLooper())

    suspend fun capture(webView: WebView): Bitmap? =
        withContext(Dispatchers.Main.immediate) {
            val activity = findActivity(webView.context) ?: return@withContext null
            if (captureRect(webView) == null) return@withContext null
            val visuallyReady =
                withTimeoutOrNull(VISUAL_TIMEOUT_MS) {
                    suspendCancellableCoroutine<Boolean> { continuation ->
                        webView.postVisualStateCallback(
                            SystemClock.uptimeMillis(),
                            object : WebView.VisualStateCallback() {
                                override fun onComplete(requestId: Long) {
                                    if (continuation.isActive) continuation.resume(true)
                                }
                            },
                        )
                    }
                } ?: false
            if (!visuallyReady) return@withContext null

            // The visual-state callback guarantees a *future* draw, not a completed
            // window buffer. Request one animation frame before copying the window.
            val frameReady =
                withTimeoutOrNull(VISUAL_TIMEOUT_MS) {
                    suspendCancellableCoroutine<Boolean> { continuation ->
                        webView.postInvalidateOnAnimation()
                        Choreographer.getInstance().postFrameCallback {
                            if (continuation.isActive) continuation.resume(true)
                        }
                    }
                } ?: false
            if (!frameReady) return@withContext null

            val rect = captureRect(webView) ?: return@withContext null
            val bitmap =
                try {
                    Bitmap.createBitmap(rect.width(), rect.height(), Bitmap.Config.ARGB_8888)
                } catch (_: IllegalArgumentException) {
                    return@withContext null
                } catch (_: OutOfMemoryError) {
                    return@withContext null
                }
            // Both the callback and the continuation run on the main looper.
            // Keep the bitmap alive if a timeout races a still-pending PixelCopy;
            // in that case its late callback is responsible for releasing it.
            var requestSubmitted = false
            var callbackCompleted = false
            val copyResult =
                withTimeoutOrNull(COPY_TIMEOUT_MS) {
                    suspendCancellableCoroutine<Boolean> { continuation ->
                        try {
                            requestSubmitted = true
                            PixelCopy.request(
                                activity.window,
                                rect,
                                bitmap,
                                { code ->
                                    callbackCompleted = true
                                    if (continuation.isActive) {
                                        continuation.resume(code == PixelCopy.SUCCESS)
                                    } else if (!bitmap.isRecycled) {
                                        bitmap.recycle()
                                    }
                                },
                                callbackHandler,
                            )
                        } catch (_: IllegalArgumentException) {
                            requestSubmitted = false
                            if (continuation.isActive) continuation.resume(false)
                        } catch (_: IllegalStateException) {
                            requestSubmitted = false
                            if (continuation.isActive) continuation.resume(false)
                        }
                    }
                } ?: false
            if (!copyResult) {
                if ((!requestSubmitted || callbackCompleted) && !bitmap.isRecycled) {
                    bitmap.recycle()
                }
                // If a submitted request is still pending, its late callback
                // recycles the bitmap rather than racing a native copy.
                return@withContext null
            }
            bitmap
        }

    private fun captureRect(webView: WebView): Rect? {
        val visible = Rect()
        if (!webView.getGlobalVisibleRect(visible)) return null
        val eligibility =
            WebViewCaptureEligibility(
                attached = webView.isAttachedToWindow && webView.windowToken != null,
                shown = webView.isShown,
                windowVisible = webView.windowVisibility == View.VISIBLE,
                width = webView.width,
                height = webView.height,
                visibleWidth = visible.width(),
                visibleHeight = visible.height(),
            )
        if (!eligibility.canCapture()) return null
        val position = IntArray(2)
        webView.getLocationInWindow(position)
        return Rect(
            position[0],
            position[1],
            position[0] + webView.width,
            position[1] + webView.height,
        )
    }

    private fun findActivity(context: Context): Activity? {
        var current: Context = context
        repeat(16) {
            when (val candidate = current) {
                is Activity -> return candidate
                is ContextWrapper -> {
                    val parent = candidate.baseContext
                    if (parent === candidate) return null
                    current = parent
                }
                else -> return null
            }
        }
        return null
    }
}
