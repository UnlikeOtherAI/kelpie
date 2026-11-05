package com.kelpie.browser.ai.openai

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.coroutines.CoroutineContext

class OpenAIInferenceLifecycleTest {
    @Test
    fun cancelledScopeNeverStartsTransport() =
        runBlocking {
            val parent = SupervisorJob().apply { cancel() }
            val transport = FakeTransport { error("Cancelled inference must not reach transport") }
            val service = OpenAIEndpointService(OpenAIEndpointStore(MapStorage(), MapSecrets()) { "id" }, OpenAIClient(transport), FakeBackend())
            val inference = OpenAIInference(service, CoroutineScope(parent + Dispatchers.Unconfined))
            val result = withTimeout(5_000) { infer(inference) }
            assertEquals(OpenAIErrorCode.INFERENCE_CANCELLED, (result["error"] as Map<*, *>)["code"])
            assertTrue(transport.requests.isEmpty())
            assertEquals(0, inference.cancelAll())
        }

    @Test
    fun cancellationBeforeQueuedWorkerStartsRetiresWithoutTransport() =
        runBlocking {
            val queued = CompletableDeferred<Runnable>()
            val dispatcher =
                object : CoroutineDispatcher() {
                    override fun dispatch(
                        context: CoroutineContext,
                        block: Runnable,
                    ) {
                        check(queued.complete(block)) { "Only one inference worker is expected" }
                    }
                }
            val transport = FakeTransport { error("Cancelled inference must not reach transport") }
            val service = OpenAIEndpointService(OpenAIEndpointStore(MapStorage(), MapSecrets()) { "id" }, OpenAIClient(transport), FakeBackend())
            val parent = SupervisorJob()
            val inference = OpenAIInference(service, CoroutineScope(parent + dispatcher))
            try {
                withTimeout(5_000) {
                    val result = async(start = CoroutineStart.UNDISPATCHED) { infer(inference) }
                    val worker = queued.await()
                    assertEquals(1, inference.cancelAll())
                    worker.run()
                    assertEquals(OpenAIErrorCode.INFERENCE_CANCELLED, (result.await()["error"] as Map<*, *>)["code"])
                    assertEquals(0, inference.cancelAll())
                    assertTrue(transport.requests.isEmpty())
                }
            } finally {
                parent.cancel()
            }
        }

    private suspend fun infer(inference: OpenAIInference) = inference.infer(InferRequest.fromBody(mapOf("prompt" to "x", "text" to "y")), { _, _ -> emptyMap() }) { null }
}
