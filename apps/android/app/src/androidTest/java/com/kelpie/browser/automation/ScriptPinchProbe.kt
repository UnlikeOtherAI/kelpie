package com.kelpie.browser.automation

import android.app.Instrumentation
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import org.json.JSONObject
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Standard Android events delivered only to the exact app-owned renderer. */
internal class ScriptPinchProbe(
    private val instrumentation: Instrumentation,
    root: View,
) {
    val view: WebView

    init {
        var found: WebView? = null
        instrumentation.runOnMainSync {
            fun collect(node: View) {
                if (node is WebView && node.isShown && node.width > 0 && node.height > 0) {
                    check(found == null) { "Expected exactly one visible owned WebView" }
                    found = node
                }
                if (node is ViewGroup) for (index in 0 until node.childCount) collect(node.getChildAt(index))
            }
            collect(root)
        }
        view = checkNotNull(found)
    }

    fun metrics(): JSONObject {
        val latch = CountDownLatch(1)
        var result: JSONObject? = null
        instrumentation.runOnMainSync {
            check(view.isAttachedToWindow && view.isShown)
            view.evaluateJavascript(
                """JSON.stringify((()=>{const v=visualViewport,r=document.getElementById('target').getBoundingClientRect();
                return {scale:v.scale,offsetLeft:v.offsetLeft,offsetTop:v.offsetTop,width:v.width,height:v.height,
                innerWidth,innerHeight,rect:{left:r.left,top:r.top,right:r.right,bottom:r.bottom}}})())""",
            ) { encoded ->
                result = JSONObject(org.json.JSONTokener(encoded).nextValue() as String)
                latch.countDown()
            }
        }
        assertTrue("Fixture viewport callback did not retire", latch.await(10, TimeUnit.SECONDS))
        return checkNotNull(result)
    }

    fun settledMetrics(): JSONObject {
        var previous = metrics()
        var stableSince = SystemClock.uptimeMillis()
        val deadline = stableSince + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            SystemClock.sleep(25)
            val current = metrics()
            if (listOf("scale", "offsetLeft", "offsetTop", "width", "height").any {
                    kotlin.math.abs(current.getDouble(it) - previous.getDouble(it)) > 0.001
                }
            ) {
                stableSince = SystemClock.uptimeMillis()
            }
            previous = current
            if (SystemClock.uptimeMillis() - stableSince >= 200) return current
        }
        throw AssertionError("Native visual viewport did not settle")
    }

    fun settings(): JSONObject {
        lateinit var result: JSONObject
        instrumentation.runOnMainSync {
            result =
                JSONObject()
                    .put("builtInZoomControls", view.settings.builtInZoomControls)
                    .put("displayZoomControls", view.settings.displayZoomControls)
                    .put("supportZoom", view.settings.supportZoom())
        }
        return result
    }

    fun spread() {
        val down = SystemClock.uptimeMillis()
        val centerX = view.width * 0.5f
        val centerY = view.height * 0.5f

        fun send(
            action: Int,
            count: Int,
            fraction: Float,
        ) {
            val properties =
                Array(count) { id ->
                    MotionEvent.PointerProperties().apply {
                        this.id = id
                        toolType = MotionEvent.TOOL_TYPE_FINGER
                    }
                }
            val coords =
                Array(count) { id ->
                    MotionEvent.PointerCoords().apply {
                        x = centerX + (if (id == 0) -1 else 1) * view.width * fraction
                        y = centerY
                        pressure = 1f
                        size = 1f
                    }
                }
            val event =
                MotionEvent.obtain(
                    down,
                    SystemClock.uptimeMillis(),
                    action,
                    count,
                    properties,
                    coords,
                    0,
                    0,
                    1f,
                    1f,
                    0,
                    0,
                    InputDevice.SOURCE_TOUCHSCREEN,
                    0,
                )
            try {
                instrumentation.runOnMainSync {
                    check(view.isAttachedToWindow && view.isShown)
                    view.dispatchTouchEvent(event)
                }
            } finally {
                event.recycle()
            }
        }
        send(MotionEvent.ACTION_DOWN, 1, 0.12f)
        send(MotionEvent.ACTION_POINTER_DOWN or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, 0.12f)
        for (step in 1..24) {
            send(MotionEvent.ACTION_MOVE, 2, 0.12f + 0.12f * step / 24)
            SystemClock.sleep(16) // Physical gesture cadence, never a retry/recovery delay.
        }
        send(MotionEvent.ACTION_POINTER_UP or (1 shl MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, 0.24f)
        send(MotionEvent.ACTION_UP, 1, 0.24f)
    }
}
