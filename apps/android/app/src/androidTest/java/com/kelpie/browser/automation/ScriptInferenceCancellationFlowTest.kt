package com.kelpie.browser.automation

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okhttp3.mockwebserver.SocketPolicy
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Public inference cancellation against an operator-selected local fixture, no API key. */
class ScriptInferenceCancellationFlowTest : ScriptPublicFixture() {
    @Test
    fun publicCancellationRetiresControlledWorkerBeforeRecovery() {
        val entered = CountDownLatch(1)
        val generations = AtomicInteger()
        MockWebServer().use { server ->
            server.dispatcher =
                object : Dispatcher() {
                    override fun dispatch(request: RecordedRequest): MockResponse {
                        assertEquals(null, request.getHeader("Authorization"))
                        if (request.path == "/fixture") return MockResponse().setHeader("Content-Type", "text/html").setBody("<title>Controlled fixture</title><p>Local cancellation fixture</p>")
                        if (request.path == "/v1/models") {
                            return MockResponse()
                                .setHeader("Content-Type", "application/json")
                                .setBody("""{"object":"list","data":[{"id":"controlled-fixture","object":"model"}]}""")
                        }
                        if (request.path == "/v1/chat/completions") {
                            val number = generations.incrementAndGet()
                            if (number == 1) {
                                entered.countDown()
                                return MockResponse().setSocketPolicy(SocketPolicy.NO_RESPONSE)
                            }
                            return MockResponse().setHeader("Content-Type", "text/event-stream").setBody(
                                "data: {\"choices\":[{\"delta\":{\"content\":\"Recovered\"}}]}\n\n" +
                                    "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" +
                                    "data: [DONE]\n\n",
                            )
                        }
                        return MockResponse().setResponseCode(404)
                    }
                }
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                assertTrue(client.call("navigate", JSONObject().put("url", server.url("/fixture").toString())).getBoolean("success"))
                val endpoint =
                    client
                        .call(
                            "ai-endpoint-save",
                            JSONObject()
                                .put("name", "Controlled cancellation fixture")
                                .put("baseURL", server.url("/v1").toString())
                                .put("model", "controlled-fixture"),
                        ).getJSONObject("endpoint")
                        .getString("id")
                assertTrue(client.call("ai-load", JSONObject().put("backend", "openai").put("endpoint", endpoint)).getBoolean("success"))
                assertEquals("ready", client.call("ai-endpoint-health", JSONObject().put("id", endpoint)).getJSONObject("health").getString("state"))
                val body = JSONObject().put("prompt", "Local fixture").put("text", "Controlled text").put("agent", false)
                val executor = Executors.newSingleThreadExecutor()
                var verified = false
                try {
                    val pending = executor.submit<JSONObject> { client.request("/v1/ai-infer", body).second }
                    assertTrue("Provider request never arrived", entered.await(10, TimeUnit.SECONDS))
                    assertEquals("busy", client.call("ai-endpoint-health", JSONObject().put("id", endpoint)).getJSONObject("health").getString("state"))
                    assertEquals(1, client.call("ai-cancel").getInt("cancelled"))
                    val cancelled = pending.get(10, TimeUnit.SECONDS)
                    assertFalse(cancelled.getBoolean("success"))
                    assertEquals("INFERENCE_CANCELLED", cancelled.getJSONObject("error").getString("code"))
                    assertEquals(0, client.call("ai-cancel").getInt("cancelled"))
                    val endpoints = client.call("ai-endpoints").getJSONArray("endpoints")
                    val saved = (0 until endpoints.length()).map(endpoints::getJSONObject).single { it.getString("id") == endpoint }
                    assertEquals("Worker must retire before terminal cancellation", "ready", saved.getJSONObject("health").getString("state"))
                    assertEquals(1, generations.get())
                    val recovered = client.call("ai-infer", body)
                    assertTrue(recovered.getBoolean("success"))
                    assertEquals("Recovered", recovered.getString("response"))
                    assertEquals(2, generations.get())
                    verified = true
                } finally {
                    executor.shutdownNow()
                    // Normal fixture cleanup only after verified retirement/recovery.
                    // A failing run does not delete the selected endpoint to hide it.
                    if (verified) {
                        client.call("ai-unload")
                        client.call("ai-endpoint-remove", JSONObject().put("id", endpoint))
                    }
                }
            }
        }
    }
}
