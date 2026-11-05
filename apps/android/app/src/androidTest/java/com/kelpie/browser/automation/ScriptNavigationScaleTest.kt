package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ScriptNavigationScaleTest : ScriptPublicFixture() {
    @Test
    fun captureSurvivesNavigationToDifferentInitialPageScale() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server, navigation = true)
                val probe = ScriptPinchProbe(instrumentation, ui.activity.window.decorView)
                val before = probe.settledNativeGeometry()
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html").setBody(
                        """<!doctype html><meta name="viewport" content="width=device-width,initial-scale=0.5"><title>Scale destination</title><div id="destination">Destination</div>""",
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
                val result = playRecorded(client, script)
                val deadline = System.nanoTime() + 10_000_000_000L
                while (client.core("tab.title", tab).optString("value") != "Scale destination" && System.nanoTime() < deadline) Thread.sleep(20)
                val after = probe.settledNativeGeometry()
                File(evidence, "navigation-scale.json").writeText(
                    JSONObject()
                        .put("before", before)
                        .put("after", after)
                        .put("result", result)
                        .toString(2),
                )
                assertNotEquals("Fixture did not change native page scale", before.getDouble("nativeScale"), after.getDouble("nativeScale"), 0.001)
                assertTrue("Capture rejected document navigation with changed initial page scale", result.getBoolean("success"))
            }
        }
    }
}
