package com.kelpie.browser.automation

import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ScriptSecurityFlowTest : ScriptPublicFixture() {
    @Test
    fun strictRefusalsDispatchNoEarlierActionAndGenericMcpRemainsUsable() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)

                fun click() = client.action("click").put("target", client.target("Submit"))
                val base = client.script(tab, click())
                val invalid =
                    listOf(
                        "SESSION_UNSUPPORTED" to JSONObject(base.toString()).put("sessionId", "unknown"),
                        "SESSION_UNSUPPORTED" to JSONObject(base.toString()).put("sessionId", "foreign-owner-session"),
                        "UNSUPPORTED_SCRIPT_ACTION" to client.script(tab, click(), client.action("press-key").put("key", "Enter")),
                        "UNRESOLVED_SCRIPT_INPUT" to client.script(tab, click()).put("inputs", JSONObject().put("name", JSONObject().put("type", "string"))),
                        "UNRESOLVED_SCRIPT_INPUT" to
                            client.script(tab, click(), client.action("fill").put("target", JSONObject().put("label", "Name")).put("text", JSONObject().put("secret", "operator-reference"))),
                        "INVALID_SCRIPT" to client.script(tab, click(), client.action("evaluate").put("script", "document.title='WRONG'")),
                        "INVALID_SCRIPT" to client.script(tab, click()).put("continueOnError", true),
                        "SENSITIVE_CAPTURE" to
                            client
                                .script(
                                    tab,
                                    click(),
                                    client
                                        .action("fill")
                                        .put("target", JSONObject().put("label", "Name"))
                                        .put("text", "private")
                                        .put("sensitive", true),
                                ).put("capture", JSONObject().put("formats", JSONArray(listOf("gif")))),
                    )
                for ((code, script) in invalid) {
                    val refusal = client.request("/v1/play-script", script)
                    assertTrue(refusal.first in 400..499)
                    assertEquals(code, refusal.second.getJSONObject("error").getString("code"))
                    assertEquals("Ready", client.core("tab.title", tab).getString("value"))
                    assertFalse(client.call("get-script-status").getBoolean("playing"))
                }
                val initialize =
                    client.request(
                        "/mcp",
                        JSONObject()
                            .put("jsonrpc", "2.0")
                            .put("id", 1)
                            .put("method", "initialize")
                            .put(
                                "params",
                                JSONObject()
                                    .put("protocolVersion", "2024-11-05")
                                    .put("capabilities", JSONObject())
                                    .put("clientInfo", JSONObject().put("name", "native-verification").put("version", "1")),
                            ),
                    )
                assertEquals(200, initialize.first)
                assertTrue(initialize.second.has("result"))
                val catalog =
                    client.mcp(
                        "kelpie_extension_tools",
                        JSONObject().put("names", JSONArray(listOf("kelpie_play_script", "kelpie_abort_script", "kelpie_get_script_status", "kelpie_get_script_artifact"))),
                    )
                for (name in listOf("kelpie_play_script", "kelpie_abort_script", "kelpie_get_script_status", "kelpie_get_script_artifact")) assertTrue(catalog.toString().contains(name))
                val completed =
                    client.mcpValue(
                        "kelpie_extension",
                        JSONObject()
                            .put("name", "kelpie_play_script")
                            .put("arguments", client.script(tab, client.action("wait").put("ms", 10)).put("inputs", JSONObject())),
                    )
                assertTrue(completed.getBoolean("success"))
                val status =
                    client.mcpValue(
                        "kelpie_extension",
                        JSONObject()
                            .put("name", "kelpie_get_script_status")
                            .put("arguments", JSONObject().put("runId", completed.getString("runId"))),
                    )
                assertEquals("completed", status.getString("state"))
                assertFalse(status.has("outputs"))
                assertTrue(status.getBoolean("runSuccess"))
            }
        }
    }

    @Test
    fun visibleStopFinalizesPartialMoviesAndNextRunRecovers() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val script =
                    client
                        .script(tab, client.action("wait").put("ms", 20_000))
                        .put("capture", JSONObject().put("formats", JSONArray(listOf("gif", "video"))).put("fps", 5).put("maxWidth", 320))
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val pending = executor.submit<JSONObject> { client.request("/v1/play-script", script).second }
                    awaitRecordingUi(pending)
                    val deadline = System.nanoTime() + 5_000_000_000L
                    while (!client.call("get-script-status").optBoolean("playing") && System.nanoTime() < deadline) Thread.sleep(20)
                    Thread.sleep(1200)
                    ui.onNodeWithContentDescription("Stop recording").performClick()
                    val stopped = pending.get(15, TimeUnit.SECONDS)
                    assertFalse(stopped.getBoolean("success"))
                    assertEquals("SCRIPT_ABORTED", stopped.getJSONObject("error").getString("code"))
                    val status = client.call("get-script-status", JSONObject().put("runId", stopped.getString("runId")))
                    assertTrue(status.getBoolean("success"))
                    assertFalse(status.getBoolean("runSuccess"))
                    assertEquals("aborted", status.getString("state"))
                    assertFalse(status.has("error"))
                    assertFalse(status.has("outputs"))
                    java.io.File(evidence, "stopped-manifest.json").writeText(stopped.toString(2))
                    val artifacts = stopped.getJSONArray("artifacts")
                    assertEquals(2, artifacts.length())
                    for (index in 0 until artifacts.length()) {
                        val artifact = artifacts.getJSONObject(index)
                        assertTrue(artifact.getBoolean("partial"))
                        val file = retrieve(client, stopped.getString("runId"), artifact)
                        var frames = 0
                        ScriptMovieProbe.frames(file) { _, _ -> frames++ }
                        assertTrue(frames > 0)
                    }
                    assertTrue(client.call("play-script", client.script(tab, client.action("wait").put("ms", 10))).getBoolean("success"))
                } finally {
                    executor.shutdownNow()
                }
            }
        }
    }

    @Test
    fun foreignOwnerCannotObserveAbortOrReadAndRevocationStopsOriginalRun() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { first ->
                ScriptHttpFixture().use { second ->
                    pair(first)
                    val tab = load(first, server)
                    pair(second)
                    val executor = Executors.newSingleThreadExecutor()
                    try {
                        val pending = executor.submit<Pair<Int, JSONObject>> { first.request("/v1/play-script", first.script(tab, first.action("wait").put("ms", 20_000))) }
                        awaitRecordingUi(pending)
                        val deadline = System.nanoTime() + 5_000_000_000L
                        var own = first.call("get-script-status")
                        while (!own.optBoolean("playing") && System.nanoTime() < deadline) {
                            Thread.sleep(20)
                            own = first.call("get-script-status")
                        }
                        val runId = own.getString("runId")
                        assertEquals("idle", second.call("get-script-status").getString("state"))
                        for (method in listOf("get-script-status", "abort-script")) {
                            val refusal = second.request("/v1/" + method, JSONObject().put("runId", runId))
                            assertEquals("SCRIPT_NOT_FOUND", refusal.second.getJSONObject("error").getString("code"))
                        }
                        val denied = second.request("/v1/get-script-artifact", JSONObject().put("runId", runId).put("artifactId", "foreign"))
                        assertEquals("SCRIPT_NOT_FOUND", denied.second.getJSONObject("error").getString("code"))
                        assertTrue(first.call("get-script-status").getBoolean("playing"))
                        assertEquals(200, first.request("/v1/pair", method = "DELETE").first)
                        val original = pending.get(15, TimeUnit.SECONDS)
                        assertFalse(original.second.has("outputs"))
                        assertEquals(401, first.request("/v1/get-script-status", JSONObject()).first)
                        val recoveryDeadline = System.nanoTime() + 10_000_000_000L
                        while (true) {
                            val next = second.request("/v1/play-script", second.script(tab, second.action("wait").put("ms", 10)))
                            if (next.second.optBoolean("success")) break
                            assertEquals("RECORDING_IN_PROGRESS", next.second.getJSONObject("error").getString("code"))
                            assertTrue(System.nanoTime() < recoveryDeadline)
                            Thread.sleep(30)
                        }
                    } finally {
                        executor.shutdownNow()
                    }
                }
            }
        }
    }

    @Test
    fun captureDeadlineStopsBeforeFollowingInputAndCapsPartialMovieDuration() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val script =
                    client
                        .script(
                            tab,
                            client.action("wait").put("ms", 1000),
                            client.action("click").put("target", client.target("Submit")),
                        ).put(
                            "capture",
                            JSONObject()
                                .put("formats", JSONArray(listOf("gif", "video")))
                                .put("fps", 10)
                                .put("maxWidth", 320)
                                .put("maxDurationMs", 100),
                        )
                val response = playRecorded(client, script)
                assertFalse(response.getBoolean("success"))
                assertEquals("CAPTURE_DURATION_LIMIT", response.getJSONObject("error").getString("code"))
                assertEquals("Ready", client.core("tab.title", tab).getString("value"))
                val artifacts = response.getJSONArray("artifacts")
                assertTrue(artifacts.length() > 0)
                for (index in 0 until artifacts.length()) {
                    val artifact = artifacts.getJSONObject(index)
                    assertTrue(artifact.getBoolean("partial"))
                    assertTrue(artifact.getDouble("durationMs") <= 101.0)
                    var frames = 0
                    ScriptMovieProbe.frames(retrieve(client, response.getString("runId"), artifact)) { _, _ -> frames++ }
                    assertTrue(frames > 0)
                }
                assertTrue(client.call("play-script", client.script(tab, client.action("wait").put("ms", 10))).getBoolean("success"))
            }
        }
    }

    @Test
    fun screenshotsOnlyDeadlineInterruptsWaitWithoutSamplerOrNextPng() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val script =
                    client
                        .script(
                            tab,
                            client.action("wait").put("ms", 1000),
                            client.action("click").put("target", client.target("Submit")),
                        ).put("capture", JSONObject().put("formats", JSONArray(listOf("screenshots"))).put("maxWidth", 320).put("maxDurationMs", 100))
                val result = playRecorded(client, script)
                assertFalse(result.getBoolean("success"))
                assertEquals("CAPTURE_DURATION_LIMIT", result.getJSONObject("error").getString("code"))
                assertEquals(0, result.getInt("actionsExecuted"))
                assertEquals(0, result.getJSONArray("artifacts").length())
                assertEquals("Ready", client.core("tab.title", tab).getString("value"))
                assertTrue(client.call("play-script", client.script(tab, client.action("wait").put("ms", 10))).getBoolean("success"))
            }
        }
    }

    @Test
    fun genericMcpAbortReturnsOwnerMetadataAndAllowsNextRun() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val pending =
                        executor.submit<JSONObject> {
                            client.request("/v1/play-script", client.script(tab, client.action("wait").put("ms", 20_000))).second
                        }
                    awaitRecordingUi(pending)
                    val active = client.mcpValue("kelpie_get_script_status")
                    assertTrue(active.getBoolean("playing"))
                    val runId = active.getString("runId")
                    val abort =
                        client.mcpValue(
                            "kelpie_extension",
                            JSONObject().put("name", "kelpie_abort_script").put("arguments", JSONObject().put("runId", runId)),
                        )
                    assertTrue(abort.getBoolean("success"))
                    assertTrue(abort.getBoolean("abortRequested"))
                    val result = pending.get(15, TimeUnit.SECONDS)
                    assertEquals("SCRIPT_ABORTED", result.getJSONObject("error").getString("code"))
                    ui.waitForIdle()
                    val status = client.mcpValue("kelpie_get_script_status", JSONObject().put("runId", runId))
                    assertTrue(status.getBoolean("success"))
                    assertFalse(status.getBoolean("runSuccess"))
                    assertEquals("aborted", status.getString("state"))
                    assertFalse(status.has("error"))
                    assertFalse(status.has("outputs"))
                    assertTrue(client.call("play-script", client.script(tab, client.action("wait").put("ms", 10))).getBoolean("success"))
                } finally {
                    executor.shutdownNow()
                }
            }
        }
    }
}
