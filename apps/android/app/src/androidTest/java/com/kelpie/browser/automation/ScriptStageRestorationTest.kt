package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
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
import kotlin.math.abs

/** Real tablet stage restores its rounded corners after every terminal state. */
class ScriptStageRestorationTest : ScriptPublicFixture() {
    @Test
    fun stageUnclipsWhileRecordingAndRestoresOnSuccessAbortAndFailure() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("deviceClass") == "tablet")
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                ui.onNodeWithContentDescription("More").performClick()
                ui.onNodeWithText("3.4\" Flip Cover").performClick()
                ui.onNodeWithContentDescription("Close staged viewport").assertExists()
                val probe = ScriptPinchProbe(instrumentation, ui.activity.window.decorView)
                probe.settledNativeGeometry()
                val executor = Executors.newSingleThreadExecutor()
                try {
                    for (terminal in listOf("success", "abort", "failure")) {
                        val before = stageFrame(probe, "stage-$terminal-before.png")
                        assertTrue("Stage must begin rounded", before > 8)
                        val actions = mutableListOf(client.action("wait").put("ms", 4000))
                        if (terminal == "failure") {
                            actions.add(client.action("click").put("target", client.target("Absent target")))
                        }
                        val script =
                            client
                                .script(tab, *actions.toTypedArray())
                                .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                        val pending = executor.submit<JSONObject> { client.request("/v1/play-script", script).second }
                        awaitRecordingUi(pending)
                        ui.waitUntil(10_000) { client.call("get-script-status").optBoolean("playing") }
                        val during = stageFrame(probe, "stage-$terminal-during.png")
                        assertTrue("Stage must expose rectangular page pixels while recording", during <= 8)
                        if (terminal == "abort") client.call("abort-script")
                        val result = pending.get(30, TimeUnit.SECONDS)
                        assertEquals(terminal == "success", result.getBoolean("success"))
                        if (terminal != "success") {
                            assertEquals(
                                if (terminal == "abort") "SCRIPT_ABORTED" else "TARGET_NOT_FOUND",
                                result.getJSONObject("error").getString("code"),
                            )
                        }
                        ui.waitForIdle()
                        val after = stageFrame(probe, "stage-$terminal-after.png")
                        assertTrue("Stage must restore rounded corners after $terminal", after > 8)
                    }
                } finally {
                    executor.shutdownNow()
                    ui.onNodeWithContentDescription("Close staged viewport").performClick()
                }
            }
        }
    }

    private fun stageFrame(
        probe: ScriptPinchProbe,
        name: String,
    ): Int {
        ui.waitForIdle()
        val location = IntArray(2)
        var width = 0
        instrumentation.runOnMainSync {
            probe.view.getLocationOnScreen(location)
            width = probe.view.width
        }
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            File(evidence, name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            val corner = bitmap.getPixel(location[0] + 1, location[1] + 1)
            val interior = bitmap.getPixel(location[0] + width / 2, location[1] + 4)
            return abs(Color.red(corner) - Color.red(interior)) +
                abs(Color.green(corner) - Color.green(interior)) +
                abs(Color.blue(corner) - Color.blue(interior))
        } finally {
            bitmap.recycle()
        }
    }
}
