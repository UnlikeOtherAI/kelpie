package com.kelpie.browser.automation

import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
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
                val moreBounds = ui.onNodeWithContentDescription("More").fetchSemanticsNode().boundsInWindow
                val decor = ui.activity.window.decorView

                fun tapMore() {
                    instrumentation.runOnMainSync {
                        check(decor.isAttachedToWindow)
                        val now = SystemClock.uptimeMillis()
                        val down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, moreBounds.center.x, moreBounds.center.y, 0)
                        val up = MotionEvent.obtain(now, now + 10, MotionEvent.ACTION_UP, moreBounds.center.x, moreBounds.center.y, 0)
                        try {
                            decor.dispatchTouchEvent(down)
                            decor.dispatchTouchEvent(up)
                        } finally {
                            down.recycle()
                            up.recycle()
                        }
                    }
                }

                fun enter() {
                    instrumentation.runOnMainSync {
                        decor.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER))
                        decor.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))
                    }
                }

                fun facts(): JSONObject =
                    client
                        .call(
                            "evaluate",
                            JSONObject().put("expression", "({href:location.href, keys:window.__ownedKeyCount || 0})"),
                        ).getJSONObject("result")

                tapMore()
                ui.waitForIdle()
                assertTrue("Owned touch did not open the baseline menu", ui.onAllNodesWithText("Settings").fetchSemanticsNodes().isNotEmpty())
                ui.runOnUiThread { ui.activity.onBackPressedDispatcher.onBackPressed() }
                ui.waitForIdle()
                assertTrue(ui.onAllNodesWithText("Settings").fetchSemanticsNodes().isEmpty())
                val initialUrl = facts().getString("href")
                client.call(
                    "evaluate",
                    JSONObject().put(
                        "expression",
                        "(()=>{window.__ownedKeyCount=0;document.addEventListener('keydown',e=>{if(e.key==='Enter')window.__ownedKeyCount++});return true})()",
                    ),
                )
                val view = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
                instrumentation.runOnMainSync { check(view.requestFocus()) }
                enter()
                val keyDeadline = System.nanoTime() + 3_000_000_000L
                while (facts().getInt("keys") == 0 && System.nanoTime() < keyDeadline) Thread.sleep(20)
                assertEquals("Owned Enter did not reach the baseline page", 1, facts().getInt("keys"))
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val script = client.script(tab, client.action("wait").put("ms", 20_000))
                    val pending = executor.submit<JSONObject> { client.request("/v1/play-script", script).second }
                    awaitRecordingUi(pending)
                    assertTrue(client.call("get-script-status").optBoolean("playing"))
                    assertTrue(ui.onAllNodesWithContentDescription("More").fetchSemanticsNodes().isEmpty())
                    tapMore()
                    enter()
                    Thread.sleep(150)
                    ui.onNodeWithContentDescription("Stop recording").performClick()
                    val stopped = pending.get(30, TimeUnit.SECONDS)
                    assertEquals("aborted", stopped.getString("state"))
                    ui.waitForIdle()
                    assertTrue(ui.onAllNodesWithText("Settings").fetchSemanticsNodes().isEmpty())
                    val after = facts()
                    assertEquals(initialUrl, after.getString("href"))
                    assertEquals("Active script delivered Enter to the page", 1, after.getInt("keys"))
                    File(evidence, "native-chrome-input-result.json").writeText(
                        JSONObject()
                            .put("moreX", moreBounds.center.x.toDouble())
                            .put("moreY", moreBounds.center.y.toDouble())
                            .put("sameUrl", initialUrl == after.getString("href"))
                            .put("keyCount", after.getInt("keys"))
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
