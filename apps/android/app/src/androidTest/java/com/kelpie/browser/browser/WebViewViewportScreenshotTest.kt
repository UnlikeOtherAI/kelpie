package com.kelpie.browser.browser

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.webkit.WebView
import android.widget.FrameLayout
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import com.kelpie.browser.MainActivity
import com.kelpie.browser.handlers.HandlerContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Base64

@RunWith(AndroidJUnit4::class)
class WebViewViewportScreenshotTest {
    @Test
    @SdkSuppress(minSdkVersion = 29)
    fun capturesCurrentWebGlFrameWithoutHostOverlay() =
        runBlocking {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                val ctx = HandlerContext()
                scenario.onActivity { activity ->
                    val container = FrameLayout(activity)
                    val webView = WebView(activity)
                    webView.settings.javaScriptEnabled = true
                    container.addView(webView, FrameLayout.LayoutParams(-1, -1))
                    val overlay = View(activity)
                    overlay.setBackgroundColor(Color.MAGENTA)
                    container.addView(overlay, FrameLayout.LayoutParams(100, 100, Gravity.CENTER))
                    activity.setContentView(container)
                    ctx.webView = webView
                    webView.loadDataWithBaseURL("https://fixture.invalid/", FIXTURE, "text/html", "UTF-8", null)
                }

                awaitFrame(ctx, 0)
                assertCenter(ctx, Color.GREEN)
                ctx.evaluateJS("window.variant = 1")
                awaitFrame(ctx, 1)
                assertCenter(ctx, Color.RED)
                scenario.onActivity { ctx.webView?.visibility = View.INVISIBLE }
                assertNull(ctx.captureScreenshotPayload())
                scenario.onActivity { ctx.webView?.visibility = View.VISIBLE }
                assertCenter(ctx, Color.RED)
            }
        }

    private suspend fun awaitFrame(
        ctx: HandlerContext,
        frame: Int,
    ) = withTimeout(10_000) {
        while (ctx.evaluateJS("window.drawn === $frame") != "true") delay(50)
    }

    private suspend fun assertCenter(
        ctx: HandlerContext,
        expected: Int,
    ) {
        val encoded = checkNotNull(ctx.captureScreenshotPayload()?.get("image") as? String)
        val bytes = Base64.getDecoder().decode(encoded)
        val bitmap: Bitmap = checkNotNull(BitmapFactory.decodeByteArray(bytes, 0, bytes.size))
        try {
            assertEquals(expected, bitmap.getPixel(bitmap.width / 2, bitmap.height / 2))
        } finally {
            bitmap.recycle()
        }
    }

    private companion object {
        val FIXTURE =
            """
            <!doctype html><meta name="viewport" content="width=device-width">
            <body style="margin:0;background:blue">
            <canvas width="100" height="100" style="width:100vw;height:100vh"></canvas>
            <script>
              const gl = document.querySelector('canvas').getContext('webgl');
              window.variant = 0;
              function draw() {
                if (gl) {
                  gl.clearColor(window.variant, 1 - window.variant, 0, 1);
                  gl.clear(gl.COLOR_BUFFER_BIT);
                  window.drawn = window.variant;
                }
                requestAnimationFrame(draw);
              }
              draw();
            </script>
            """.trimIndent()
    }
}
