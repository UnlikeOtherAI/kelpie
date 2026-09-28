package com.kelpie.browser

import com.kelpie.browser.account.UOACredentials
import com.kelpie.browser.account.UOASessionRejected
import com.kelpie.browser.account.UOASessionStorage
import com.kelpie.browser.account.UOAStoredSession
import com.kelpie.browser.account.UOATokenGrant
import com.kelpie.browser.account.UOATransport
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class UOASessionTests {
    private class MemoryStorage(
        var session: UOAStoredSession? = null,
    ) : UOASessionStorage {
        override fun load() = session

        override fun save(session: UOAStoredSession) {
            this.session = session
        }

        override fun clear() {
            session = null
        }
    }

    /** Scripted UOA: each `/oauth/token` call consumes the next reply, optionally after a gate opens. */
    private class FakeUOA {
        val tokenReplies = ArrayDeque<() -> String>()
        var tokenGate: CompletableDeferred<Unit>? = null
        val calls = mutableListOf<Pair<String, JsonObject>>()

        fun calls(path: String) = calls.filter { it.first == path }.map { it.second }

        @Suppress("UNUSED_PARAMETER")
        suspend fun request(
            path: String,
            method: String,
            token: String?,
            body: String?,
            version: String?,
        ): UOATransport.Response {
            calls += path to (body?.let { Json.parseToJsonElement(it).jsonObject } ?: JsonObject(emptyMap()))
            return when (path) {
                "/oauth/token" -> {
                    tokenGate?.await()
                    UOATransport.Response(tokenReplies.removeFirst()().toByteArray(), null)
                }
                "/oauth/revoke" -> throw UOATransport.Failure(404)
                else -> throw UOATransport.Failure(503)
            }
        }
    }

    private val stored = UOAStoredSession("client-1", "refresh-1")

    private fun grant(
        access: String,
        refresh: String?,
        expiresIn: Long = 1800,
    ): () -> String =
        {
            val refreshField = refresh?.let { ""","refresh_token":"$it"""" }.orEmpty()
            """{"access_token":"$access","token_type":"Bearer","expires_in":$expiresIn$refreshField}"""
        }

    private fun JsonObject.text(key: String) = get(key)?.jsonPrimitive?.content

    @Test fun storedSessionHoldsOnlyTheClientAndRefreshToken() {
        val encoded = Json.parseToJsonElement(stored.encode()).jsonObject
        assertEquals(setOf("client_id", "refresh_token"), encoded.keys)
        assertEquals(stored, UOAStoredSession.decode(stored.encode()))
        assertNull(UOAStoredSession.decode("""{"client_id":"","refresh_token":"x"}"""))
        assertNull(UOAStoredSession.decode("not json"))
    }

    @Test fun resumeRotatesTheStoredSessionAndPersistsTheSuccessor() =
        runBlocking {
            val server = FakeUOA().apply { tokenReplies += grant("access-1", "refresh-2") }
            val storage = MemoryStorage(stored)
            val tokens = UOACredentials(storage, server::request)
            assertEquals(UOACredentials.Resume.RESTORED, tokens.resume())
            val refresh = server.calls("/oauth/token").single()
            assertEquals("refresh_token", refresh.text("grant_type"))
            assertEquals("refresh-1", refresh.text("refresh_token"))
            assertEquals("client-1", refresh.text("client_id"))
            assertEquals(UOAStoredSession("client-1", "refresh-2"), storage.session)
            assertEquals("access-1", tokens.validToken(tokens.generation))
        }

    @Test fun rejectedResumeForgetsTheSession() =
        runBlocking {
            val server = FakeUOA().apply { tokenReplies += { throw UOATransport.Failure(400) } }
            val storage = MemoryStorage(stored)
            assertEquals(UOACredentials.Resume.REJECTED, UOACredentials(storage, server::request).resume())
            assertNull(storage.session)
        }

    @Test fun resumeFailingInTransitKeepsTheSession() =
        runBlocking {
            val server =
                FakeUOA().apply {
                    tokenReplies += { throw java.io.IOException("offline") }
                    tokenReplies += { throw UOATransport.Failure(503) }
                    tokenReplies += { "{not json" }
                }
            val storage = MemoryStorage(stored)
            val tokens = UOACredentials(storage, server::request)
            repeat(3) { assertEquals(UOACredentials.Resume.UNAVAILABLE, tokens.resume()) }
            assertEquals(stored, storage.session)
        }

    @Test fun nearlyExpiredTokenIsRefreshedOnceForConcurrentCallers() =
        runBlocking {
            var now = 1_000_000L
            val gate = CompletableDeferred<Unit>()
            val server =
                FakeUOA().apply {
                    tokenReplies += grant("access-2", "refresh-2")
                    tokenGate = gate
                }
            val storage = MemoryStorage()
            val tokens = UOACredentials(storage, server::request) { now }
            tokens.accept(UOATokenGrant("access-1", 1800, "refresh-1"), "client-1")
            now += 1_750_000L
            val first = async { tokens.validToken(tokens.generation) }
            val second = async { tokens.validToken(tokens.generation) }
            yield()
            gate.complete(Unit)
            assertEquals("access-2", first.await())
            assertEquals("access-2", second.await())
            assertEquals(1, server.calls("/oauth/token").size)
            assertEquals("refresh-2", storage.session?.refreshToken)
        }

    @Test fun serverWithoutRefreshTokensKeepsTheSessionInMemoryOnly() =
        runBlocking {
            val server = FakeUOA().apply { tokenReplies += grant("access-1", null) }
            val storage = MemoryStorage(stored)
            val tokens = UOACredentials(storage, server::request)
            assertEquals(UOACredentials.Resume.RESTORED, tokens.resume())
            assertNull(storage.session)
            assertEquals(false, tokens.persistent)
            val rejected = runCatching { tokens.refresh("access-1", tokens.generation) }.exceptionOrNull()
            assertEquals(true, rejected is UOASessionRejected)
        }

    @Test fun refreshFinishingAfterResetNeverWritesStorage() =
        runBlocking {
            val gate = CompletableDeferred<Unit>()
            val server =
                FakeUOA().apply {
                    tokenReplies += grant("access-1", "refresh-2")
                    tokenGate = gate
                }
            val storage = MemoryStorage(stored)
            val tokens = UOACredentials(storage, server::request)
            val pending = async { runCatching { tokens.resume() } }
            yield()
            assertEquals(stored, tokens.reset(clearStorage = true))
            gate.complete(Unit)
            assertEquals(true, pending.await().exceptionOrNull() is CancellationException)
            assertNull(storage.session)
            assertEquals(false, tokens.active)
        }

    @Test fun revokeSendsTheDroppedSessionAndIgnoresFailures() =
        runBlocking {
            val server = FakeUOA()
            UOACredentials(MemoryStorage(), server::request).revoke(stored)
            val revoke = server.calls("/oauth/revoke").single()
            assertEquals("refresh-1", revoke.text("token"))
            assertEquals("client-1", revoke.text("client_id"))
        }
}
