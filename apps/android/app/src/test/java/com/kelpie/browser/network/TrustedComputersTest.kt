package com.kelpie.browser.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class TrustedComputersTest {
    @get:Rule
    val folder = TemporaryFolder()

    private fun request(
        source: String,
        extra: Map<String, List<String>> = emptyMap(),
    ) = ParsedRequest("POST", "/v1/browser-control", mapOf("host" to listOf("127.0.0.1:8420"), "content-type" to listOf("application/json")) + extra, false, source)

    @Test
    fun localhostNeedsNoTokenButBrowserRequestsStayBlocked() {
        val auth = AuthMiddleware(testPairingStore(folder.root.resolve("pairings.json")))
        assertTrue(auth.evaluate(request("127.0.0.1")) is AuthDecision.Authenticated)
        for (headers in listOf(mapOf("origin" to listOf("null")), mapOf("host" to listOf("evil.example")), mapOf("sec-fetch-site" to listOf("cross-site")))) {
            assertEquals(403, (auth.evaluate(request("127.0.0.1", headers)) as AuthDecision.Reject).status)
        }
        assertEquals(401, (auth.evaluate(request("192.0.2.10")) as AuthDecision.Reject).status)
    }

    @Test
    fun oneDecisionResolvesManualWaitersWithoutApprovingAccountChallenges() {
        val store = testPairingStore(folder.root.resolve("pairings.json"))
        val first = store.startPairing("same", "First", "192.0.2.10").request!!
        val second = store.startPairing("same", "Second", "192.0.2.10").request!!
        val account = store.startPairing("account", "Account", "192.0.2.10", "uoa").request!!
        assertNotEquals(first.requestId, second.requestId)
        assertEquals(1, store.visiblePending().size)
        assertNull(store.approve(account.requestId, persist = true))
        assertTrue(store.trustedComputers.list().isEmpty())
        assertNotNull(store.approve(first.requestId, persist = true))
        assertNotNull(store.takeIssuance(first.requestId, "192.0.2.10"))
        assertNotNull(store.takeIssuance(second.requestId, "192.0.2.10"))
        assertNotNull(store.pendingRequest(account.requestId))
        assertTrue(store.listPersistent().isEmpty())
        assertTrue(AuthMiddleware(store).evaluate(request("192.0.2.10")) is AuthDecision.Authenticated)
        assertTrue(store.revokeComputer("192.0.2.10"))
        assertEquals(401, (AuthMiddleware(store).evaluate(request("192.0.2.10")) as AuthDecision.Reject).status)
        assertTrue(AuthMiddleware(store).evaluate(request("127.0.0.1")) is AuthDecision.Authenticated)
    }

    @Test
    fun trustedPairingSkipsPromptAndIssuedTokenCannotMoveToAnotherIP() {
        val store = testPairingStore(folder.root.resolve("pairings.json"))
        store.trustedComputers.approve("192.0.2.10", "Computer")
        var prompts = 0
        val endpoints = PairEndpoints(store) { prompts++ }
        val start = endpoints.handlePairPost("{\"clientId\":\"new\"}", "192.0.2.10")
        assertEquals(false, start.json["approvalRequired"])
        assertEquals(0, prompts)
        val id = start.json["requestId"] as String
        assertEquals("not_found", endpoints.handlePairStatus(id, "192.0.2.11").json["status"])
        val token = endpoints.handlePairStatus(id, "192.0.2.10").json["token"] as String
        assertNull(store.validateBearer(token))
        assertEquals(401, (AuthMiddleware(store).evaluate(request("192.0.2.11", mapOf("authorization" to listOf("Bearer $token")))) as AuthDecision.Reject).status)
        assertFalse(store.trustedComputers.clientId("192.0.2.11") != null)
    }

    @Test
    fun clientIdCannotRevokeComputerPermissionAndBearerCanUseAnAlias() {
        val store = testPairingStore(folder.root.resolve("pairings.json"))
        store.trustedComputers.approve("192.0.2.11", "Other computer")
        val pending = store.startPairing("host:192.0.2.11", "Legacy", "192.0.2.10").request!!
        val token = store.approve(pending.requestId, persist = false)!!.first
        store.trustedComputers.approve("192.0.2.10", "Computer")
        val legacy = request("192.0.2.10", mapOf("host" to listOf("custom-alias.local"), "authorization" to listOf("Bearer $token")))
        assertEquals(AuthDecision.Authenticated("host:192.0.2.11"), AuthMiddleware(store).evaluate(legacy))
        assertTrue(store.revoke("host:192.0.2.11"))
        assertNotNull(store.trustedComputers.clientId("192.0.2.11"))
        assertNull(store.validateBearer(token))
    }

    @Test
    fun oneSourceCannotFillAnotherComputersQueueAndApprovalOverridesSuppression() {
        val store = testPairingStore(folder.root.resolve("pairings.json"))
        repeat(32) { assertNotNull(store.startPairing("client-$it", "Client", "192.0.2.10").request) }
        assertEquals(PairingStore.PairStartResult.RATE_LIMITED, store.startPairing("overflow", "Client", "192.0.2.10").result)
        val other = store.startPairing("other", "Other", "192.0.2.11").request!!
        store.deny(other.requestId)
        assertTrue(store.wasRecentlyDenied("::ffff:192.0.2.11"))
        store.trustedComputers.approve("192.0.2.11", "Approved elsewhere")
        assertNotNull(store.startPairing("new", "New", "192.0.2.11").request)
    }

    @Test
    fun computerRevocationPreservesIndependentAccountIssuance() {
        val store = testPairingStore(folder.root.resolve("pairings.json"))
        store.trustedComputers.approve("192.0.2.10", "Computer")
        val pending = store.startPairing("account", "Account", "192.0.2.10", "uoa").request!!
        assertNull(store.approve(pending.requestId, persist = true))
        val grant = PairingStore.AccountGrant("uoa", "verified-proof", pending.requestId, System.currentTimeMillis() + 60_000, "192.0.2.10")
        assertNotNull(store.approve(pending.requestId, persist = false, accountGrant = grant))
        assertTrue(store.revokeComputer("192.0.2.10"))
        assertNotNull(store.takeIssuance(pending.requestId, "192.0.2.10"))
    }
}
