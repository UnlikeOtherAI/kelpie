package com.kelpie.browser.network

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.UUID

@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = 33)
class ComputerTrustInstrumentedTest {
    private fun computer(alias: String): KeyPair =
        KeyPairGenerator.getInstance("Ed25519", "AndroidKeyStore").run {
            initialize(
                KeyGenParameterSpec
                    .Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setAlgorithmParameterSpec(ECGenParameterSpec("ed25519"))
                    .setDigests(KeyProperties.DIGEST_NONE)
                    .build(),
            )
            generateKeyPair()
        }

    private fun key(pair: KeyPair): String =
        pair.public.encoded
            .takeLast(32)
            .joinToString("") { "%02x".format(it) }

    private fun start(
        trust: ComputerTrust,
        pair: KeyPair,
        ip: String,
    ): String {
        val publicKey = key(pair)
        val body = mapOf("clientId" to UUID.randomUUID().toString(), "clientName" to "Test computer", "computerPublicKey" to publicKey)
        val challenge = trust.start(JsonObject(body.mapValues { JsonPrimitive(it.value) }), ip)
        assertEquals(challenge.json.toString(), 202, challenge.status)
        val id = challenge.json["requestId"] as String
        val signature = Signature.getInstance("Ed25519")
        signature.initSign(pair.private)
        signature.update("kelpie-computer-pair-v1\n$id\n$publicKey".toByteArray())
        val proof = body + mapOf("requestId" to id, "computerSignature" to signature.sign().joinToString("") { "%02x".format(it) })
        val response = trust.start(JsonObject(proof.mapValues { JsonPrimitive(it.value) }), ip)
        assertEquals(response.json.toString(), 202, response.status)
        return id
    }

    @Test
    fun trustSurvivesAddressChangesAndRestartWhileAnotherKeyAtTheOldIPIsDenied() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.cacheDir, "computer-trust-${UUID.randomUUID()}")
        val aliases = listOf("kelpie-trust-test-${UUID.randomUUID()}", "kelpie-trust-test-${UUID.randomUUID()}")
        directory.mkdirs()
        try {
            val file = File(directory, "trusted-computers.json")
            var trust = TrustedComputers(file)
            val computer = computer(aliases[0])
            val id = start(trust, computer, "192.0.2.1")
            assertNotNull(trust.pending())
            assertTrue(trust.approve(id))
            val token = trust.status(id, "192.0.2.1")["token"] as String
            trust = TrustedComputers(file)
            assertEquals(key(computer), trust.clientId("203.0.113.2", token))
            val moved = start(trust, computer, "203.0.113.2")
            assertNull(trust.pending())
            assertEquals("approved", trust.status(moved, "203.0.113.2")["status"])
            assertNull(trust.clientId("192.0.2.1"))
            start(trust, computer(aliases[1]), "192.0.2.1")
            assertNotNull(trust.pending())
            assertTrue(trust.revoke(key(computer)))
            assertNull(trust.clientId("203.0.113.2", token))
        } finally {
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.let { store -> aliases.forEach(store::deleteEntry) }
            directory.deleteRecursively()
        }
    }
}
