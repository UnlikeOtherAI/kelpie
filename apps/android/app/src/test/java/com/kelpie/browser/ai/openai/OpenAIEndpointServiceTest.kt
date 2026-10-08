package com.kelpie.browser.ai.openai

import com.kelpie.browser.ai.AIBackendInfer
import com.kelpie.browser.ai.AIInferDispatch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class OpenAIEndpointServiceTest {
    private val storage = MapStorage()
    private val secrets = MapSecrets()
    private val backend = FakeBackend()
    private var nextId = 0
    private val store = OpenAIEndpointStore(storage, secrets) { "id${++nextId}" }
    private var respond: (TransportRequest) -> FakeResponse = { FakeResponse(200, Fixtures.MODELS_JSON) }
    private val transport = FakeTransport { respond(it) }
    private val service = OpenAIEndpointService(store, OpenAIClient(transport), backend)
    private val handler =
        OpenAIEndpointsHandler(
            runtime = {
                OpenAIRuntimeParts(
                    service,
                    OpenAIInference(service, CoroutineScope(SupervisorJob() + Dispatchers.Default)),
                    EndpointTester(service),
                    HealthMonitor(service, CoroutineScope(SupervisorJob() + Dispatchers.Default)),
                )
            },
            agentTools =
                object : AgentToolBridge {
                    override suspend fun pinnedDispatcher(tabId: String?) = ToolDispatcher { _, _ -> mapOf("success" to true) }

                    override suspend fun pageContext(mode: String): String = "page text"
                },
        )

    private fun save(
        apiKey: String? = null,
        model: String? = "qwen3-q4",
        toolCalling: Boolean? = null,
    ) = service.save(
        EndpointSaveInput(
            name = "Strata",
            baseURL = "http://127.0.0.1:18880/v1/",
            apiKey = apiKey,
            model = Patch(model),
            toolCalling = toolCalling?.let { Patch(it) },
        ),
    )

    @Test
    fun saveDoesNotConnectAndNeverExposesKey() {
        val endpoint = save(apiKey = "sk-hidden")
        assertTrue(transport.requests.isEmpty())
        assertEquals("http://127.0.0.1:18880/v1", endpoint.baseURL)
        assertEquals("sk-hidden", secrets.values["openai-endpoint.id1.apiKey"])
        val listing = OpenAIJson.encode(OpenAIJson.fromAny(service.listPublic()))
        assertFalse(listing.contains("sk-hidden"))
        assertFalse(storage.values.values.any { it.contains("sk-hidden") })
        val public = service.endpointPublic(endpoint)
        assertEquals(true, public["hasApiKey"])
        assertEquals(true, public["loopback"])
        val host = service.listPublic()["executionHost"] as Map<*, *>
        assertEquals("android", host["platform"])
        assertTrue((host["loopbackMeans"] as String).contains("this phone"))
        assertTrue(storage.values.containsKey(OpenAIEndpointStore.ENDPOINTS_KEY))
    }

    @Test
    fun saveRejectsInvalidURLAndClearsKeyAndOverrides() {
        try {
            service.save(EndpointSaveInput(name = "x", baseURL = "ftp://nope"))
            fail("expected invalid url")
        } catch (e: OpenAIException) {
            assertEquals(OpenAIErrorCode.INVALID_ENDPOINT_URL, e.code)
        }
        val endpoint = save(apiKey = "sk-1", toolCalling = true)
        assertEquals("user", endpoint.toolCalling.source)
        val cleared =
            service.save(
                EndpointSaveInput(id = endpoint.id, name = "Strata", baseURL = endpoint.baseURL, clearApiKey = true, toolCalling = Patch(null)),
            )
        assertFalse(store.hasApiKey(cleared.id))
        assertNull(cleared.toolCalling.value)
        assertEquals("qwen3-q4", cleared.model)
    }

    @Test
    fun discoveryCachesModelsAndCapabilitiesFromServer() {
        val endpoint = save()
        val result = runBlocking { service.discover(endpoint.id) }
        assertEquals(listOf("qwen3-q4", "other"), result.models.map { it.id })
        val stored = store.get(endpoint.id)!!
        assertEquals(131072, stored.contextWindow.value)
        assertEquals("server", stored.contextWindow.source)
        assertEquals(HealthState.READY, service.healthOf(endpoint.id).state)
    }

    @Test
    fun emptyDiscoveryWarns() {
        respond = { FakeResponse(200, """{"data":[]}""") }
        val result = runBlocking { service.discover(save().id) }
        assertTrue(result.models.isEmpty())
        assertEquals("The server returned no models.", result.warning)
    }

    @Test
    fun loadFailsOnUnreachableWithoutChangingBackend() {
        backend.backend = "ollama"
        val endpoint = save()
        respond = { FakeResponse(failure = OpenAIException(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "refused")) }
        val result = runBlocking { handler.load(mapOf("backend" to "openai", "endpoint" to "strata")) }
        assertEquals(false, result["success"])
        assertEquals(OpenAIErrorCode.ENDPOINT_UNREACHABLE, (result["error"] as Map<*, *>)["code"])
        assertEquals("ollama", backend.backend)
        assertNull(store.active())
        respond = { FakeResponse(401, "{}") }
        val auth = runBlocking { service.runCatching { activate(endpoint.id, null) } }
        assertEquals(OpenAIErrorCode.ENDPOINT_AUTH_FAILED, (auth.exceptionOrNull() as OpenAIException).code)
        assertEquals("ollama", backend.backend)
    }

    @Test
    fun loadSelectsEndpointAndRemovingActiveUnloads() {
        val endpoint = save()
        val result = runBlocking { handler.load(mapOf("backend" to "openai", "endpoint" to endpoint.id, "model" to "other")) }
        assertEquals(true, result["success"])
        assertEquals("openai", backend.backend)
        assertEquals(ActiveSelection(endpoint.id, "other"), store.active())
        assertEquals("other", store.get(endpoint.id)!!.model)
        val status = handler.status()
        assertEquals("openai", status["backend"])
        assertEquals(endpoint.id, (status["endpoint"] as Map<*, *>)["id"])
        assertTrue(service.remove(endpoint.id))
        assertEquals("platform", backend.backend)
        assertNull(store.active())
    }

    @Test
    fun agentRequiresVerifiedToolCalling() {
        val endpoint = save()
        runBlocking { service.activate(endpoint.id, null) }
        val requestsBefore = transport.requests.size
        val result = runBlocking { handler.infer(mapOf("prompt" to "What is on the page?")) }
        assertEquals(OpenAIErrorCode.TOOLS_UNVERIFIED, (result["error"] as Map<*, *>)["code"])
        assertEquals(requestsBefore, transport.requests.size)
    }

    @Test
    fun toolTestRecordsEvidenceForModel() {
        val endpoint = save()
        respond = { request ->
            if (request.url.endsWith("/models")) {
                FakeResponse(200, Fixtures.MODELS_JSON)
            } else {
                val body = String(request.body!!)
                if (body.contains("\"tools\"")) {
                    FakeResponse(
                        200,
                        """{"choices":[{"message":{"tool_calls":[{"id":"t","function":{"name":"get_current_url","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}""",
                    )
                } else {
                    FakeResponse(200, """{"choices":[{"message":{"content":"ready"},"finish_reason":"stop"}]}""")
                }
            }
        }
        val result = runBlocking { EndpointTester(service).test(endpoint.id, null, generate = true, tools = true) }
        assertEquals(true, (result["generation"] as Map<*, *>)["ok"])
        assertEquals("ready", (result["generation"] as Map<*, *>)["text"])
        assertEquals(true, (result["toolCalling"] as Map<*, *>)["ok"])
        val stored = store.get(endpoint.id)!!
        assertEquals(true, stored.toolCalling.value)
        assertEquals("test", stored.toolCalling.source)
        assertNull(stored.copy(model = "other").toolCalling.value)
    }

    @Test
    fun plainInferenceStreamsAndReportsEndpoint() {
        val endpoint = save()
        runBlocking { service.activate(endpoint.id, null) }
        respond = {
            val stream =
                Fixtures.sse("""{"choices":[{"delta":{"reasoning_content":"hm"}}]}""", Fixtures.contentFrame("Answer"), """{"choices":[{"delta":{},"finish_reason":"stop"}]}""")
            FakeResponse(200, contentType = "text/event-stream", body = stream.toByteArray())
        }
        val result = runBlocking { handler.infer(mapOf("prompt" to "Summarise", "context" to "page_text")) }
        assertEquals(true, result["success"])
        assertEquals("Answer", result["response"])
        assertEquals("hm", result["reasoning"])
        assertEquals("stop", result["finishReason"])
        assertEquals(endpoint.id, result["endpointId"])
        assertEquals("qwen3-q4", result["model"])
        val sent = String(transport.requests.last().body!!)
        assertTrue(sent.contains("page text"))
        assertTrue(sent.contains("\"stream\":true"))
    }

    @Test
    fun visionNotSentUnlessEnabled() {
        val endpoint = save()
        runBlocking { service.activate(endpoint.id, null) }
        val before = transport.requests.size
        val result = runBlocking { handler.infer(mapOf("prompt" to "x", "text" to "y", "image" to "aGk=")) }
        assertEquals(OpenAIErrorCode.VISION_NOT_SUPPORTED, (result["error"] as Map<*, *>)["code"])
        assertEquals(before, transport.requests.size)
    }

    @Test
    fun cancelReturnsInferenceCancelled() {
        val endpoint = save()
        runBlocking { service.activate(endpoint.id, null) }
        val hanging = FakeTransport { FakeResponse(hang = true) }
        val hangingService = OpenAIEndpointService(store, OpenAIClient(hanging), backend)
        val inference = OpenAIInference(hangingService, CoroutineScope(SupervisorJob() + Dispatchers.Default))
        runBlocking {
            val pending =
                async(Dispatchers.Default) {
                    inference.infer(InferRequest.fromBody(mapOf("prompt" to "x", "text" to "y")), { _, _ -> emptyMap() }) { null }
                }
            withTimeout(5_000) { hanging.started.await() }
            assertEquals(1, inference.cancelAll())
            val result = withTimeout(5_000) { pending.await() }
            assertEquals(OpenAIErrorCode.INFERENCE_CANCELLED, (result["error"] as Map<*, *>)["code"])
        }
        assertTrue(hanging.cancelled)
        assertEquals(0, hangingService.inFlightCount(endpoint.id))
    }

    @Test
    fun openAIFailureNeverFallsBackToAnotherBackend() {
        val endpoint = save()
        runBlocking { service.activate(endpoint.id, null) }
        respond = { FakeResponse(failure = OpenAIException(OpenAIErrorCode.ENDPOINT_UNREACHABLE, "gone")) }
        var otherBackendCalls = 0
        val dispatch =
            AIInferDispatch(
                mapOf<String, AIBackendInfer>(
                    "platform" to { _ ->
                        otherBackendCalls++
                        mapOf("success" to true)
                    },
                    "ollama" to { _ ->
                        otherBackendCalls++
                        mapOf("success" to true)
                    },
                    "openai" to { body -> handler.infer(body) },
                ),
            )
        val result = runBlocking { dispatch.infer(backend.currentBackend(), mapOf("prompt" to "x", "text" to "y")) }
        assertEquals(false, result["success"])
        assertEquals(OpenAIErrorCode.ENDPOINT_UNREACHABLE, (result["error"] as Map<*, *>)["code"])
        assertEquals(0, otherBackendCalls)
        assertEquals("openai", backend.backend)
        assertEquals(endpoint.id, store.active()?.endpointId)
        assertEquals(HealthState.UNREACHABLE, service.healthOf(endpoint.id).state)
    }

    private fun toolCallStream(name: String) =
        Fixtures.sse(
            """{"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"$name","arguments":"{}"}}]}}]}""",
            """{"choices":[{"delta":{},"finish_reason":"tool_calls"}]}""",
        )

    private fun sseResponse(stream: String) = FakeResponse(200, contentType = "text/event-stream", body = stream.toByteArray())

    @Test
    fun agentInferenceReportsTasksCompletionAndStopReason() {
        val endpoint = save(toolCalling = true)
        runBlocking { service.activate(endpoint.id, null) }
        var chats = 0
        respond = { request ->
            if (request.url.endsWith("/models")) {
                FakeResponse(200, Fixtures.MODELS_JSON)
            } else {
                when (chats++) {
                    0 -> sseResponse(toolCallStream("get_current_url"))
                    else -> sseResponse(Fixtures.sse(Fixtures.contentFrame("Example"), """{"choices":[{"delta":{},"finish_reason":"stop"}]}"""))
                }
            }
        }
        val result = runBlocking { handler.infer(mapOf("prompt" to "Which page?", "maxSteps" to 5)) }
        assertEquals(true, result["success"])
        assertEquals("Example", result["response"])
        assertEquals(true, result["completed"])
        assertEquals("answered", result["stopReason"])
        assertEquals(emptyList<Any>(), result["tasks"])
        assertEquals(1, (result["steps"] as List<*>).size)
        assertEquals("openai", result["backend"])
        val sent = String(transport.requests.last().body!!)
        assertTrue(sent.contains("update_task_list"))
        assertTrue(sent.contains("\"max_tokens\":4096"))
    }

    @Test
    fun agentErrorAfterStepsStillReportsSteps() {
        val endpoint = save(toolCalling = true)
        runBlocking { service.activate(endpoint.id, null) }
        var chats = 0
        respond = { request ->
            when {
                request.url.endsWith("/models") -> FakeResponse(200, Fixtures.MODELS_JSON)
                chats++ == 0 -> sseResponse(toolCallStream("get_page_text"))
                else -> FakeResponse(500, """{"error":{"message":"kaboom"}}""")
            }
        }
        val result = runBlocking { handler.infer(mapOf("prompt" to "Read it")) }
        assertEquals(false, result["success"])
        assertEquals(OpenAIErrorCode.ENDPOINT_ERROR, (result["error"] as Map<*, *>)["code"])
        assertEquals("get_page_text", ((result["steps"] as List<*>).single() as Map<*, *>)["tool"])
    }
}
