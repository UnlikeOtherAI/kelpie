package com.kelpie.browser.automation

import android.graphics.Bitmap
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
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
        ui.waitForIdle()
        ui.waitUntil(10_000) { ui.onAllNodesWithText("Yes, once").fetchSemanticsNodes().isEmpty() }
        client.finishPair(id)
    }

    protected fun load(
        client: ScriptHttpFixture,
        server: MockWebServer,
        navigation: Boolean = false,
    ): String {
        val fixtureId = "fixture-" + java.util.UUID.randomUUID()
        val activation = if (navigation) "location.href=\'/next\'" else "document.title=\'Clicked:\'+event.isTrusted"
        server.enqueue(
            MockResponse().setHeader("Content-Type", "text/html").setBody(
                """<!doctype html><meta name="viewport" content="width=device-width"><title>Ready</title>
            <style>body{margin:0;background:white}button{position:absolute;left:100px;top:140px;width:120px;height:60px;background:#eee;color:#111;border:1px solid #777;box-sizing:border-box}</style>
            <button id="$fixtureId" onclick="$activation">Submit</button>
            <input aria-label="Name" style="position:absolute;top:250px" value="private-form-canary">
            <p id="public" style="position:absolute;top:320px">Public fixture</p>""",
            ),
        )
        val tab = client.call("get-tabs").getString("activeTab")
        assertTrue(client.call("navigate", JSONObject().put("url", server.url("/fixture").toString())).getBoolean("success"))
        ui.waitUntil(15_000) {
            client.core("tab.title", tab).optString("value") == "Ready" &&
                client
                    .core("tab.ready", tab, JSONObject().put("state", "complete").put("selector", "#" + fixtureId))
                    .getJSONObject("value")
                    .getBoolean("ready")
        }
        ui.waitForIdle()
        ScriptPinchProbe(instrumentation, ui.activity.window.decorView).settledNativeGeometry()
        return tab
    }

    protected fun retrieve(
        client: ScriptHttpFixture,
        runId: String,
        artifact: JSONObject,
    ): File {
        val expected = artifact.getLong("byteLength")
        assertTrue(expected in 1..268_435_456L)
        var verified: ByteArray? = null
        for (protocol in 0..2) {
            val bytes = ByteArrayOutputStream()
            var offset = 0L
            var count = 0L
            val deadline = System.nanoTime() + 60_000_000_000L
            do {
                assertTrue("Artifact download deadline", System.nanoTime() < deadline)
                assertTrue("Artifact chunk bound", count++ <= (expected + 4092) / 4093)
                val request =
                    JSONObject()
                        .put("runId", runId)
                        .put("artifactId", artifact.getString("id"))
                        .put("offset", offset)
                        .put("length", 4093)
                val chunk =
                    when (protocol) {
                        0 -> client.call("get-script-artifact", request)
                        1 -> client.mcpValue("kelpie_get_script_artifact", request)
                        else -> client.mcpValue("kelpie_extension", JSONObject().put("name", "kelpie_get_script_artifact").put("arguments", request))
                    }
                assertEquals(runId, chunk.getString("runId"))
                assertEquals(artifact.getString("id"), chunk.getString("artifactId"))
                assertEquals(artifact.getString("mimeType"), chunk.getString("mimeType"))
                assertEquals(artifact.getString("sha256"), chunk.getString("sha256"))
                assertEquals(expected, chunk.getLong("byteLength"))
                assertEquals(offset, chunk.getLong("offset"))
                val data = Base64.getDecoder().decode(chunk.getString("data"))
                assertTrue("Non-progressing or oversized chunk", data.isNotEmpty() && data.size <= 4093)
                bytes.write(data)
                offset += data.size
                assertTrue(offset <= expected)
                assertEquals(offset, chunk.getLong("nextOffset"))
                assertEquals(offset == expected, chunk.getBoolean("eof"))
            } while (offset < expected)
            val all = bytes.toByteArray()
            assertEquals(expected, all.size.toLong())
            assertEquals(artifact.getString("sha256"), MessageDigest.getInstance("SHA-256").digest(all).joinToString("") { "%02x".format(it) })
            verified?.let { assertTrue("Protocol bytes differ", it.contentEquals(all)) }
            verified = all
        }
        val extension =
            when (artifact.getString("mimeType")) {
                "image/png" -> "png"
                "image/gif" -> "gif"
                else -> "mp4"
            }
        return File(evidence, artifact.getString("id") + "." + extension).apply { writeBytes(checkNotNull(verified)) }
    }

    protected fun awaitRecordingUi(pending: java.util.concurrent.Future<*>? = null) {
        ui.waitUntil(10_000) {
            ui.onAllNodesWithContentDescription("Stop recording").fetchSemanticsNodes().isNotEmpty() || pending?.isDone == true
        }
        ui.waitForIdle()
    }

    protected fun playRecorded(
        client: ScriptHttpFixture,
        script: JSONObject,
    ): JSONObject {
        val executor =
            java.util.concurrent.Executors
                .newSingleThreadExecutor()
        try {
            val pending = executor.submit<JSONObject> { client.request("/v1/play-script", script).second }
            awaitRecordingUi(pending)
            val result = pending.get(60, java.util.concurrent.TimeUnit.SECONDS)
            ui.waitForIdle()
            return result
        } finally {
            executor.shutdownNow()
        }
    }

    protected fun captureBlueMarker(): Bitmap {
        val owned = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
        val deadline = System.nanoTime() + 10_000_000_000L
        var rejected: Bitmap? = null
        while (System.nanoTime() < deadline) {
            // The live overlay invalidates while animating; waiting for Compose idle
            // here would defer the screenshot until the marker has disappeared.
            val viewport = android.graphics.Rect()
            instrumentation.runOnMainSync {
                val location = IntArray(2)
                owned.getLocationOnScreen(location)
                viewport.set(location[0], location[1], location[0] + owned.width, location[1] + owned.height)
            }
            val target = submitTargetBounds(viewport)
            val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
            val marker = target?.let { ScriptMarkerPixels.locate(bitmap, it) }
            if (marker != null) {
                val confirmedTarget = checkNotNull(target)
                rejected?.recycle()
                File(evidence, "native-marker-evidence.json").writeText(
                    JSONObject()
                        .put(
                            "target",
                            JSONObject()
                                .put("left", confirmedTarget.left)
                                .put("top", confirmedTarget.top)
                                .put("right", confirmedTarget.right)
                                .put("bottom", confirmedTarget.bottom),
                        ).put(
                            "webView",
                            JSONObject()
                                .put("left", viewport.left)
                                .put("top", viewport.top)
                                .put("right", viewport.right)
                                .put("bottom", viewport.bottom),
                        ).put("componentArea", marker.area)
                        .put("centerX", marker.x)
                        .put("centerY", marker.y)
                        .put("centerCoverage", marker.centerCoverage)
                        .toString(2),
                )
                return bitmap
            }
            rejected?.recycle()
            rejected = bitmap
            Thread.sleep(50)
        }
        rejected?.let { image ->
            File(evidence, "native-marker-rejected.png").outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            image.recycle()
        }
        throw AssertionError("Scene-centered native Submit marker never appeared")
    }

    @Suppress("DEPRECATION")
    private fun submitTargetBounds(viewport: android.graphics.Rect): android.graphics.Rect? {
        val root = instrumentation.uiAutomation.rootInActiveWindow ?: return null
        try {
            val nodes = root.findAccessibilityNodeInfosByText("Submit")
            try {
                for (node in nodes) {
                    if (!node.isVisibleToUser || !node.isClickable || node.text?.toString() != "Submit") continue
                    val rect = android.graphics.Rect()
                    node.getBoundsInScreen(rect)
                    if (rect.intersect(viewport) && !rect.isEmpty) return rect
                }
            } finally {
                nodes.forEach { it.recycle() }
            }
        } finally {
            root.recycle()
        }
        return null
    }
}
