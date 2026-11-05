package com.kelpie.browser.automation

import android.graphics.BitmapFactory
import android.graphics.Color
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Window captures require the certified recording scene. */
class ScriptCompositorCaptureTest : ScriptPublicFixture() {
    @Test
    fun uncertifiedSceneRefusesBeforePixelCopy() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                load(client, server)
                val view = ScriptPinchProbe(instrumentation, ui.activity.window.decorView).view
                var code: String? = null
                instrumentation.runOnMainSync {
                    try {
                        ScriptCompositorCapture(view) { -1L }.rectangle()
                    } catch (error: ScriptFailure) {
                        code = error.code
                    }
                }
                assertEquals("CAPTURE_VIEW_UNAVAILABLE", code)
            }
        }
    }

    @Test
    fun exportedPageDoesNotContainTheNativeStopControl() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val script =
                    client
                        .script(tab, client.action("screenshot"))
                        .put("capture", JSONObject().put("formats", JSONArray().put("screenshots")))
                val result = playRecorded(client, script)
                assertTrue(result.toString(), result.getBoolean("success"))
                val artifact = result.getJSONArray("artifacts").getJSONObject(0)
                val file = retrieve(client, result.getString("runId"), artifact)
                val bitmap = checkNotNull(BitmapFactory.decodeFile(file.path))
                try {
                    // The entire upper strip of the fixture is white. A sampled
                    // Stop control anywhere in that strip would introduce dark pixels.
                    for (y in 0 until bitmap.height / 10 step 4) {
                        for (x in 0 until bitmap.width step 4) {
                            val pixel = bitmap.getPixel(x, y)
                            assertTrue(Color.red(pixel) > 245 && Color.green(pixel) > 245 && Color.blue(pixel) > 245)
                        }
                    }
                } finally {
                    bitmap.recycle()
                }
            }
        }
    }
}
