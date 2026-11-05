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

    protected fun captureBlueMarker(
        client: ScriptHttpFixture,
        geometry: JSONObject,
    ): Bitmap {
        // Recording can resize the WebView; measure the same fixture after admission.
        val owned = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
        val currentGeometry = readSubmitGeometry(owned, geometry.getString("href"))
        assertEquals(geometry.getString("href"), currentGeometry.getString("href"))
        val deadline = System.nanoTime() + 10_000_000_000L
        var rejected: Bitmap? = null
        val observations = org.json.JSONArray()
        val started = System.nanoTime()
        var nextStatus = started

        fun saveObservations() {
            File(evidence, "native-marker-poll.json").writeText(observations.toString(2))
        }
        while (System.nanoTime() < deadline) {
            // The live overlay invalidates while animating; waiting for Compose idle
            // here would defer the screenshot until the marker has disappeared.
            val viewport = android.graphics.Rect()
            instrumentation.runOnMainSync {
                if (owned.getGlobalVisibleRect(viewport)) {
                    val rootLocation = IntArray(2)
                    owned.rootView.getLocationOnScreen(rootLocation)
                    viewport.offset(rootLocation[0], rootLocation[1])
                }
            }
            val projection = JSONObject()
            val target = submitTargetBounds(owned, currentGeometry, projection)
            val screenshotStartNs = System.nanoTime()
            val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
            val marker = target?.let { ScriptMarkerPixels.locate(bitmap, it) }
            val now = System.nanoTime()
            if (now >= nextStatus && observations.length() < 16) {
                val status = runCatching { client.call("get-script-status") }.getOrNull()
                observations.put(
                    JSONObject()
                        .put("elapsedMs", (now - started) / 1_000_000)
                        .put("startedNs", started)
                        .put("sampleNs", now)
                        .put("screenshotStartNs", screenshotStartNs)
                        .put("actionIndex", status?.optInt("actionIndex", -1) ?: -1)
                        .put("playing", status?.optBoolean("playing") ?: false)
                        .put("targetVisible", target != null)
                        .put("projection", projection)
                        .put("markerFound", marker != null)
                        .put("accessibility", diagnoseSubmitWindows()),
                )
                nextStatus = now + 1_000_000_000L
            }
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
                saveObservations()
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
        saveObservations()
        throw AssertionError("Scene-centered native Submit marker never appeared")
    }

    @Suppress("DEPRECATION")
    private fun diagnoseSubmitWindows(): JSONObject {
        val automation = instrumentation.uiAutomation
        val info = automation.serviceInfo
        val previousFlags = info.flags
        val windows = org.json.JSONArray()
        val active = automation.rootInActiveWindow
        val activePresent = active != null
        active?.recycle()
        try {
            info.flags = previousFlags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            automation.serviceInfo = info
            for (window in automation.windows.take(16)) {
                val root = window.root
                try {
                    val owned = root?.packageName?.toString() == "com.kelpie.browser"
                    val submit = if (owned) root?.findAccessibilityNodeInfosByText("Submit").orEmpty() else emptyList()
                    val stop = if (owned) root?.findAccessibilityNodeInfosByText("Stop").orEmpty() else emptyList()
                    try {
                        windows.put(
                            JSONObject()
                                .put("type", window.type)
                                .put("active", window.isActive)
                                .put("owned", owned)
                                .put("submitCount", submit.size)
                                .put("strictSubmitCount", submit.count { it.isVisibleToUser && it.isClickable && it.text?.toString() == "Submit" })
                                .put("stopCount", stop.size),
                        )
                    } finally {
                        submit.forEach { it.recycle() }
                        stop.forEach { it.recycle() }
                    }
                } finally {
                    root?.recycle()
                    window.recycle()
                }
            }
        } finally {
            info.flags = previousFlags
            automation.serviceInfo = info
        }
        return JSONObject().put("activeRootPresent", activePresent).put("windows", windows)
    }

    private val submitGeometryExpression =
        """(()=>{const b=[...document.querySelectorAll('button')],v=visualViewport;
        if(b.length!==1||b[0].textContent!=='Submit'||!v)return null;
        const r=b[0].getBoundingClientRect();
        return {left:r.left,top:r.top,right:r.right,bottom:r.bottom,
        offsetLeft:v.offsetLeft,offsetTop:v.offsetTop,width:v.width,height:v.height,href:location.href};})()"""

    /** Resolve the single fixture button independently of the marker renderer. */
    protected fun readSubmitGeometry(
        client: ScriptHttpFixture,
        expectedPath: String = "/fixture",
    ): JSONObject {
        val geometry = client.call("evaluate", JSONObject().put("expression", submitGeometryExpression)).getJSONObject("result")
        assertEquals(
            expectedPath,
            android.net.Uri
                .parse(geometry.getString("href"))
                .path,
        )
        assertTrue(geometry.getDouble("right") > geometry.getDouble("left"))
        assertTrue(geometry.getDouble("bottom") > geometry.getDouble("top"))
        return geometry
    }

    /** Read-only fixture probe bypasses the gateway's intentional recording lock. */
    private fun readSubmitGeometry(
        view: android.webkit.WebView,
        expectedHref: String,
    ): JSONObject {
        val value =
            java.util.concurrent.atomic
                .AtomicReference<String>()
        val done = java.util.concurrent.CountDownLatch(1)

        instrumentation.runOnMainSync {
            view.evaluateJavascript(submitGeometryExpression) { result ->
                value.set(result)
                done.countDown()
            }
        }
        check(done.await(3, java.util.concurrent.TimeUnit.SECONDS)) { "Fixture geometry callback timed out" }
        val geometry = JSONObject(checkNotNull(value.get()))
        assertEquals(expectedHref, geometry.getString("href"))
        assertTrue(geometry.getDouble("right") > geometry.getDouble("left"))
        assertTrue(geometry.getDouble("bottom") > geometry.getDouble("top"))
        return geometry
    }

    /** Project DOM CSS coordinates through the exact owned WebView's native transform. */
    private fun submitTargetBounds(
        view: android.webkit.WebView,
        geometry: JSONObject,
        diagnostic: JSONObject,
    ): android.graphics.Rect? {
        var target: android.graphics.Rect? = null
        instrumentation.runOnMainSync {
            diagnostic.put("viewWidth", view.width).put("viewHeight", view.height)
            if (!view.isAttachedToWindow || !view.isShown || view.width <= 0 || view.height <= 0) {
                diagnostic.put("reason", "view-unavailable")
                return@runOnMainSync
            }
            val width = geometry.getDouble("width")
            val height = geometry.getDouble("height")
            diagnostic.put("cssWidth", width).put("cssHeight", height)
            if (!width.isFinite() || !height.isFinite() || width <= 0 || height <= 0) {
                diagnostic.put("reason", "viewport-invalid")
                return@runOnMainSync
            }
            val scaleX = view.width / width
            val scaleY = view.height / height
            diagnostic.put("scaleX", scaleX).put("scaleY", scaleY)
            if (kotlin.math.abs(scaleX / scaleY - 1.0) > 0.02) {
                diagnostic.put("reason", "viewport-scale-mismatch")
                return@runOnMainSync
            }
            val left = (geometry.getDouble("left") - geometry.getDouble("offsetLeft")) * scaleX
            val top = (geometry.getDouble("top") - geometry.getDouble("offsetTop")) * scaleY
            val right = (geometry.getDouble("right") - geometry.getDouble("offsetLeft")) * scaleX
            val bottom = (geometry.getDouble("bottom") - geometry.getDouble("offsetTop")) * scaleY
            diagnostic
                .put("localLeft", left)
                .put("localTop", top)
                .put("localRight", right)
                .put("localBottom", bottom)
            if (left < 0 || top < 0 || right > view.width || bottom > view.height) {
                diagnostic.put("reason", "target-outside-view")
                return@runOnMainSync
            }
            val rect = android.graphics.RectF(left.toFloat(), top.toFloat(), right.toFloat(), bottom.toFloat())
            val matrix = android.graphics.Matrix()
            view.transformMatrixToGlobal(matrix)
            val values = FloatArray(9)
            matrix.getValues(values)
            val sx = values[android.graphics.Matrix.MSCALE_X]
            val sy = values[android.graphics.Matrix.MSCALE_Y]
            diagnostic.put("matrixScaleX", sx.toDouble()).put("matrixScaleY", sy.toDouble())
            if (!matrix.isAffine ||
                sx <= 0f ||
                sy <= 0f ||
                kotlin.math.abs(sx / sy - 1f) > 0.02f ||
                kotlin.math.abs(values[android.graphics.Matrix.MSKEW_X]) > 0.0001f ||
                kotlin.math.abs(values[android.graphics.Matrix.MSKEW_Y]) > 0.0001f
            ) {
                diagnostic.put("reason", "native-transform-unsupported")
                return@runOnMainSync
            }
            val origin = floatArrayOf(0f, 0f)
            matrix.mapPoints(origin)
            matrix.mapRect(rect)
            val screen = IntArray(2)
            view.getLocationOnScreen(screen)
            rect.offset(screen[0] - origin[0], screen[1] - origin[1])
            val visible = android.graphics.Rect()
            if (!view.getGlobalVisibleRect(visible)) {
                diagnostic.put("reason", "view-not-visible")
                return@runOnMainSync
            }
            val rootLocation = IntArray(2)
            view.rootView.getLocationOnScreen(rootLocation)
            visible.offset(rootLocation[0], rootLocation[1])
            val projected =
                android.graphics.Rect(
                    kotlin.math.floor(rect.left.toDouble()).toInt(),
                    kotlin.math.floor(rect.top.toDouble()).toInt(),
                    kotlin.math.ceil(rect.right.toDouble()).toInt(),
                    kotlin.math.ceil(rect.bottom.toDouble()).toInt(),
                )
            diagnostic.put("visible", visible.toShortString()).put("projected", projected.toShortString())
            if (visible.contains(projected)) {
                diagnostic.put("reason", "admitted")
                target = projected
            } else {
                diagnostic.put("reason", "target-clipped")
            }
        }
        return target
    }
}
