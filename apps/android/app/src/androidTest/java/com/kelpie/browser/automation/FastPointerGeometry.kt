package com.kelpie.browser.automation

import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.RectF
import android.webkit.WebView
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor

/** Test-only receipt binding the owned WebView to its G08 visual viewport. */
internal object FastPointerGeometry {
    fun capture(view: WebView): JSONObject {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val value = AtomicReference<String>()
        val done = CountDownLatch(1)
        var nativeRect: Rect? = null
        instrumentation.runOnMainSync {
            check(view.isAttachedToWindow && view.isShown && view.width > 0 && view.height > 0)
            val matrix = Matrix()
            view.transformMatrixToGlobal(matrix)
            val values = FloatArray(9)
            matrix.getValues(values)
            val sx = values[Matrix.MSCALE_X]
            val sy = values[Matrix.MSCALE_Y]
            check(matrix.isAffine && sx > 0f && sy > 0f && abs(sx / sy - 1f) < 0.02f)
            check(abs(values[Matrix.MSKEW_X]) < 0.0001f && abs(values[Matrix.MSKEW_Y]) < 0.0001f)
            val origin = floatArrayOf(0f, 0f)
            matrix.mapPoints(origin)
            val rect = RectF(0f, 0f, view.width.toFloat(), view.height.toFloat())
            matrix.mapRect(rect)
            val screen = IntArray(2)
            view.getLocationOnScreen(screen)
            rect.offset(screen[0] - origin[0], screen[1] - origin[1])
            val bounds =
                Rect(
                    floor(rect.left.toDouble()).toInt(),
                    floor(rect.top.toDouble()).toInt(),
                    ceil(rect.right.toDouble()).toInt(),
                    ceil(rect.bottom.toDouble()).toInt(),
                )
            val visible = Rect()
            check(view.getGlobalVisibleRect(visible))
            val root = IntArray(2)
            view.rootView.getLocationOnScreen(root)
            visible.offset(root[0], root[1])
            check(visible.contains(bounds))
            nativeRect = bounds
            view.evaluateJavascript(
                """(()=>{const v=visualViewport;return v?{width:v.width,height:v.height,
                offsetLeft:v.offsetLeft,offsetTop:v.offsetTop,href:location.href}:null})()""",
            ) {
                value.set(it)
                done.countDown()
            }
        }
        check(done.await(3, TimeUnit.SECONDS))
        val viewport = JSONObject(checkNotNull(value.get()))
        check(viewport.getString("href").contains("/g08"))
        val rect = checkNotNull(nativeRect)
        val scaleX = rect.width() / viewport.getDouble("width")
        val scaleY = rect.height() / viewport.getDouble("height")
        check(scaleX > 0 && scaleY > 0 && abs(scaleX / scaleY - 1.0) < 0.02)
        return JSONObject()
            .put("left", rect.left)
            .put("top", rect.top)
            .put("right", rect.right)
            .put("bottom", rect.bottom)
            .put("viewport", viewport)
    }
}
