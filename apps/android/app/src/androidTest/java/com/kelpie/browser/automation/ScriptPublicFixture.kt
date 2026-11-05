package com.kelpie.browser.automation

import android.graphics.Bitmap
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import com.kelpie.browser.MainActivity
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.Base64

abstract class ScriptPublicFixture {
    @get:Rule val ui = createAndroidComposeRule<MainActivity>()
    protected val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    protected val evidence get() = File(instrumentation.targetContext.getExternalFilesDir(null), "script-acceptance").apply { mkdirs() }

    protected fun pair(client: ScriptHttpFixture) {
        ui.waitForIdle()
        if (ui.onAllNodesWithText("Get Started").fetchSemanticsNodes().isNotEmpty()) ui.onNodeWithText("Get Started").performClick()
        client.waitForListener()
        val id = client.beginPair()
        ui.waitUntil(10_000) { ui.onAllNodesWithText("Yes, once").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithText("Yes, once").performClick()
        client.finishPair(id)
    }

    protected fun load(
        client: ScriptHttpFixture,
        server: MockWebServer,
        navigation: Boolean = false,
    ): String {
        val activation = if (navigation) "location.href=\'/next\'" else "document.title=\'Clicked:\'+event.isTrusted"
        server.enqueue(
            MockResponse().setHeader("Content-Type", "text/html").setBody(
                """<!doctype html><meta name="viewport" content="width=device-width"><title>Ready</title>
            <style>body{margin:0;background:white}button{position:absolute;left:100px;top:140px;width:120px;height:60px}</style>
            <button onclick="$activation">Submit</button>
            <input aria-label="Name" style="position:absolute;top:250px" value="private-form-canary">
            <p id="public" style="position:absolute;top:320px">Public fixture</p>""",
            ),
        )
        val tab = client.call("get-tabs").getString("activeTab")
        assertTrue(client.call("navigate", JSONObject().put("url", server.url("/fixture").toString())).getBoolean("success"))
        val deadline = System.nanoTime() + 10_000_000_000L
        while (client.core("tab.title", tab).optString("value") != "Ready" && System.nanoTime() < deadline) Thread.sleep(50)
        assertEquals("Ready", client.core("tab.title", tab).getString("value"))
        return tab
    }

    protected fun retrieve(
        client: ScriptHttpFixture,
        runId: String,
        artifact: JSONObject,
    ): File {
        val bytes = ByteArrayOutputStream()
        var offset = 0L
        do {
            val chunk =
                client.call(
                    "get-script-artifact",
                    JSONObject()
                        .put("runId", runId)
                        .put("artifactId", artifact.getString("id"))
                        .put("offset", offset)
                        .put("length", 4093),
                )
            assertEquals(offset, chunk.getLong("offset"))
            val data = Base64.getDecoder().decode(chunk.getString("data"))
            bytes.write(data)
            offset += data.size
            assertEquals(offset, chunk.getLong("nextOffset"))
        } while (!chunk.getBoolean("eof"))
        val all = bytes.toByteArray()
        assertEquals(artifact.getLong("byteLength"), all.size.toLong())
        val hash = MessageDigest.getInstance("SHA-256").digest(all).joinToString("") { "%02x".format(it) }
        assertEquals(artifact.getString("sha256"), hash)
        val extension =
            when (artifact.getString("mimeType")) {
                "image/png" -> "png"
                "image/gif" -> "gif"
                else -> "mp4"
            }
        return File(evidence, artifact.getString("id") + "." + extension).apply { writeBytes(all) }
    }

    protected fun captureBlueMarker(): Bitmap {
        val deadline = System.nanoTime() + 10_000_000_000L
        while (System.nanoTime() < deadline) {
            val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
            var blue = 0
            for (y in 0 until bitmap.height step 16) {
                for (x in 0 until bitmap.width step 16) {
                    val color = bitmap.getPixel(x, y)
                    if (android.graphics.Color.blue(color) > android.graphics.Color.red(color) + 50 &&
                        android.graphics.Color.blue(color) > android.graphics.Color.green(color) + 20
                    ) {
                        blue++
                    }
                }
            }
            if (blue >= 10) return bitmap
            bitmap.recycle()
            Thread.sleep(50)
        }
        throw AssertionError("Native blue marker never appeared")
    }
}
