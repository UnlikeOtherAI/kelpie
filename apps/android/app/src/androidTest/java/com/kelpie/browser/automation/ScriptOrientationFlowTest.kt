package com.kelpie.browser.automation

import android.app.UiAutomation
import android.content.pm.ActivityInfo
import android.os.SystemClock
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ScriptOrientationFlowTest : ScriptPublicFixture() {
    @Test
    fun recordingLocksNormalRotationAndRestoresPolicyAfterSuccessAbortAndFailure() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val probe = ScriptPinchProbe(instrumentation, ui.activity.window.decorView)
                val originalRotation = rotation()
                val originalPolicy = ui.activity.requestedOrientation
                assertEquals(
                    "Fresh fixture must retain its normal orientation policy",
                    ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED,
                    originalPolicy,
                )
                val report = JSONArray()
                val evidenceFile = File(evidence, "recording-orientation.json")
                val executor = Executors.newSingleThreadExecutor()
                try {
                    for (mode in listOf("success", "abort", "failure")) {
                        val actions = mutableListOf(client.action("wait").put("ms", 5000))
                        if (mode == "failure") actions.add(client.action("click").put("target", client.target("Absent target")))
                        val pending =
                            executor.submit<JSONObject> {
                                client.request("/v1/play-script", client.script(tab, *actions.toTypedArray())).second
                            }
                        awaitRecordingUi(pending)
                        ui.waitUntil(10_000) { ui.activity.requestedOrientation == ActivityInfo.SCREEN_ORIENTATION_LOCKED }
                        ui.waitUntil(10_000) {
                            val status = client.call("get-script-status")
                            status.getBoolean("playing") && status.has("actionIndex")
                        }
                        ui.waitForIdle()
                        val width = probe.view.width
                        val height = probe.view.height
                        val targetRotation = (rotation() + 1) % 4
                        val record =
                            JSONObject()
                                .put("mode", mode)
                                .put("originalPolicy", originalPolicy)
                                .put("lockedPolicy", ui.activity.requestedOrientation)
                                .put("width", width)
                                .put("height", height)
                                .put("requestedDeviceRotation", targetRotation)
                        report.put(record)
                        evidenceFile.writeText(report.toString(2))
                        assertTrue("Standard device rotation request failed", instrumentation.uiAutomation.setRotation(targetRotation))
                        val observeUntil = SystemClock.uptimeMillis() + 600
                        ui.waitUntil(5_000) {
                            assertEquals("Locked renderer width changed", width, probe.view.width)
                            assertEquals("Locked renderer height changed", height, probe.view.height)
                            assertEquals(ActivityInfo.SCREEN_ORIENTATION_LOCKED, ui.activity.requestedOrientation)
                            SystemClock.uptimeMillis() >= observeUntil
                        }
                        record.put("heldWidth", probe.view.width).put("heldHeight", probe.view.height)
                        if (mode == "abort") client.call("abort-script")
                        val result = pending.get(30, TimeUnit.SECONDS)
                        record.put("result", result)
                        evidenceFile.writeText(report.toString(2))
                        assertEquals(mode == "success", result.getBoolean("success"))
                        if (mode != "success") {
                            assertEquals(
                                if (mode == "abort") "SCRIPT_ABORTED" else "TARGET_NOT_FOUND",
                                result.getJSONObject("error").getString("code"),
                            )
                        }
                        ui.waitForIdle()
                        ui.waitUntil(10_000) { ui.activity.requestedOrientation == originalPolicy }
                        record.put("restoredPolicy", ui.activity.requestedOrientation)
                        assertTrue(instrumentation.uiAutomation.setRotation(targetRotation))
                        ui.waitUntil(10_000) { probe.view.width != width }
                        record
                            .put("releasedWidth", probe.view.width)
                            .put("releasedHeight", probe.view.height)
                            .put("releasedDeviceRotation", rotation())
                        evidenceFile.writeText(report.toString(2))
                        assertTrue(instrumentation.uiAutomation.setRotation(originalRotation))
                        ui.waitUntil(10_000) { probe.view.width == width }
                    }
                } finally {
                    executor.shutdownNow()
                    instrumentation.uiAutomation.setRotation(originalRotation)
                    instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_UNFREEZE)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun rotation(): Int {
        var result = 0
        instrumentation.runOnMainSync { result = ui.activity.windowManager.defaultDisplay.rotation }
        return result
    }
}
