package com.kelpie.browser.automation

import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** The host CLI pairs normally; only non-secret fixture coordinates cross adb. */
class ScriptCliBridgeTest : ScriptPublicFixture() {
    @Test
    fun hostedCliUsesRealPairingAndOwnerBoundRunStatusDownload() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { fixture ->
                pair(fixture)
                val tab = load(fixture, server)
                server.enqueue(
                    MockResponse().setHeader("Content-Type", "text/html").setBody(
                        scriptNoiseFixture,
                    ),
                )
                val bridgeId =
                    androidx.test.platform.app.InstrumentationRegistry
                        .getArguments()
                        .getString("bridgeId")
                require(bridgeId != null && bridgeId.matches(Regex("[A-Za-z0-9-]{1,64}"))) { "A unique bridgeId is required" }
                val bridge = File(evidence, "cli-bridge-$bridgeId.json")
                val finish = File(evidence, "cli-finish-$bridgeId.txt")
                assertTrue(!finish.exists())
                bridge.writeText(JSONObject().put("tabId", tab).put("url", server.url("/cli").toString()).toString())
                ui.waitUntil(60_000) { ui.onAllNodesWithText("Always allow").fetchSemanticsNodes().isNotEmpty() }
                ui.onNodeWithText("Always allow").performClick()
                ui.waitForIdle()
                ui.waitUntil(840_000) { finish.exists() }
                assertTrue(finish.readText().trim() == "complete:0")
            }
        }
    }
}
