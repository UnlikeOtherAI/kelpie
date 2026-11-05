package com.kelpie.browser.automation

import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ScriptArtifactPublicationFlowTest : ScriptPublicFixture() {
    @Test
    fun activeRunWithholdsArtifactsWhilePriorTerminalDownloadRemainsAvailable() {
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val prior =
                    playRecorded(
                        client,
                        client.script(tab, client.action("screenshot")),
                    )
                assertTrue(prior.getBoolean("success"))
                val artifact = prior.getJSONArray("artifacts").getJSONObject(0)
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val pending =
                        executor.submit<JSONObject> {
                            playRecorded(
                                client,
                                client
                                    .script(
                                        tab,
                                        client.action("screenshot"),
                                        client.action("wait").put("ms", 10000),
                                    ).put("capture", JSONObject().put("formats", JSONArray().put("screenshots"))),
                            )
                        }
                    var status = client.call("get-script-status")
                    val end = System.nanoTime() + 15_000_000_000L
                    while ((!status.optBoolean("playing") || status.optInt("actionIndex", -1) < 1) && System.nanoTime() < end) {
                        Thread.sleep(20)
                        status = client.call("get-script-status")
                    }
                    File(evidence, "publication-active-status.json").writeText(status.toString(2))
                    assertTrue(status.getBoolean("playing"))
                    assertTrue(status.getInt("actionIndex") >= 1)
                    assertEquals(0, status.getJSONArray("artifacts").length())
                    assertFalse(status.has("outputs"))
                    val request =
                        JSONObject()
                            .put("runId", status.getString("runId"))
                            .put("artifactId", artifact.getString("id"))
                            .put("length", 1)
                    for (protocol in 0..2) {
                        val reply =
                            when (protocol) {
                                0 -> client.request("/v1/get-script-artifact", request).second
                                1 -> client.mcp("kelpie_get_script_artifact", request)
                                else -> client.mcp("kelpie_extension", JSONObject().put("name", "kelpie_get_script_artifact").put("arguments", request))
                            }
                        File(evidence, "publication-active-$protocol.json").writeText(reply.toString(2))
                        val error = reply.optJSONObject("error") ?: reply.getJSONObject("value").getJSONObject("error")
                        assertEquals("ARTIFACT_NOT_READY", error.getString("code"))
                    }
                    retrieve(client, prior.getString("runId"), artifact)
                    assertTrue(client.call("abort-script", JSONObject().put("runId", status.getString("runId"))).getBoolean("success"))
                    val terminal = pending.get(30, TimeUnit.SECONDS)
                    File(evidence, "publication-terminal.json").writeText(terminal.toString(2))
                    assertEquals("SCRIPT_ABORTED", terminal.getJSONObject("error").getString("code"))
                    assertTrue(terminal.getJSONArray("artifacts").length() > 0)
                    retrieve(client, terminal.getString("runId"), terminal.getJSONArray("artifacts").getJSONObject(0))
                } finally {
                    client.call("abort-script")
                    executor.shutdownNow()
                    assertTrue(executor.awaitTermination(30, TimeUnit.SECONDS))
                }
            }
        }
    }
}
