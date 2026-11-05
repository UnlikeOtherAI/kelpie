package com.kelpie.browser.automation

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import android.webkit.WebView
import androidx.annotation.RequiresApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Copies the committed recording scene from the owned window, never a software
 * WebView draw. Callers fence authority, document and layout around this work.
 */
internal class ScriptCompositorCapture(
    private val view: WebView,
    private val scene: () -> Long,
) {
    private val handler = Handler(Looper.getMainLooper())

    private fun window(): Window {
        var context: Context = view.context
        while (context is ContextWrapper && context !is Activity) {
            val next = context.baseContext
            if (next === context) break
            context = next
        }
        return (context as? Activity)?.window ?: throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
    }

    /** Reject partial visibility, another focused window and an uncertified UI. */
    fun rectangle(): Rect {
        if (scene() < 0 ||
            !view.isAttachedToWindow ||
            !view.isShown ||
            !view.hasWindowFocus() ||
            !view.isHardwareAccelerated ||
            view.width <= 0 ||
            view.height <= 0
        ) {
            throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
        }
        val location = IntArray(2)
        view.getLocationInWindow(location)
        val expected = Rect(location[0], location[1], location[0] + view.width, location[1] + view.height)
        val visible = Rect()
        if (!view.getGlobalVisibleRect(visible) || visible != expected) throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
        val window = window()
        if (expected.left < 0 ||
            expected.top < 0 ||
            expected.right > window.decorView.width ||
            expected.bottom > window.decorView.height
        ) {
            throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
        }
        return expected
    }

    /**
     * WebView's visual callback alone precedes the next draw. The frame commit
     * callback fences that draw before PixelCopy reads the most recent buffer.
     */
    suspend fun awaitCommittedFrame() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) throw ScriptFailure("CAPTURE_VIEW_UNAVAILABLE")
        awaitCommittedFrameOnQ()
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private suspend fun awaitCommittedFrameOnQ() {
        suspendCancellableCoroutine<Unit> { continuation ->
            view.postVisualStateCallback(
                0,
                object : WebView.VisualStateCallback() {
                    override fun onComplete(requestId: Long) {
                        if (!continuation.isActive) return
                        if (!view.isAttachedToWindow) {
                            continuation.resumeWithException(ScriptFailure("CAPTURE_VIEW_UNAVAILABLE"))
                            return
                        }
                        view.viewTreeObserver.registerFrameCommitCallback {
                            if (continuation.isActive) continuation.resume(Unit)
                        }
                        view.invalidate()
                    }
                },
            )
        }
    }

    suspend fun copy(
        rect: Rect,
        width: Int,
        height: Int,
    ): Bitmap {
        if (!ScriptPixelCopySlot.acquire()) throw ScriptFailure("CAPTURE_FAILED")
        val bitmap =
            try {
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            } catch (error: Throwable) {
                ScriptPixelCopySlot.release()
                throw error
            }
        val gate = ScriptPixelCopyGate(bitmap::recycle, ScriptPixelCopySlot::release)
        val completed = CompletableDeferred<Int>()
        try {
            PixelCopy.request(
                window(),
                rect,
                bitmap,
                { status ->
                    // Retire only after this native callback has returned.
                    handler.post {
                        gate.complete()
                        completed.complete(status)
                    }
                },
                handler,
            )
        } catch (error: Throwable) {
            // A synchronous refusal does not transfer the bitmap to PixelCopy.
            gate.complete()
            gate.abandon()
            if (error !is Exception) throw error
            throw ScriptFailure("CAPTURE_FAILED")
        }
        try {
            if (completed.await() != PixelCopy.SUCCESS || !gate.claim()) throw ScriptFailure("CAPTURE_FAILED")
            return bitmap
        } catch (error: Throwable) {
            // The bitmap remains private and occupied until any late callback.
            gate.abandon()
            throw error
        }
    }
}
