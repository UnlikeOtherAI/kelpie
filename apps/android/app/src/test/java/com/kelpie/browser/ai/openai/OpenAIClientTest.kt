package com.kelpie.browser.ai.openai

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class OpenAIClientTest {
    private val base = OpenAIEndpointURL.normalize("http://studio.local:1234")

    private fun discoveryCode(response: FakeResponse): String {
        val client = OpenAIClient(FakeTransport { response })
        return try {
            runBlocking { client.listModels(base, null) }
            "OK"
        } catch (e: OpenAIException) {
            e.code
        }
    }

    @Test
    fun parsesModelsWithMetadata() {
        val body =
            """{"data":[
              {"id":"a","meta":{"n_ctx":4096},"context_length":99},
              {"id":"b","max_model_len":32768,"architecture":{"input_modalities":["text","image"]}},
              {"id":"c","architecture":{"input_modalities":["text"]},"state":"not-loaded"},
              {"id":"d","capabilities":["completion","vision"],"status":"loading"},
              {"id":""},{"name":"no id"},42,{"id":"a"}
            ]}"""
        val models = ModelsParser.parse(body)
        assertEquals(listOf("a", "b", "c", "d"), models.map { it.id })
        assertEquals(4096, models[0].contextWindow)
        assertNull(models[0].vision)
        assertEquals(32768, models[1].contextWindow)
        assertEquals(true, models[1].vision)
        assertEquals(false, models[2].vision)
        assertEquals(ModelStatus.UNLOADED, models[2].status)
        assertEquals(true, models[3].vision)
        assertEquals(ModelStatus.LOADING, models[3].status)
        assertEquals(listOf("x"), ModelsParser.parse("""{"models":[{"id":"x"}]}""").map { it.id })
    }

    @Test
    fun malformedModelResponses() {
        listOf("not json", "[]", "{}", """{"data":{}}""", """{"data":"x"}""").forEach { body ->
            try {
                ModelsParser.parse(body)
                fail("expected malformed for $body")
            } catch (e: OpenAIException) {
                assertEquals(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, e.code)
            }
        }
    }

    @Test
    fun discoveryFailureCodes() {
        assertEquals(OpenAIErrorCode.ENDPOINT_AUTH_FAILED, discoveryCode(FakeResponse(401, "{}")))
        assertEquals(OpenAIErrorCode.ENDPOINT_AUTH_FAILED, discoveryCode(FakeResponse(403, "{}")))
        assertEquals(OpenAIErrorCode.MODEL_DISCOVERY_UNSUPPORTED, discoveryCode(FakeResponse(404, "")))
        assertEquals(OpenAIErrorCode.MODEL_DISCOVERY_UNSUPPORTED, discoveryCode(FakeResponse(405, "")))
        assertEquals(OpenAIErrorCode.MODEL_DISCOVERY_UNSUPPORTED, discoveryCode(FakeResponse(501, "")))
        assertEquals(OpenAIErrorCode.ENDPOINT_LOADING, discoveryCode(FakeResponse(503, "loading model")))
        assertEquals(OpenAIErrorCode.ENDPOINT_ERROR, discoveryCode(FakeResponse(500, "boom")))
        assertEquals(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, discoveryCode(FakeResponse(200, "<html>")))
        val unreachable = OpenAIException(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "refused")
        assertEquals(OpenAIErrorCode.ENDPOINT_UNREACHABLE, discoveryCode(FakeResponse(failure = unreachable)))
    }

    @Test
    fun emptyModelListIsSuccess() {
        val client = OpenAIClient(FakeTransport { FakeResponse(200, """{"data":[]}""") })
        assertTrue(runBlocking { client.listModels(base, null) }.isEmpty())
    }

    @Test
    fun authorizationHeaderOnlyWithKey() {
        val transport = FakeTransport { FakeResponse(200, Fixtures.MODELS_JSON) }
        val client = OpenAIClient(transport)
        runBlocking {
            client.listModels(base, null)
            client.listModels(base, "")
            client.listModels(base, "sk-1")
        }
        assertFalse(transport.requests[0].headers.containsKey("Authorization"))
        assertFalse(transport.requests[1].headers.containsKey("Authorization"))
        assertEquals("Bearer sk-1", transport.requests[2].headers["Authorization"])
        assertEquals("http://studio.local:1234/v1/models", transport.requests[0].url)
        assertEquals(TransportTimeouts.PROBE, transport.requests[0].timeouts)
    }

    @Test
    fun chatStreamsSseInRandomChunks() {
        val stream =
            Fixtures.sse(
                """{"choices":[{"delta":{"reasoning_content":"r"}}]}""",
                Fixtures.contentFrame("Grüß "),
                Fixtures.contentFrame("dich 👋"),
                """{"choices":[{"delta":{},"finish_reason":"stop"}]}""",
            )
        val transport =
            FakeTransport {
                FakeResponse(200, contentType = "text/event-stream", body = stream.toByteArray(Charsets.UTF_8))
            }
        val payload = JsonObject(mapOf("model" to JsonPrimitive("m"), "messages" to JsonArray(emptyList())))
        val result = runBlocking { OpenAIClient(transport).chat(base, "k", payload, stream = true) }
        assertEquals("Grüß dich 👋", result.content)
        assertEquals("r", result.reasoning)
        val request = transport.requests.single()
        assertEquals("POST", request.method)
        assertEquals("http://studio.local:1234/v1/chat/completions", request.url)
        assertEquals("text/event-stream", request.headers["Accept"])
        assertEquals("application/json", request.headers["Content-Type"])
        assertEquals(TransportTimeouts.CHAT, request.timeouts)
    }

    @Test
    fun chatAcceptsJsonWhenServerIgnoresStream() {
        val body = """{"choices":[{"message":{"content":"plain"},"finish_reason":"stop"}]}"""
        val transport = FakeTransport { FakeResponse(200, body) }
        val result = runBlocking { OpenAIClient(transport).chat(base, null, JsonObject(emptyMap()), stream = true) }
        assertEquals("plain", result.content)
    }

    @Test
    fun chatErrorsMapToContractCodesWithRedaction() {
        fun code(
            status: Int,
            body: String,
            tools: Boolean = false,
        ): OpenAIException = OpenAIClient.chatError(TransportResponse(status, null, body), "sk-zz", tools)
        assertEquals(OpenAIErrorCode.ENDPOINT_AUTH_FAILED, code(401, "").code)
        assertEquals(OpenAIErrorCode.ENDPOINT_LOADING, code(503, "").code)
        assertEquals(OpenAIErrorCode.MODEL_NOT_AVAILABLE, code(404, """{"error":{"message":"model 'x' not found"}}""").code)
        assertEquals(OpenAIErrorCode.TOOLS_NOT_SUPPORTED, code(400, "tools are not supported", tools = true).code)
        assertEquals(OpenAIErrorCode.ENDPOINT_ERROR, code(400, "tools are not supported", tools = false).code)
        val redacted = code(500, "key sk-zz " + "y".repeat(400))
        assertFalse(redacted.message.contains("sk-zz"))
        assertTrue(redacted.message.length <= ServerErrorText.MAX_LENGTH + "HTTP 500: ".length)
        assertEquals(500, redacted.httpStatus)
    }

    @Test
    fun redirectPolicyAllowsOnlySameOrigin() {
        assertEquals("http://h:8080/v2/models", RedirectPolicy.resolveSameOrigin("http://h:8080/v1/models", "/v2/models"))
        assertEquals("http://H/v1/x", RedirectPolicy.resolveSameOrigin("http://h:80/v1/models", "http://H/v1/x"))
        assertNull(RedirectPolicy.resolveSameOrigin("http://h:8080/v1/models", "http://h:8081/v1/models"))
        assertNull(RedirectPolicy.resolveSameOrigin("http://h/v1/models", "https://h/v1/models"))
        assertNull(RedirectPolicy.resolveSameOrigin("http://h/v1/models", "http://evil.example/v1/models"))
        assertNull(RedirectPolicy.resolveSameOrigin("http://h/v1/models", "//evil.example/x"))
    }
}
