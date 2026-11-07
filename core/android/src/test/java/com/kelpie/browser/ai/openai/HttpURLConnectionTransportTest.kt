package com.kelpie.browser.ai.openai

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.net.ServerSocket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Exercises the real HttpURLConnection transport against an in-process HTTP server. */
class HttpURLConnectionTransportTest {
    private lateinit var server: MiniHttpServer
    private lateinit var other: MiniHttpServer
    private val seenAuth = ConcurrentHashMap<String, String>()
    private val slowStarted = CountDownLatch(1)

    @Before
    fun start() {
        other =
            MiniHttpServer { request, out ->
                seenAuth["other"] = request.headers["authorization"] ?: "<none>"
                out.respond(200, Fixtures.MODELS_JSON)
            }
        server =
            MiniHttpServer { request, out ->
                when (request.path) {
                    "/v1/models" -> {
                        seenAuth[request.path] = request.headers["authorization"] ?: "<none>"
                        out.respond(200, Fixtures.MODELS_JSON)
                    }
                    "/same/v1/models" -> out.respond(302, "", mapOf("Location" to "/v1/models"))
                    "/cross/v1/models" -> out.respond(307, "", mapOf("Location" to "http://127.0.0.1:${other.port}/v1/models"))
                    "/slow/v1/models" -> {
                        out.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n{".toByteArray())
                        out.flush()
                        slowStarted.countDown()
                        runCatching { Thread.sleep(20_000) }
                    }
                    else -> out.respond(404, "")
                }
            }
    }

    @After
    fun stop() {
        server.close()
        other.close()
    }

    private fun base(path: String) = OpenAIEndpointURL.normalize("http://127.0.0.1:${server.port}$path")

    private val client = OpenAIClient(HttpURLConnectionTransport())

    @Test
    fun sendsAuthorizationOnlyWhenKeyExists() {
        runBlocking { client.listModels(base("/v1"), null) }
        assertEquals("<none>", seenAuth["/v1/models"])
        runBlocking { client.listModels(base("/v1"), "sk-test") }
        assertEquals("Bearer sk-test", seenAuth["/v1/models"])
    }

    @Test
    fun followsSameOriginRedirect() {
        val models = runBlocking { client.listModels(base("/same/v1"), "sk-test") }
        assertEquals(listOf("qwen3-q4", "other"), models.map { it.id })
        assertEquals("Bearer sk-test", seenAuth["/v1/models"])
    }

    @Test
    fun refusesCrossOriginRedirectWithoutLeakingKey() {
        try {
            runBlocking { client.listModels(base("/cross/v1"), "sk-test") }
            fail("expected redirect refusal")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.ENDPOINT_REDIRECT_REFUSED, e.code)
        }
        assertNull(seenAuth["other"])
    }

    @Test
    fun connectionRefusedIsUnreachable() {
        val port = ServerSocket(0).use { it.localPort }
        try {
            runBlocking { client.listModels(OpenAIEndpointURL.normalize("http://127.0.0.1:$port"), null) }
            fail("expected unreachable")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.ENDPOINT_UNREACHABLE, e.code)
        }
    }

    @Test
    fun cancellationDisconnectsPromptly() {
        val started = System.nanoTime()
        runBlocking {
            val job = async(Dispatchers.Default) { client.listModels(base("/slow/v1"), null) }
            assertTrue(slowStarted.await(5, TimeUnit.SECONDS))
            delay(100)
            job.cancel()
            // The caller is released promptly; the connection is disconnected and the worker discarded.
            assertNotNull("cancel did not release the caller", withTimeoutOrNull(3_000) { job.join() })
            assertTrue(job.isCancelled)
        }
        assertTrue("cancel took too long", TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started) < 6_000)
    }
}
