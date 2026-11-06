package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import androidx.test.platform.app.InstrumentationRegistry
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** API-floor smoke using the real native marker and authenticated PNG retrieval. */
class ScriptApi29SmokeTest : ScriptPublicFixture() {
    @Test
    fun oneSemanticClickShowsNativeMarkerAndReturnsOneDecodablePng() {
        assumeTrue(Build.VERSION.SDK_INT == 29 && InstrumentationRegistry.getArguments().getString("api29Smoke") == "true")
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val geometry = readSubmitGeometry(client)
                val script =
                    client
                        .script(tab, client.action("click").put("target", client.target("Submit")))
                        .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                        .put("pointer", JSONObject().put("enabled", false))
                        .put("tapIndicator", JSONObject().put("color", "#3B82F6").put("durationMs", 5000).put("fade", false))
                val executor = Executors.newSingleThreadExecutor()
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
                File(evidence, "api29-one-step-result.json").writeText(result.toString(2))
                assertTrue(result.toString(), result.getBoolean("success"))
                assertEquals("completed", result.getString("state"))
                assertEquals(1, result.getInt("actionsExecuted"))
                assertEquals("Clicked:false", client.core("tab.title", tab).getString("value"))
                val screen = captureBlueMarker(client, geometry)
                File(evidence, "api29-native-marker.png").outputStream().use {
                    screen.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                screen.recycle()
                val artifacts = result.getJSONArray("artifacts")
                assertEquals(1, artifacts.length())
                val artifact = artifacts.getJSONObject(0)
                assertEquals("image/png", artifact.getString("mimeType"))
                val png = retrieve(client, result.getString("runId"), artifact)
                val bitmap = checkNotNull(BitmapFactory.decodeFile(png.absolutePath))
                assertEquals(artifact.getInt("width"), bitmap.width)
                assertEquals(artifact.getInt("height"), bitmap.height)
                bitmap.recycle()
            }
        }
    }
}
