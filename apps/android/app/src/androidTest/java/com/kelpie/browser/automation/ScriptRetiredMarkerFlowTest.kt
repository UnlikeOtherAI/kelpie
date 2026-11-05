package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.Rect
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** A real navigation clears the first marker before the final no-movie tap. */
class ScriptRetiredMarkerFlowTest : ScriptPublicFixture() {
    @Test
    fun navigationThenFinalTapRetainsOnlyItsNativeMarker() = runScenario(false)

    @Test
    fun pngTapRetiresAndNextRunClearsIt() = runScenario(true)

    @Test
    fun nativeStopKeepsTheNormalViewportAndRecovers() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val view = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view

                fun frame(): JSONObject {
                    val result = JSONObject()
                    instrumentation.runOnMainSync {
                        val point = IntArray(2)
                        view.getLocationOnScreen(point)
                        result.put("x", point[0]).put("y", point[1]).put("width", view.width).put("height", view.height)
                    }
                    return result
                }

                val before = frame()
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val script = client.script(tab, client.action("wait").put("ms", 20_000))
                    val pending = executor.submit<JSONObject> { client.request("/v1/play-script", script).second }
                    awaitRecordingUi(pending)
                    assertTrue(client.call("get-script-status").optBoolean("playing"))
                    val during = frame()
                    assertEquals(before.toString(), during.toString())
                    val screen = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
                    File(evidence, "retired-marker-native-stop.png").outputStream().use { screen.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    screen.recycle()
                    ui.onNodeWithContentDescription("Stop recording").performClick()
                    val stopped = pending.get(30, TimeUnit.SECONDS)
                    assertEquals("aborted", stopped.getString("state"))
                    ui.waitForIdle()
                    val after = frame()
                    assertEquals(before.toString(), after.toString())
                    File(evidence, "retired-marker-stop-frame.json").writeText(
                        JSONObject().put("before", before).put("during", during).put("after", after).put("result", stopped).toString(2),
                    )
                    assertTrue(client.call("play-script", client.script(tab, client.action("wait").put("ms", 10))).getBoolean("success"))
                } finally {
                    executor.shutdownNow()
                }
            }
        }
    }
    private fun runScenario(png: Boolean) {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server, navigation = true)
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html").setBody(
                        """<!doctype html><meta name="viewport" content="width=device-width"><title>Destination</title>
                        <style>body{margin:0;background:white}button{position:absolute;left:100px;top:140px;width:120px;height:60px}</style>
                        <button id="destination" onclick="document.title='Final click'">Submit</button>""",
                    ),
                )
                val script =
                    client
                        .script(
                            tab,
                            client.action("click").put("target", client.target("Submit")),
                            client.action("wait-ready").put("state", "complete").put("selector", "#destination"),
                            client.action("click").put("target", client.target("Submit")),
                        ).put("pointer", JSONObject().put("enabled", false))
                        .put("tapIndicator", JSONObject().put("color", "#3B82F6").put("durationMs", 5000).put("fade", false))
                val executor = Executors.newSingleThreadExecutor()
                if (png) script.put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                val playStartedNs = System.nanoTime()
                val result =
                    try {
                        val pending = executor.submit<JSONObject> { client.call("play-script", script) }
                        val deadline = System.nanoTime() + 60_000_000_000L
                        while (!pending.isDone && System.nanoTime() < deadline) {
                            ui.mainClock.advanceTimeByFrame()
                            Thread.sleep(20)
                        }
                        pending.get(1, TimeUnit.SECONDS)
                    } finally {
                        executor.shutdownNow()
                    }
                File(evidence, "retired-marker-play-result.json").writeText(result.toString(2))
                assertTrue(result.toString(), result.getBoolean("success"))
                assertEquals("completed", result.getString("state"))
                assertFalse(client.call("get-script-status").optBoolean("playing"))
                val geometry = readSubmitGeometry(client, "/next")
                val screen = captureBlueMarker(client, geometry)

                File(evidence, "native-retired-navigation-marker.png").outputStream().use {
                    screen.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                screen.recycle()
                if (png) {
                    assertTrue(result.getJSONArray("artifacts").length() > 0)
                    val markerEvidence = JSONObject(File(evidence, "native-marker-evidence.json").readText())
                    val bounds = markerEvidence.getJSONObject("target")
                    val target = Rect(bounds.getInt("left"), bounds.getInt("top"), bounds.getInt("right"), bounds.getInt("bottom"))
                    val nextExecutor = Executors.newSingleThreadExecutor()
                    try {
                        val next = client.script(tab, client.action("wait").put("ms", 1800))
                        val pending = nextExecutor.submit<JSONObject> { client.call("play-script", next) }
                        val deadline = System.nanoTime() + 3_000_000_000L
                        var playing = false
                        while (!playing && !pending.isDone && System.nanoTime() < deadline) {
                            ui.mainClock.advanceTimeByFrame()
                            playing = client.call("get-script-status").optBoolean("playing")
                        }
                        assertTrue("Next run was not admitted before marker expiry", playing)
                        val owned = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
                        val expectedViewport = markerEvidence.getJSONObject("webView")
                        val currentViewport = Rect()
                        instrumentation.runOnMainSync {
                            check(owned.getGlobalVisibleRect(currentViewport))
                            val origin = IntArray(2)
                            owned.rootView.getLocationOnScreen(origin)
                            currentViewport.offset(origin[0], origin[1])
                        }
                        assertEquals(expectedViewport.getInt("left"), currentViewport.left)
                        assertEquals(expectedViewport.getInt("top"), currentViewport.top)
                        assertEquals(expectedViewport.getInt("right"), currentViewport.right)
                        assertEquals(expectedViewport.getInt("bottom"), currentViewport.bottom)
                        val nextScreen = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
                        try {
                            assertTrue("Next-run check cannot exclude natural marker expiry", System.nanoTime() - playStartedNs < 4_500_000_000L)
                            assertEquals(null, ScriptMarkerPixels.locate(nextScreen, target))
                        } finally {
                            nextScreen.recycle()
                        }
                        assertTrue(pending.get(10, TimeUnit.SECONDS).getBoolean("success"))
                    } finally {
                        nextExecutor.shutdownNow()
                    }
                }
                assertTrue(ui.onAllNodesWithContentDescription("Stop recording").fetchSemanticsNodes().isEmpty())
            }
        }
    }
}
