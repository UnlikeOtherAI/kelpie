package com.kelpie.browser.automation

import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Input is dispatched only to this Activity's own window. */
class ScriptChromeInputFlowTest : ScriptPublicFixture() {
    @Test
    fun activeNoMovieRunBlocksChromeButNativeStopStillWorks() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                ui.onNodeWithContentDescription("More").performClick()
                assertTrue(ui.onAllNodesWithText("Settings").fetchSemanticsNodes().isNotEmpty())
                ui.runOnUiThread { ui.activity.onBackPressedDispatcher.onBackPressed() }
                ui.waitForIdle()
                assertTrue(ui.onAllNodesWithText("Settings").fetchSemanticsNodes().isEmpty())
                val moreBounds = ui.onNodeWithContentDescription("More").fetchSemanticsNode().boundsInWindow
                ui.onNodeWithTag("browser-address").performClick()
                ui.waitForIdle()
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val script = client.script(tab, client.action("wait").put("ms", 20_000))
                    val pending = executor.submit<JSONObject> { client.request("/v1/play-script", script).second }
                    awaitRecordingUi(pending)
                    assertTrue(client.call("get-script-status").optBoolean("playing"))
                    assertTrue(ui.onAllNodesWithContentDescription("More").fetchSemanticsNodes().isEmpty())
                    val decor = ui.activity.window.decorView
                    instrumentation.runOnMainSync {
                        check(decor.isAttachedToWindow)
                        val now = SystemClock.uptimeMillis()
                        val down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, moreBounds.center.x, moreBounds.center.y, 0)
                        val up = MotionEvent.obtain(now, now + 10, MotionEvent.ACTION_UP, moreBounds.center.x, moreBounds.center.y, 0)
                        try {
                            decor.dispatchTouchEvent(down)
                            decor.dispatchTouchEvent(up)
                            decor.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                            decor.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                        } finally {
                            down.recycle()
                            up.recycle()
                        }
                    }
                    ui.onNodeWithContentDescription("Stop recording").performClick()
                    val stopped = pending.get(30, TimeUnit.SECONDS)
                    assertEquals("aborted", stopped.getString("state"))
                    ui.waitForIdle()
                    assertTrue(ui.onAllNodesWithText("Settings").fetchSemanticsNodes().isEmpty())
                    assertEquals("Ready", client.core("tab.title", tab).optString("value"))
                    File(evidence, "native-chrome-input-result.json").writeText(
                        JSONObject()
                            .put("moreX", moreBounds.center.x.toDouble())
                            .put("moreY", moreBounds.center.y.toDouble())
                            .put("stopped", stopped)
                            .toString(2),
                    )
                    assertTrue(client.call("play-script", client.script(tab, client.action("wait").put("ms", 10))).getBoolean("success"))
                } finally {
                    executor.shutdownNow()
                }
            }
        }
    }
}
