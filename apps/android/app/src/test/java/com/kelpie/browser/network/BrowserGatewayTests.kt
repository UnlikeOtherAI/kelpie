package com.kelpie.browser.network

import com.kelpie.browser.ai.openai.OpenAIJson
import com.kelpie.browser.nativecore.BrowserGatewayAbi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class BrowserGatewayTests {
    @get:Rule val folder = TemporaryFolder()

    private class Abi : BrowserGatewayAbi {
        var phase = 0
        var begins = 0
        var cancels = 0
        var destroyed = 0
        var invalidated = 0

        override fun create(config: String) = 1L

        override fun destroy(handle: Long) {
            destroyed++
        }

        override fun begin(
            handle: Long,
            request: String,
            mcp: Boolean,
        ): String {
            begins++
            phase = 0
            return """{"kind":"authorize","request":{"version":1,"method":"tab.click"},"mutates":true}"""
        }

        override fun advance(
            handle: Long,
            result: String,
        ): String {
            val success = OpenAIJson.toMap(OpenAIJson.parseObjectOrNull(result)!!)["success"] == true
            if (phase++ == 0 && success) return """{"kind":"dispatch","method":"click","params":{},"mutates":true}"""
            return """{"kind":"complete","response":{"version":1,"ok":$success,"value":null}}"""
        }

        override fun cancel(handle: Long): String {
            cancels++
            return """{"kind":"complete","response":{"version":1,"ok":false,"error":{"code":"CANCELLED","mayHaveCompleted":true}}}"""
        }

        override fun invalidate(
            handle: Long,
            tab: String?,
        ) {
            invalidated++
        }
    }

    @Test fun deniesBothUnauthenticatedRoutesAndAcceptsOnlyIssuedBearer() {
        val store = PairingStore(folder.root.resolve("pairings.json"))
        val auth = AuthMiddleware(store)
        for (path in listOf("/v1/browser-control", "/mcp")) {
            val request = ParsedRequest("POST", path, emptyMap(), false, "127.0.0.1")
            assertEquals(401, (auth.evaluate(request) as AuthDecision.Reject).status)
            val pending = store.startPairing("gateway-$path", "Gateway test", "127.0.0.1").request!!
            val token = store.approve(pending.requestId, persist = false)!!.first
            assertTrue(auth.evaluate(request.copy(headers = mapOf("authorization" to listOf("Bearer $token")))) is AuthDecision.Authenticated)
            assertEquals(400, (auth.evaluate(request.copy(headers = mapOf("authorization" to listOf("Bearer $token", "Bearer $token")))) as AuthDecision.Reject).status)
            if (path == "/mcp") {
                val authorized = request.copy(headers = mapOf("authorization" to listOf("Bearer $token")))
                assertEquals(403, (auth.evaluate(authorized.copy(headers = authorized.headers + ("origin" to listOf("null")))) as AuthDecision.Reject).status)
                assertEquals(400, (auth.evaluate(authorized.copy(headers = authorized.headers + ("mcp-protocol-version" to listOf("unsupported")))) as AuthDecision.Reject).status)
                assertTrue(auth.evaluate(authorized.copy(headers = authorized.headers + ("mcp-protocol-version" to listOf("2025-06-18")))) is AuthDecision.Authenticated)
            }
        }
    }

    @Test fun runScopeRejectsActionsCrossTabAndNestedExtensionTargets() {
        fun permits(
            request: Map<String, Any?>,
            mutates: Boolean = false,
            active: String = "one",
        ) = BrowserGatewayTabPolicy.permits(request, mutates, false, "one", active, setOf("one", "two"))
        assertTrue(permits(mapOf("tabId" to "one")))
        assertFalse(permits(emptyMap(), mutates = true))
        assertFalse(permits(emptyMap(), active = "two"))
        assertFalse(permits(mapOf("tabId" to "two")))
        assertFalse(permits(mapOf("params" to mapOf("tabId" to "two"))))
        assertFalse(BrowserGatewayTabPolicy.permits(mapOf("params" to mapOf("tabId" to "missing")), false, true, null, "one", setOf("one")))
    }

    @Test fun directTargetCannotFollowHumanSwitchBetweenInspectionAndDispatch() {
        val target = mapOf<String, Any?>("tabId" to "one")
        assertTrue(BrowserGatewayTabPolicy.permitsDispatch("browser-control-evaluate", target, null, "one"))
        assertFalse(BrowserGatewayTabPolicy.permitsDispatch("browser-control-evaluate", target, null, "two"))
        assertFalse(BrowserGatewayTabPolicy.permitsDispatch("navigate", target, null, "two"))
        assertTrue(BrowserGatewayTabPolicy.permitsDispatch("switch-tab", target, null, "two"))
        assertFalse(BrowserGatewayTabPolicy.permitsDispatch("switch-tab", target, "one", "two"))
    }

    @Test fun dispatchKeepsCapturedRendererAndRefusesResultAfterHumanSwitch() =
        runBlocking {
            var active = "one"
            var visible = "view-one"
            val boundary = BrowserGatewayDispatch({ active }, { visible })
            val admitted = CompletableDeferred<Unit>()
            val finish = CompletableDeferred<Unit>()
            var touched: String? = null
            val call =
                async {
                    boundary.execute("navigate", mapOf("tabId" to "one"), null) { captured ->
                        admitted.complete(Unit)
                        finish.await()
                        touched = captured
                        mapOf("success" to true)
                    }
                }
            admitted.await()
            active = "two"
            visible = "view-two"
            finish.complete(Unit)
            assertEquals(false, call.await()["success"])
            assertEquals("view-one", touched)
            var invoked = false
            boundary.execute("browser-control-evaluate", mapOf("tabId" to "one"), null) {
                invoked = true
                emptyMap()
            }
            assertFalse(invoked)
            val noPage = BrowserGatewayDispatch<String>({ "0" }, { null })
            assertEquals(true, noPage.execute("get-device-info", emptyMap(), null) { mapOf("success" to (it == null)) }["success"])
        }

    @Test fun protocolFailureKeepsUncertaintyOnSuccessfulTransport() =
        runBlocking {
            val router = Router()
            val canonical = mapOf("version" to 1, "ok" to false, "error" to mapOf("code" to "CANCELLED", "mayHaveCompleted" to true))
            router.register("browser-control") { canonical }
            val response = router.handle("browser-control", emptyMap())
            assertEquals(200, response.first)
            assertEquals(true, (response.second["error"] as Map<*, *>)["mayHaveCompleted"])
            router.register("mcp") { mapOf("jsonrpc" to "2.0", "id" to 1, "error" to mapOf("code" to -32602)) }
            assertEquals(200, router.handle("mcp", emptyMap()).first)
        }

    @Test fun refusalNeverDispatchesAndClosureFreesOnce() =
        runBlocking {
            val abi = Abi()
            var dispatches = 0
            val session =
                BrowserGatewaySession(emptyMap(), Mutex(), { _, _ -> false }, { _, _ ->
                    dispatches++
                    emptyMap()
                }, abi)
            assertEquals(false, session.call(emptyMap())!!["ok"])
            assertEquals(0, dispatches)
            session.invalidateLocked()
            session.close()
            session.close()
            assertEquals(1, abi.invalidated)
            assertEquals(1, abi.destroyed)
        }

    @Test fun timeoutCancelsUncertainTransactionWithoutRepeatingAction() =
        runBlocking {
            val abi = Abi()
            var dispatches = 0
            val session =
                BrowserGatewaySession(emptyMap(), Mutex(), { _, _ -> true }, { _, _ ->
                    dispatches++
                    awaitCancellation()
                }, abi, 20)
            val response = session.call(emptyMap())!!
            assertEquals(true, (response["error"] as Map<*, *>)["mayHaveCompleted"])
            assertEquals(1, dispatches)
            assertEquals(1, abi.cancels)
            session.close()
        }

    @Test fun externalCancellationResetsNativeStateAndSerializesNextRequest() =
        runBlocking {
            val lock = Mutex()
            val abi = Abi()
            val started = CompletableDeferred<Unit>()
            var dispatches = 0
            val session =
                BrowserGatewaySession(emptyMap(), lock, { _, _ -> true }, { _, _ ->
                    if (++dispatches == 1) {
                        started.complete(Unit)
                        awaitCancellation()
                    }
                    mapOf("success" to true)
                }, abi)
            val first = launch { session.call(emptyMap()) }
            started.await()
            val second = async { session.call(emptyMap()) }
            assertEquals(1, abi.begins)
            first.cancelAndJoin()
            assertEquals(true, second.await()!!["ok"])
            assertEquals(1, abi.cancels)
            assertEquals(2, dispatches)
            session.close()
        }

    @Test fun timedOutRendererLeaseWaitsForCallbackThenAllowsExplicitReconciliation() = runBlocking {
        val lock = Mutex()
        val retirement = BrowserGatewayRetirement()
        val target = Any()
        lateinit var ticket: Any
        var dispatches = 0
        val session = BrowserGatewaySession(emptyMap(), lock, { _, _ -> true }, { _, _ ->
            if (++dispatches == 1) {
                ticket = retirement.start(target) {}
                awaitCancellation()
            }
            mapOf("success" to true)
        }, Abi(), 20, retirement = retirement)
        assertEquals(false, session.call(emptyMap())!!["ok"])
        val next = async { session.call(emptyMap()) }
        kotlinx.coroutines.delay(25)
        assertEquals(1, dispatches)
        assertFalse(next.isCompleted)
        retirement.complete(ticket)
        assertEquals(true, next.await()!!["ok"])
        assertEquals(2, dispatches)
        session.close()
    }

    @Test fun confirmedRendererTeardownRetiresLostCallbackWithoutPermanentLatch() = runBlocking {
        val retirement = BrowserGatewayRetirement()
        val target = Any()
        var cancelled = false
        retirement.start(target) { cancelled = true }
        val pending = retirement.waitForPending()!!
        retirement.retireTarget(target)
        assertTrue(cancelled)
        pending.await()
        assertEquals(null, retirement.waitForPending())
    }

    @Test fun cancelledLegacyRendererWorkKeepsSharedLeaseUntilCallback() = runBlocking {
        val lock = Mutex()
        val retirement = BrowserGatewayRetirement()
        val target = Any()
        lateinit var ticket: Any
        val started = CompletableDeferred<Unit>()
        val first = launch {
            withBrowserGatewayLease(lock, retirement) {
                ticket = retirement.start(target) {}
                started.complete(Unit)
                awaitCancellation()
            }
        }
        started.await()
        first.cancelAndJoin()
        val next = async { withBrowserGatewayLease(lock, retirement) { "reconciled" } }
        kotlinx.coroutines.delay(25)
        assertFalse(next.isCompleted)
        retirement.complete(ticket)
        assertEquals("reconciled", next.await())
    }

    @Test fun reentrantAdmissionUsesOnlyConfiguredExtensionMethods() {
        val descriptors = listOf(mapOf<String, Any?>("name" to "kelpie_ai_ask", "method" to "ai-infer"))
        fun permits(name: String, args: Map<String, Any?> = emptyMap()) = BrowserGatewayReentrant.permits(
            mapOf("method" to "tools/call", "params" to mapOf("name" to name, "arguments" to args)), descriptors, setOf("ai-infer"))
        assertTrue(permits("kelpie_ai_ask"))
        assertTrue(permits("kelpie_extension", mapOf("name" to "kelpie_ai_ask")))
        assertFalse(permits("ai-infer"))
        assertFalse(permits("kelpie_extension", mapOf("name" to "unknown")))
        assertFalse(BrowserGatewayReentrant.permits(mapOf("method" to "tools/list"), descriptors, setOf("ai-infer")))
    }

    @Test fun outerInferenceHandleAllowsNestedAndConcurrentBrowserTransactions() = runBlocking {
        val browserLock = Mutex()
        val started = CompletableDeferred<Unit>()
        val provider = CompletableDeferred<Unit>()
        val browser = BrowserGatewaySession(emptyMap(), browserLock, { _, _ -> true }, { _, _ -> mapOf("success" to true) }, Abi())
        val inference = BrowserGatewaySession(emptyMap(), Mutex(), { _, _ -> true }, { _, _ ->
            assertEquals(true, browser.call(emptyMap())!!["ok"])
            started.complete(Unit)
            provider.await()
            mapOf("success" to true)
        }, Abi(), dispatchTimeoutMs = null)
        val outer = async { inference.call(emptyMap(), mcp = true) }
        started.await()
        assertEquals(true, browser.call(emptyMap())!!["ok"])
        assertFalse(outer.isCompleted)
        provider.complete(Unit)
        assertEquals(true, outer.await()!!["ok"])
        inference.close()
        browser.close()
    }
}
