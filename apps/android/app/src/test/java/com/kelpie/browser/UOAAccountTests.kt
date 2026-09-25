package com.kelpie.browser

import com.kelpie.browser.account.AccountBookmarks
import com.kelpie.browser.account.UOAAuthorization
import com.kelpie.browser.browser.Bookmark
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class UOAAccountTests {
    @Test fun pkceMatchesRfc7636AndCallbacksAreExact() {
        val auth = UOAAuthorization("state", "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        val reference = UOAAuthorization("state", "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", reference.challenge)
        val base = UOAAuthorization.CALLBACK
        assertEquals(true, auth.denied("$base?state=state&error=access_denied"))
        assertEquals("one", auth.code("$base?state=state&code=one"))
        listOf("$base?state=other&code=one", "$base?state=state&code=one&code=two",
            "$base?state=state&state=state&code=one", "$base?state=state&code=one#fragment",
            "https://oauth/callback?state=state&code=one", "$base?state=state&error=denied&code=one").forEach {
            assertThrows(IllegalArgumentException::class.java) { auth.code(it) }
        }
    }

    @Test fun mutationsPreserveUnknownMetadataAndForeignEntries() {
        val existing = Json.parseToJsonElement("""[{"url":"https://one.example","name":"Other client","folder":{"id":"foreign"}},null,{"unknown":true}]""").jsonArray
        val bookmark = Bookmark(title = "New", url = "https://two.example")
        val updated = AccountBookmarks.apply(existing, AccountBookmarks.Mutation.Add(bookmark))
        assertEquals(existing[0], updated[0])
        assertEquals(existing[1], updated[1])
        assertEquals(existing[2], updated[2])
        assertEquals(2, AccountBookmarks.decode(updated).size)
        assertEquals(updated, AccountBookmarks.apply(updated, AccountBookmarks.Mutation.Add(bookmark)))
        val id = AccountBookmarks.decode(existing).single().id
        assertEquals(id, AccountBookmarks.decode(existing).single().id)
        assertEquals(3, AccountBookmarks.apply(updated, AccountBookmarks.Mutation.Remove(id)).size)
    }

    @Test fun conflictsRetryTheIntentAndRetainRemoteChanges() = kotlinx.coroutines.runBlocking {
        var puts = 0
        var published = emptyList<Bookmark>()
        var error: String? = null
        val sync = AccountBookmarks({ published = it }, { _, value -> error = value }, this) { _, method, body, version ->
            if (method == "PUT") {
                assertEquals("v2", version)
                puts++
                if (puts == 1) throw com.kelpie.browser.account.UOATransport.Failure(409)
                com.kelpie.browser.account.UOATransport.Response(body!!.toByteArray(), "v3")
            } else {
                val value = if (puts == 0) "[]" else "[{\"url\":\"https://remote.example\",\"folder\":\"Keep me\"}]"
                com.kelpie.browser.account.UOATransport.Response("{\"value\":$value}".toByteArray(), "v2")
            }
        }
        sync.enqueue(AccountBookmarks.Mutation.Add(Bookmark(title = "Added", url = "https://added.example")))
        sync.flush()
        assertEquals(2, puts)
        assertEquals(listOf("https://remote.example", "https://added.example"), published.map { it.url })
        assertEquals(null, error)
    }

    @Test fun invalidatedResponseCannotPublishAccountData() = kotlinx.coroutines.runBlocking {
        val started = kotlinx.coroutines.CompletableDeferred<Unit>()
        val release = kotlinx.coroutines.CompletableDeferred<Unit>()
        var publications = 0
        val sync = AccountBookmarks({ publications++ }, { _, _ -> }, this) { _, _, _, _ ->
            started.complete(Unit)
            kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) { release.await() }
            com.kelpie.browser.account.UOATransport.Response("{\"value\":[]}".toByteArray(), "v1")
        }
        sync.enqueue()
        started.await()
        sync.invalidate()
        release.complete(Unit)
        runCatching { sync.flush() }
        assertEquals(0, publications)
    }

    @Test fun aLaterSuccessfulSaveCannotHideAnEarlierFailure() = kotlinx.coroutines.runBlocking {
        kotlinx.coroutines.supervisorScope {
            var puts = 0
            val sync = AccountBookmarks({}, { _, _ -> }, this) { _, method, body, _ ->
                if (method == "PUT") {
                    puts++
                    if (puts == 1) throw com.kelpie.browser.account.UOATransport.Failure(503)
                    com.kelpie.browser.account.UOATransport.Response(body!!.toByteArray(), "v2")
                } else com.kelpie.browser.account.UOATransport.Response("{\"value\":[]}".toByteArray(), "v1")
            }
            val first = sync.enqueue(AccountBookmarks.Mutation.Clear)
            val second = sync.enqueue(AccountBookmarks.Mutation.Add(Bookmark(title = "Later", url = "https://later.example")))
            assertEquals(true, runCatching { first.await() }.isFailure)
            second.await()
            assertEquals(true, runCatching { first.await() }.isFailure)
        }
    }

    @Test fun legacyAppleDateIsNormalized() {
        val raw = Json.parseToJsonElement("""[{"url":"https://example.com","createdAt":0}]""").jsonArray
        assertEquals("2001-01-01T00:00:00Z", AccountBookmarks.decode(raw).single().createdAt)
    }
}
