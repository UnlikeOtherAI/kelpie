package com.kelpie.browser.sync

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Reproduces every value in core/native/core-sync/tests/vectors/handshake-v1.json with JCA. */
class SyncCryptoVectorTests {
    private val vectors: JsonObject =
        Json.parseToJsonElement(File(requireNotNull(System.getProperty("kelpie.sync.vectors"))).readText()).jsonObject

    private fun field(
        side: String,
        key: String,
    ) = vectors[side]!!.jsonObject[key]!!.jsonPrimitive.content

    private fun top(key: String) = vectors[key]!!.jsonPrimitive.content

    private fun bytes(text: String) = requireNotNull(SyncBase64.decode(text))

    private fun pair(side: String) = SyncCrypto.keyPair(bytes(field(side, "privateKey")), bytes(field(side, "key")))

    @Test fun transcriptChallengeComesFromCoreSync() {
        val challenge =
            SyncCore.challenge(
                HelloSide(field("initiator", "replica"), field("initiator", "key"), field("initiator", "nonce")),
                HelloSide(field("responder", "replica"), field("responder", "key"), field("responder", "nonce")),
            )
        assertEquals(top("challenge"), challenge)
    }

    @Test fun ecdhAgreesInBothDirections() {
        val initiator = pair("initiator")
        val responder = pair("responder")
        val forward = SyncCrypto.sharedSecret(initiator.privateKey, SyncCrypto.decodePublicKey(field("responder", "key"))!!)
        val backward = SyncCrypto.sharedSecret(responder.privateKey, SyncCrypto.decodePublicKey(field("initiator", "key"))!!)
        assertEquals(top("sharedSecret"), SyncBase64.encode(forward))
        assertArrayEquals(forward, backward)
    }

    @Test fun hkdfDerivesBothDirectionKeys() {
        val initiator = pair("initiator")
        val keys = SyncChannel.deriveKeys(initiator.privateKey, SyncCrypto.decodePublicKey(field("responder", "key"))!!, top("challenge"))
        assertEquals(top("i2r"), SyncBase64.encode(keys.i2r))
        assertEquals(top("r2i"), SyncBase64.encode(keys.r2i))
        val responder = pair("responder")
        val mirrored = SyncChannel.deriveKeys(responder.privateKey, SyncCrypto.decodePublicKey(field("initiator", "key"))!!, top("challenge"))
        assertArrayEquals(keys.i2r, mirrored.i2r)
        assertArrayEquals(keys.r2i, mirrored.r2i)
    }

    @Test fun everyMessageSealsAndOpensExactly() {
        val i2r = bytes(top("i2r"))
        val r2i = bytes(top("r2i"))
        val session = top("sessionId")
        for (element in vectors["messages"]!!.jsonArray) {
            val message = element.jsonObject
            val direction = message["direction"]!!.jsonPrimitive.content
            val seq = message["seq"]!!.jsonPrimitive.long
            val plaintext = message["plaintext"]!!.jsonPrimitive.content
            val key = if (direction == SyncChannel.REQUEST) i2r else r2i
            assertEquals(message["nonce"]!!.jsonPrimitive.content, SyncBase64.encode(SyncChannel.nonce(seq)))
            assertEquals(message["aad"]!!.jsonPrimitive.content, SyncBase64.encode(SyncChannel.aad(session, direction, seq)))
            val box = SyncChannel.seal(key, session, direction, seq, plaintext)
            assertEquals(message["box"]!!.jsonPrimitive.content, box)
            assertEquals(plaintext, SyncChannel.open(key, session, direction, seq, box))
            // The other direction's key, the other direction's AAD and the next seq must all fail.
            assertNull(SyncChannel.open(if (key === i2r) r2i else i2r, session, direction, seq, box))
            assertNull(SyncChannel.open(key, session, if (direction == "req") "res" else "req", seq, box))
            assertNull(SyncChannel.open(key, session, direction, seq + 1, box))
        }
    }

    @Test fun publicKeysMustBeUncompressedPointsOnTheCurve() {
        val key = bytes(field("initiator", "key"))
        assertNotNull(SyncCrypto.decodePublicKey(key))
        val offCurve = key.copyOf().also { it[64] = (it[64].toInt() xor 1).toByte() }
        assertNull(SyncCrypto.decodePublicKey(offCurve))
        assertNull(SyncCrypto.decodePublicKey(key.copyOf().also { it[0] = 0x02 }))
        assertNull(SyncCrypto.decodePublicKey(key.copyOf(33)))
        assertNull(SyncCrypto.decodePublicKey("not base64url!"))
    }

    @Test fun generatedKeysRoundTrip() {
        val random = java.security.SecureRandom()
        val a = SyncCrypto.generateKeyPair(random)
        val b = SyncCrypto.generateKeyPair(random)
        assertEquals(65, a.publicKey.size)
        val one = SyncCrypto.sharedSecret(a.privateKey, SyncCrypto.decodePublicKey(b.publicKey)!!)
        val two = SyncCrypto.sharedSecret(b.privateKey, SyncCrypto.decodePublicKey(a.publicKey)!!)
        assertArrayEquals(one, two)
    }

    @Test fun replayWindowAcceptsEachSeqOnceWithin64() {
        val window = ReplayWindow()
        assertTrue(window.accept(1))
        assertFalse(window.accept(1))
        assertTrue(window.accept(3))
        assertTrue(window.accept(2))
        assertTrue(window.accept(100))
        assertTrue(window.accept(37))
        assertTrue(window.accept(36)) // exactly 64 below the highest
        assertFalse(window.accept(35)) // 65 below
        assertFalse(window.accept(37))
        assertFalse(window.accept(100))
        assertFalse(window.accept(0))
        assertTrue(window.accept(99))
    }

    @Test fun skewGateSurvivesExtremeClocks() {
        assertTrue(SyncProtocol.withinSkew(1_000_000, 1_000_000 + SyncProtocol.MAX_CLOCK_SKEW_MS))
        assertFalse(SyncProtocol.withinSkew(1_000_000, 1_000_001 + SyncProtocol.MAX_CLOCK_SKEW_MS))
        assertFalse(SyncProtocol.withinSkew(Long.MIN_VALUE, 1_767_225_600_000))
        assertFalse(SyncProtocol.withinSkew(Long.MAX_VALUE, -1_767_225_600_000))
    }

    @Test fun peerErrorsAreLimitedToDocumentedCodes() {
        assertEquals("CLOCK_SKEW", SyncProtocol.peerCode("CLOCK_SKEW", 409))
        assertEquals("PEER_ERROR", SyncProtocol.peerCode("eyJhbGci.reflected.ticket", 403))
        assertEquals("PEER_ERROR", SyncProtocol.peerCode("sid=secret", 400))
        assertEquals("HTTP_502", SyncProtocol.peerCode(null, 502))
    }

    @Test fun base64UrlRejectsPaddingAndStandardAlphabet() {
        assertNull(SyncBase64.decode("YQ=="))
        assertNull(SyncBase64.decode("a+b/"))
        assertEquals("YQ", SyncBase64.encode("a".toByteArray()))
    }
}
