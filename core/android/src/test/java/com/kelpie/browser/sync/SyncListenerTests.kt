package com.kelpie.browser.sync

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Semaphore
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.net.InetAddress
import java.net.Socket
import java.security.SecureRandom

/** Admission on the real sync listener, driven with raw HTTP so every header is under test control. */
class SyncListenerTests {
    @get:Rule val folder = TemporaryFolder()

    private val uoa = FakeUOA()
    private val random = SecureRandom()
    private lateinit var responderRun: SyncRun
    private lateinit var initiatorRun: SyncRun
    private lateinit var listener: SyncListener
    private var port = 0

    private fun run(
        name: String,
        account: SyncAccount,
    ): SyncRun =
        runBlocking {
            val replica = SyncBase64.encode(ByteArray(16).also(random::nextBytes))
            val now = System.currentTimeMillis()
            val store = SyncStore.open(folder.newFolder(name), "alice", replica, launch = false, now = now)
            SyncRun(account.identity.value!!, store, MemoryCookies(), account, Semaphore(2), name, System::currentTimeMillis, random, SyncRun.Warmup(now, false, 0, 0))
        }

    @Before fun start() =
        runBlocking {
            responderRun = run("responder", uoa.account("alice"))
            initiatorRun = run("initiator", uoa.account("alice"))
            listener = SyncListener(SyncResponder(responderRun), SyncAddressRule { emptyList() }, System::currentTimeMillis)
            port = listener.start()
        }

    @After fun stop() =
        runBlocking {
            listener.stop()
            responderRun.store.close()
            initiatorRun.store.close()
        }

    private data class Raw(
        val status: Int,
        val headers: Map<String, String>,
        val body: String,
    )

    /** Sends [head] (request line + headers, CRLF-joined) and [body], reads one response. */
    private fun raw(
        head: List<String>,
        body: String = "",
    ): Raw =
        Socket(InetAddress.getLoopbackAddress(), port).use { socket ->
            socket.soTimeout = 15_000
            val out = socket.getOutputStream()
            out.write((head.joinToString("\r\n") + "\r\n\r\n" + body).toByteArray())
            out.flush()
            val reader = socket.getInputStream().bufferedReader()
            val status = reader.readLine().split(' ')[1].toInt()
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                headers[line.substringBefore(':').lowercase()] = line.substringAfter(':').trim()
            }
            val length = headers["content-length"]?.toIntOrNull() ?: 0
            val chars = CharArray(length)
            var read = 0
            while (read < length) {
                val count = reader.read(chars, read, length - read)
                if (count < 0) break
                read += count
            }
            Raw(status, headers, String(chars, 0, read))
        }

    private fun post(
        path: String,
        body: String,
        extra: List<String> = emptyList(),
        length: Int = body.toByteArray().size,
    ) = raw(listOf("POST $path HTTP/1.1", "Host: 127.0.0.1", "Content-Type: application/json", "Content-Length: $length") + extra, body)

    private fun hello(): String =
        buildJsonObject {
            put("v", 1)
            put("replica", initiatorRun.replica)
            put("hint", initiatorRun.hints().first)
            put("now", System.currentTimeMillis())
            put("platform", "android")
            put("name", "test")
            put("key", SyncCrypto.generateKeyPair(random).encodedPublicKey)
            put("nonce", SyncBase64.encode(ByteArray(32).also(random::nextBytes)))
        }.toString()

    @Test fun refusesBadMethodsPathsAndHeadersBeforeReadingBodies() {
        val get = raw(listOf("GET /v1/sync/hello HTTP/1.1", "Host: x"))
        assertEquals(405, get.status)
        assertEquals("no-store", get.headers["cache-control"])
        val unknown = post("/v1/sync/other", "{}")
        assertEquals(404, unknown.status)
        assertEquals("no-store", unknown.headers["cache-control"])
        assertEquals(403, post("/v1/sync/hello", hello(), listOf("Origin: https://evil.test")).status)
        assertEquals(415, raw(listOf("POST /v1/sync/hello HTTP/1.1", "Host: x", "Content-Type: text/plain", "Content-Length: 2"), "{}").status)
        assertEquals(411, raw(listOf("POST /v1/sync/hello HTTP/1.1", "Host: x", "Content-Type: application/json", "Connection: close"), "").status)
        // Oversized bodies and session-less exchanges are refused without sending a byte of body.
        assertEquals(413, post("/v1/sync/hello", "", length = 20_000).status)
        val exchange = post("/v1/sync/exchange", "", length = 1_000_000)
        assertEquals(401, exchange.status)
        assertTrue(exchange.body.contains("SYNC_SESSION"))
        assertEquals(413, post("/v1/sync/exchange", "", listOf("${SyncProtocol.SESSION_HEADER}: x"), length = 5 * 1024 * 1024).status)
    }

    @Test fun refusesChunkedAndDuplicateLengths() {
        val chunked = raw(listOf("POST /v1/sync/hello HTTP/1.1", "Host: x", "Content-Type: application/json", "Transfer-Encoding: chunked"), "2\r\n{}\r\n0\r\n\r\n")
        assertEquals(400, chunked.status)
        val duplicate = raw(listOf("POST /v1/sync/hello HTTP/1.1", "Host: x", "Content-Type: application/json", "Content-Length: 2", "Content-Length: 2"), "{}")
        assertEquals(400, duplicate.status)
    }

    @Test fun helloIsRateLimitedPerSource() {
        repeat(SyncProtocol.HELLO_PER_SOURCE_PER_MIN) { assertEquals(400, post("/v1/sync/hello", "{}").status) }
        assertEquals(429, post("/v1/sync/hello", "{}").status)
    }

    @Test fun helloChecksHintAndClock() {
        val reply = post("/v1/sync/hello", hello())
        assertEquals(200, reply.status)
        assertNull(SyncCore.invalid("hello-reply", SyncJson.parseObject(reply.body)!!))
        val wrongHint = hello().replace(initiatorRun.hints().first, SyncCore.hints("bob", System.currentTimeMillis()).first)
        assertEquals(409, post("/v1/sync/hello", wrongHint).status)
        val skewed = hello().replace(Regex("\"now\":\\d+"), "\"now\":${System.currentTimeMillis() - 3 * 60_000}")
        val refusal = post("/v1/sync/hello", skewed)
        assertEquals(409, refusal.status)
        assertTrue(refusal.body.contains("CLOCK_SKEW"))
    }

    @Test fun authIsSingleUseAndPendingHandshakesAreEvicted() {
        val first = SyncJson.parseObject(post("/v1/sync/hello", hello()).body)!!.string("handshakeId")!!
        val auth = { id: String ->
            post(
                "/v1/sync/auth",
                buildJsonObject {
                    put("handshakeId", id)
                    put("ticket", "forged")
                }.toString(),
            )
        }
        assertEquals(403, auth(first).status)
        assertEquals(401, auth(first).status)
        val ids = (1..SyncProtocol.MAX_PENDING + 1).map { SyncJson.parseObject(post("/v1/sync/hello", hello()).body)!!.string("handshakeId")!! }
        assertEquals(401, auth(ids.first()).status) // evicted by the ninth
        assertEquals(403, auth(ids.last()).status)
    }

    @Test fun exchangeRejectsReplaysAndForeignBoxes() =
        runBlocking {
            val initiator = SyncInitiator(initiatorRun, SyncHttpTransport())
            val target = PeerTarget(listOf(InetAddress.getLoopbackAddress()), port)
            val session = initiator.handshake(responderRun.replica, target)
            val pull =
                buildJsonObject {
                    put("op", "pull")
                    put("replica", initiatorRun.replica)
                    put(
                        "since",
                        buildJsonObject {
                            put("replica", responderRun.replica)
                            put("seq", 0)
                        },
                    )
                    put("wait", 0)
                }.toString()
            val box = SyncChannel.seal(session.keys.i2r, session.id, SyncChannel.REQUEST, 1, pull)
            val envelope =
                buildJsonObject {
                    put("seq", 1)
                    put("box", box)
                }.toString()
            val header = listOf("${SyncProtocol.SESSION_HEADER}: ${session.id}")
            val answer = post("/v1/sync/exchange", envelope, header)
            assertEquals(200, answer.status)
            val opened = SyncChannel.open(session.keys.r2i, session.id, SyncChannel.RESPONSE, 1, SyncJson.parseObject(answer.body)!!.string("box")!!)
            assertEquals(responderRun.replica, SyncJson.parseObject(opened!!)!!.string("replica"))
            assertEquals(400, post("/v1/sync/exchange", envelope, header).status) // replay
            val forged =
                buildJsonObject {
                    put("seq", 2)
                    put("box", SyncChannel.seal(session.keys.r2i, session.id, SyncChannel.REQUEST, 2, pull))
                }.toString()
            assertEquals(400, post("/v1/sync/exchange", forged, header).status)
            assertFalse(SyncAddressRule { emptyList() }.permits("192.168.1.20"))
        }

    @Test fun addressRuleAcceptsOnlyLocalPeers() {
        val wifi = SyncSubnet(InetAddress.getByName("192.168.1.10"), 24)
        val rule = SyncAddressRule { listOf(wifi) }
        assertTrue(rule.permits("127.0.0.1"))
        assertTrue(rule.permits("::1"))
        assertTrue(rule.permits("169.254.10.2"))
        assertTrue(rule.permits("fe80::1%wlan0"))
        assertTrue(rule.permits("192.168.1.200"))
        assertTrue(rule.permits("::ffff:192.168.1.7"))
        assertFalse(rule.permits("192.168.2.1"))
        assertFalse(rule.permits("10.8.0.2"))
        assertFalse(rule.permits("8.8.8.8"))
        assertFalse(rule.permits("example.com"))
        val ordered = rule.outgoing(listOf(InetAddress.getByName("fe80::2"), InetAddress.getByName("8.8.8.8"), InetAddress.getByName("192.168.1.5")))
        assertEquals(listOf("192.168.1.5", "fe80:0:0:0:0:0:0:2"), ordered.map { it.hostAddress })
    }

    @Test fun headerGateOrder() {
        val ok = SyncRequestGate.Request(true, false, false, listOf("10"), "application/json; charset=utf-8", 16)
        assertNull(SyncRequestGate.check(ok))
        assertEquals(403 to "FORBIDDEN", SyncRequestGate.check(ok.copy(sourcePermitted = false)))
        assertEquals(400 to "BAD_REQUEST", SyncRequestGate.check(ok.copy(contentLengths = listOf("1, 1"))))
        assertEquals(413 to "PAYLOAD_TOO_LARGE", SyncRequestGate.check(ok.copy(contentLengths = listOf("17"))))
    }
}
