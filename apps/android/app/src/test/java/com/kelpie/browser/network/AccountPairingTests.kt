package com.kelpie.browser.network

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AccountPairingTests {
    @get:Rule val folder = TemporaryFolder()

    private fun store() = PairingStore(java.io.File(folder.newFolder(), "pairing.json"))

    private fun body(challenge: String? = null) =
        buildJsonObject {
            put("account", JsonPrimitive(true))
            put("clientId", JsonPrimitive("client"))
            put("clientName", JsonPrimitive("Client"))
            if (challenge != null) {
                put("requestId", JsonPrimitive(challenge))
                put("accountTicket", JsonPrimitive("proof"))
            }
        }.toString()

    private fun request(
        token: String,
        duplicate: Boolean = false,
    ) = ParsedRequest(
        "POST",
        "/v1/browser-control",
        mapOf("authorization" to if (duplicate) listOf("Bearer $token", "Bearer other") else listOf("Bearer $token")),
        false,
        "peer",
    )

    private suspend fun connect(auth: AccountPairingAuthorization): Pair<String, String> {
        val challenge = auth.handlePost(body(), "peer")
        assertEquals(202, challenge.status)
        val id = challenge.json["requestId"] as String
        val approved = auth.handlePost(body(id), "peer")
        assertEquals(200, approved.status)
        assertEquals("session", approved.json["scope"])
        return id to approved.json["token"] as String
    }

    @Test fun automaticAccessIsMemoryOnlyAndAlwaysRevalidated() =
        runBlocking {
            val store = store()
            var checks = 0
            val auth =
                AccountPairingAuthorization(store, { "session" }, { _, _, client, _ ->
                    checks++
                    assertEquals("client", client)
                    System.currentTimeMillis() + 60_000
                })
            val (_, token) = connect(auth)
            assertTrue(store.visiblePending().isEmpty())
            assertTrue(store.listPersistent().isEmpty())
            assertNull(store.validateBearer(token))
            assertEquals(AuthDecision.Authenticated("client"), auth.evaluate(request(token)))
            assertEquals(AuthDecision.Authenticated("client"), auth.evaluate(request(token)))
            assertEquals(3, checks)
            assertNull(store().accountApproval(token))
        }

    @Test fun uoaRevocationAndAccountChangesInvalidateAccess() =
        runBlocking {
            val store = store()
            var session: String? = "original"
            var active = true
            val auth =
                AccountPairingAuthorization(store, { session }, { _, _, _, _ ->
                    if (active) System.currentTimeMillis() + 60_000 else null
                })
            val (_, token) = connect(auth)
            active = false
            assertEquals(401, (auth.evaluate(request(token)) as AuthDecision.Reject).status)
            active = true
            for (next in listOf(null, "another-session")) {
                session = next
                assertEquals(401, (auth.evaluate(request(token)) as AuthDecision.Reject).status)
            }
        }

    @Test fun challengesCannotBeManuallyApprovedReplayedOrCollectedByAnotherPeer() =
        runBlocking {
            val store = store()
            val auth = AccountPairingAuthorization(store, { "session" }, { _, _, _, _ -> System.currentTimeMillis() + 60_000 })
            val challenge = auth.handlePost(body(), "peer").json["requestId"] as String
            assertTrue(store.visiblePending().isEmpty())
            assertNull(store.approve(challenge, true))
            assertEquals(403, auth.handlePost(body(challenge), "other-peer").status)
            assertEquals(200, auth.handlePost(body(challenge), "peer").status)
            assertEquals(403, auth.handlePost(body(challenge), "peer").status)
            assertNull(store.takeIssuance(challenge, "peer"))
            assertTrue(store.revoke("client"))
            assertEquals(403, auth.handlePost(body(), "peer").status)
        }

    @Test fun signOutDuringVerificationCannotIssueAccess() =
        runBlocking {
            val store = store()
            var session: String? = "original"
            val auth =
                AccountPairingAuthorization(store, { session }, { _, _, _, _ ->
                    session = null
                    System.currentTimeMillis() + 60_000
                })
            val challenge = auth.handlePost(body(), "peer").json["requestId"] as String
            assertEquals(403, auth.handlePost(body(challenge), "peer").status)
            assertTrue(store.listSessions().isEmpty())
        }

    @Test fun expiredAndOverlongProofsNeverIssueAccess() =
        runBlocking {
            for (offset in listOf(-1L, 121_000L)) {
                val store = store()
                val auth = AccountPairingAuthorization(store, { "session" }, { _, _, _, _ -> System.currentTimeMillis() + offset })
                val challenge = auth.handlePost(body(), "peer").json["requestId"] as String
                assertEquals(403, auth.handlePost(body(challenge), "peer").status)
                assertTrue(store.listSessions().isEmpty())
            }
        }

    @Test fun ambiguousHeadersAndMcpOriginRemainRejected() =
        runBlocking {
            val store = store()
            var checks = 0
            val auth =
                AccountPairingAuthorization(store, { "session" }, { _, _, _, _ ->
                    checks++
                    System.currentTimeMillis() + 60_000
                })
            val (_, token) = connect(auth)
            assertEquals(400, (auth.evaluate(request(token, true)) as AuthDecision.Reject).status)
            assertEquals(1, checks)
            val mcp = request(token).copy(path = "/mcp", headers = request(token).headers + ("origin" to listOf("null")))
            assertEquals(403, (auth.evaluate(mcp) as AuthDecision.Reject).status)
        }
}
