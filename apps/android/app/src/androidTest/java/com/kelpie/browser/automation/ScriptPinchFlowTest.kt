package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

class ScriptPinchFlowTest : ScriptPublicFixture() {
    @Test
    fun realPinchClipsVisibleTargetCenterAndExportedMarker() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html").setBody(
                        """<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=5,user-scalable=yes">
                    <title>Pinch fixture</title><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;background:white}
                    button{position:absolute;left:62.5vw;top:35vh;width:50vw;height:40vh;background:#dd0000;color:black;border:0}</style>
                    <button id="target">Zoom target</button><script>window.clicks=0;
                    target.onclick=e=>{const v=visualViewport,r=target.getBoundingClientRect();window.clicks++;
                    document.title=JSON.stringify({clicks:window.clicks,x:e.clientX,y:e.clientY,trusted:e.isTrusted,
                    scale:v.scale,offsetLeft:v.offsetLeft,offsetTop:v.offsetTop,width:v.width,height:v.height,
                    rect:{left:r.left,top:r.top,right:r.right,bottom:r.bottom}})};</script>""",
                    ),
                )
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/pinch").toString())).getBoolean("success"))
                ui.waitUntil(10_000) { client.core("tab.title", tab).optString("value") == "Pinch fixture" }
                val probe = ScriptPinchProbe(instrumentation, ui.activity.window.decorView)
                val record = JSONObject().put("settings", probe.settings()).put("before", probe.metrics())
                val evidenceFile = File(evidence, "pinch-viewport.json")
                evidenceFile.writeText(record.toString(2))
                assertTrue(record.getJSONObject("settings").getBoolean("builtInZoomControls"))
                assertFalse(record.getJSONObject("settings").getBoolean("displayZoomControls"))
                probe.spread()
                ui.waitForIdle()
                val pinched = probe.settledMetrics()
                record.put("pinched", pinched)
                evidenceFile.writeText(record.toString(2))
                assertTrue("Real WebView pinch did not increase scale", pinched.getDouble("scale") > 1.2)
                assertTrue(
                    "Pinch did not produce a nonzero viewport offset",
                    pinched.getDouble("offsetLeft") > 0.1 || pinched.getDouble("offsetTop") > 0.1,
                )
                val script =
                    client
                        .script(tab, client.action("click").put("target", client.target("Zoom target")))
                        .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")).put("maxWidth", 640))
                        .put(
                            "tapIndicator",
                            JSONObject()
                                .put("color", "#3B82F6")
                                .put("radius", 16)
                                .put("fade", false)
                                .put("wobble", false),
                        )
                val result = playRecorded(client, script)
                assertTrue("Pinched semantic click failed", result.getBoolean("success"))
                record.put("clickResult", result)
                evidenceFile.writeText(record.toString(2))
                val artifact = result.getJSONArray("artifacts").getJSONObject(0)
                val file = retrieve(client, result.getString("runId"), artifact)
                val clicked = JSONObject(client.core("tab.title", tab).getString("value"))
                record.put("clicked", clicked)
                evidenceFile.writeText(record.toString(2))
                assertEquals(1, clicked.getInt("clicks"))
                assertFalse(clicked.getBoolean("trusted"))
                val expected = clippedCenter(clicked)
                assertEquals(floor(expected.first), clicked.getDouble("x"), 0.0)
                assertTrue(abs(expected.first - clicked.getDouble("x")) < 1.0)
                assertEquals(floor(expected.second), clicked.getDouble("y"), 0.0)
                assertTrue(abs(expected.second - clicked.getDouble("y")) < 1.0)
                val bitmap = checkNotNull(BitmapFactory.decodeFile(file.path))
                try {
                    val center = blueCenter(bitmap)
                    val px = (expected.first - clicked.getDouble("offsetLeft")) / clicked.getDouble("width") * bitmap.width
                    val py = (expected.second - clicked.getDouble("offsetTop")) / clicked.getDouble("height") * bitmap.height
                    assertEquals(px, center.first, 5.0)
                    assertEquals(py, center.second, 5.0)
                    val redY = (py + 24.0 / clicked.getDouble("height") * bitmap.height).toInt()
                    assertTrue("Fixture red sample must remain visible", redY in 0 until bitmap.height)
                    val underlay = bitmap.getPixel(px.toInt(), redY)
                    assertTrue(
                        "Exported page pixels are not aligned with the marker",
                        Color.red(underlay) > 150 && Color.green(underlay) < 80 && Color.blue(underlay) < 80,
                    )
                    record.put(
                        "overlayPixels",
                        JSONObject()
                            .put("x", center.first)
                            .put("y", center.second)
                            .put("width", bitmap.width)
                            .put("height", bitmap.height),
                    )
                } finally {
                    bitmap.recycle()
                }
                evidenceFile.writeText(record.toString(2))
            }
        }
    }

    private fun clippedCenter(value: JSONObject): Pair<Double, Double> {
        val rect = value.getJSONObject("rect")
        val left = max(rect.getDouble("left"), value.getDouble("offsetLeft"))
        val right = min(rect.getDouble("right"), value.getDouble("offsetLeft") + value.getDouble("width"))
        val top = max(rect.getDouble("top"), value.getDouble("offsetTop"))
        val bottom = min(rect.getDouble("bottom"), value.getDouble("offsetTop") + value.getDouble("height"))
        assertTrue(right > left && bottom > top)
        assertTrue("Fixture target must be partially clipped", right - left < rect.getDouble("right") - rect.getDouble("left") - 1)
        return (left + right) / 2 to (top + bottom) / 2
    }

    private fun blueCenter(image: Bitmap): Pair<Double, Double> {
        var count = 0
        var xSum = 0.0
        var ySum = 0.0
        for (y in 0 until image.height) {
            for (x in 0 until image.width) {
                val color = image.getPixel(x, y)
                if (Color.blue(color) > Color.red(color) + 50 && Color.blue(color) > Color.green(color) + 20) {
                    count++
                    xSum += x
                    ySum += y
                }
            }
        }
        assertTrue("Exported marker pixels are missing", count > 20)
        return xSum / count to ySum / count
    }
}
