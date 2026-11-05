package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
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

/** Real app UI pairing, production HTTP/MCP routes and retrieved native artifacts. */
class ScriptPublicFlowTest : ScriptPublicFixture() {
    @Test
    fun ownerBoundHttpCaptureAndDirectMcpStatusProduceDecodableArtifacts() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val snapshot = client.core("tab.snapshot", tab).toString()
                assertTrue(snapshot.contains("Public fixture"))
                assertFalse(snapshot.contains("private-form-canary"))
                val script =
                    client
                        .script(
                            tab,
                            client.action("wait-ready").put("state", "complete").put("selector", "button"),
                            client.action("extract").put("name", "page").put(
                                "params",
                                JSONObject().put("fields", JSONArray().put(JSONObject().put("name", "public").put("selector", "#public").put("source", "text"))),
                            ),
                            client.action("click").put("target", client.target("Submit")),
                            client.action("wait").put("ms", 900),
                            client.action("output").put("name", "title").put("source", "title"),
                        ).put("capture", JSONObject().put("formats", JSONArray(listOf("gif", "video", "screenshots"))).put("fps", 10).put("maxWidth", 320))
                        .put("pointer", JSONObject().put("enabled", true).put("curve", "s").put("durationMs", 400))
                        .put(
                            "tapIndicator",
                            JSONObject()
                                .put("color", "#3B82F6")
                                .put("durationMs", 700)
                                .put("wobble", true)
                                .put("fade", true),
                        )
                val executor = Executors.newSingleThreadExecutor()
                val result: JSONObject
                try {
                    val pending = executor.submit<JSONObject> { client.call("play-script", script) }
                    // Sampling the animation must not wait for Compose to become idle.
                    val deadline = System.nanoTime() + 5_000_000_000L
                    while (!client.call("get-script-status").optBoolean("playing") && System.nanoTime() < deadline) Thread.sleep(30)
                    Thread.sleep(550)
                    val screen = captureBlueMarker()
                    File(evidence, "native-active-overlay.png").outputStream().use { screen.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    screen.recycle()
                    result = pending.get(30, TimeUnit.SECONDS)
                } finally {
                    executor.shutdownNow()
                }
                assertTrue("Typed workflow failed", result.getBoolean("success"))
                assertEquals("Clicked:false", result.getJSONObject("outputs").getString("title"))
                assertTrue(
                    result
                        .getJSONObject("outputs")
                        .getJSONObject("page")
                        .toString()
                        .contains("Public fixture"),
                )
                val runId = result.getString("runId")
                val status = client.mcpValue("kelpie_get_script_status", JSONObject().put("runId", runId))
                assertEquals("completed", status.getString("state"))
                assertTrue(status.getBoolean("success"))
                assertTrue(status.getBoolean("runSuccess"))
                assertFalse(status.has("outputs"))
                assertFalse(status.has("error"))
                val artifacts = result.getJSONArray("artifacts")
                assertEquals(7, artifacts.length())
                for (index in 0 until artifacts.length()) {
                    val artifact = artifacts.getJSONObject(index)
                    val file = retrieve(client, runId, artifact)
                    when (artifact.getString("mimeType")) {
                        "image/png", "image/gif" -> {
                            val bitmap = checkNotNull(BitmapFactory.decodeFile(file.absolutePath))
                            assertEquals(artifact.getInt("width"), bitmap.width)
                            assertEquals(artifact.getInt("height"), bitmap.height)
                            bitmap.recycle()
                        }
                        "video/mp4" -> {
                            val decoder = MediaMetadataRetriever()
                            try {
                                decoder.setDataSource(file.absolutePath)
                                val frame = checkNotNull(decoder.getFrameAtTime(600_000, MediaMetadataRetriever.OPTION_CLOSEST))
                                assertEquals(artifact.getInt("width"), frame.width)
                                assertEquals(artifact.getInt("height"), frame.height)
                                frame.recycle()
                                val duration = checkNotNull(decoder.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)).toDouble()
                                assertEquals(artifact.getDouble("durationMs"), duration, 50.0)
                            } finally {
                                decoder.release()
                            }
                        }
                    }
                }
                File(evidence, "manifest.json").writeText(result.toString(2))
                val idle = client.call("get-script-status")
                assertEquals(runId, idle.getString("runId"))
                assertFalse(idle.has("outputs"))
            }
        }
    }

    @Test
    fun moviesOnlyOneFpsNavigationRetainsOldDocumentMarkerInEveryFormat() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server, navigation = true)
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html").setBody(
                        """<!doctype html><meta name="viewport" content="width=device-width"><title>Destination</title><body style="margin:0;background:#e63946"><div id="destination">Destination</div>""",
                    ),
                )
                val script =
                    client
                        .script(
                            tab,
                            client.action("click").put("target", client.target("Submit")),
                            client.action("wait-ready").put("state", "complete").put("selector", "#destination"),
                            client.action("wait").put("ms", 1200),
                        ).put("capture", JSONObject().put("formats", JSONArray(listOf("gif", "video"))).put("fps", 1).put("maxWidth", 320))
                        .put("tapIndicator", JSONObject().put("color", "#3B82F6").put("durationMs", 100))
                val result = playRecorded(client, script)
                assertTrue("Low-FPS navigation failed", result.getBoolean("success"))
                val artifacts = result.getJSONArray("artifacts")
                assertEquals(2, artifacts.length())
                for (index in 0 until artifacts.length()) {
                    val artifact = artifacts.getJSONObject(index)
                    val file = retrieve(client, result.getString("runId"), artifact)
                    var markerOnOld = false
                    var markerOnNew = false
                    var frames = 0
                    var previous = -1L
                    val markerX = (160.0 * artifact.getInt("width") / artifact.getJSONObject("viewport").getDouble("width")).toInt()
                    val markerY = (170.0 * artifact.getInt("height") / artifact.getJSONObject("viewport").getDouble("height")).toInt()
                    ScriptMovieProbe.frames(file) { bitmap, timestamp ->
                        if (previous >= 0) assertTrue("Movie exceeded requested FPS", timestamp - previous >= 990_000)
                        previous = timestamp
                        frames++
                        val corner = bitmap.getPixel(1, 1)
                        val old = android.graphics.Color.red(corner) > 200 && android.graphics.Color.green(corner) > 200
                        val center = bitmap.getPixel(markerX.coerceIn(0, bitmap.width - 1), markerY.coerceIn(0, bitmap.height - 1))
                        val blue =
                            android.graphics.Color.blue(center) > android.graphics.Color.red(center) + 50 &&
                                android.graphics.Color.blue(center) > android.graphics.Color.green(center) + 20
                        if (blue && old) markerOnOld = true
                        if (blue && !old) markerOnNew = true
                        File(evidence, artifact.getString("id") + "-frame-" + frames + ".png").outputStream().use {
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                        }
                    }
                    assertEquals(artifact.getInt("frameCount"), frames)
                    assertTrue("No decoded pre-navigation marker", markerOnOld)
                    assertFalse("Marker attached to destination document", markerOnNew)
                }
                File(evidence, "low-fps-manifest.json").writeText(result.toString(2))
            }
        }
    }
}
