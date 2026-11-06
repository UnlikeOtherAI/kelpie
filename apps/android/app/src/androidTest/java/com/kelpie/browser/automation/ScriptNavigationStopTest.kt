package com.kelpie.browser.automation

import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** Stop is issued only after the owned server observes the admitted navigation. */
class ScriptNavigationStopTest : ScriptPublicFixture() {
    @Test
    fun nativeStopDuringIssuedNavigationPreservesUncertaintyAndRecovers() {
        val releaseResponse = CountDownLatch(1)
        MockWebServer().use { server ->
            server.start()
            ScriptHttpFixture().use { client ->
                pair(client)
                val tab = load(client, server)
                val issued = CountDownLatch(1)
                val requests = AtomicInteger()
                server.dispatcher =
                    object : Dispatcher() {
                        override fun dispatch(request: RecordedRequest): MockResponse {
                            if (request.path != "/slow") return MockResponse().setResponseCode(404)
                            requests.incrementAndGet()
                            issued.countDown()
                            check(releaseResponse.await(30, TimeUnit.SECONDS))
                            return MockResponse()
                                .setHeader("Content-Type", "text/html")
                                .setBody("<!doctype html><title>Delayed destination</title>")

                        }
                    }
                val executor = Executors.newSingleThreadExecutor()
                try {
                    val script = client.script(tab, client.action("navigate").put("url", server.url("/slow").toString()))
                    val pending = executor.submit<JSONObject> { client.request("/v1/play-script", script).second }
                    awaitRecordingUi(pending)
                    assertTrue("Owned navigation was never issued", issued.await(15, TimeUnit.SECONDS))
                    assertTrue("Navigation finished before Stop", !pending.isDone)
                    ui.onNodeWithContentDescription("Stop recording").performClick()
                    val result = pending.get(30, TimeUnit.SECONDS)
                    File(evidence, "navigation-stop-result.json").writeText(result.toString(2))
                    assertEquals("aborted", result.getString("state"))
                    assertEquals("SCRIPT_ABORTED", result.getJSONObject("error").getString("code"))
                    assertTrue(result.getBoolean("mayHaveCompleted"))
                    assertEquals(1, requests.get())
                    assertTrue(client.call("play-script", client.script(tab, client.action("wait").put("ms", 10))).getBoolean("success"))
                } finally {
                    releaseResponse.countDown()
                    executor.shutdownNow()
                }
            }
        }
    }
}
