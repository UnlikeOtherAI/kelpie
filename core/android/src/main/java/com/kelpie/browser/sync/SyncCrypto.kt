package com.kelpie.browser.sync

import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.interfaces.ECPrivateKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECFieldFp
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** base64url without padding, the encoding of every binary sync field. */
object SyncBase64 {
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder = Base64.getUrlDecoder()

    fun encode(bytes: ByteArray): String = encoder.encodeToString(bytes)

    fun decode(text: String): ByteArray? = if (text.contains('=')) null else runCatching { decoder.decode(text) }.getOrNull()
}

/** One ephemeral P-256 key pair; [publicKey] is the x9.63 uncompressed point (65 bytes). */
class SyncKeyPair(
    val privateKey: ECPrivateKey,
    val publicKey: ByteArray,
) {
    val encodedPublicKey: String get() = SyncBase64.encode(publicKey)
}

/** The channel cryptography from the handshake spec, using only JCA primitives. */
object SyncCrypto {
    private const val COORDINATE_BYTES = 32
    private const val TAG_BITS = 128

    private val curve: ECParameterSpec by lazy {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"))
        (generator.generateKeyPair().public as ECPublicKey).params
    }

    fun generateKeyPair(random: SecureRandom): SyncKeyPair {
        val generator = KeyPairGenerator.getInstance("EC")
        generator.initialize(ECGenParameterSpec("secp256r1"), random)
        val pair = generator.generateKeyPair()
        return SyncKeyPair(pair.private as ECPrivateKey, encodePoint((pair.public as ECPublicKey).w))
    }

    /** Rebuilds a key pair from a raw scalar and its public point; used by the shared vectors. */
    fun keyPair(
        privateScalar: ByteArray,
        publicKey: ByteArray,
    ): SyncKeyPair {
        val spec = ECPrivateKeySpec(BigInteger(1, privateScalar), curve)
        val private = KeyFactory.getInstance("EC").generatePrivate(spec) as ECPrivateKey
        requireNotNull(decodePublicKey(publicKey)) { "invalid public key" }
        return SyncKeyPair(private, publicKey)
    }

    /** Returns the key only when it is an uncompressed point on P-256. */
    fun decodePublicKey(encoded: ByteArray): ECPublicKey? {
        if (encoded.size != 1 + 2 * COORDINATE_BYTES || encoded[0] != 0x04.toByte()) return null
        val x = BigInteger(1, encoded.copyOfRange(1, 1 + COORDINATE_BYTES))
        val y = BigInteger(1, encoded.copyOfRange(1 + COORDINATE_BYTES, encoded.size))
        if (!onCurve(x, y)) return null
        return runCatching {
            KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(ECPoint(x, y), curve)) as ECPublicKey
        }.getOrNull()
    }

    fun decodePublicKey(encoded: String): ECPublicKey? = SyncBase64.decode(encoded)?.let(::decodePublicKey)

    private fun onCurve(
        x: BigInteger,
        y: BigInteger,
    ): Boolean {
        val field = curve.curve.field as ECFieldFp
        val p = field.p
        if (x.signum() < 0 || y.signum() < 0 || x >= p || y >= p) return false
        val left = y.multiply(y).mod(p)
        val right =
            x
                .pow(3)
                .add(curve.curve.a.multiply(x))
                .add(curve.curve.b)
                .mod(p)
        return left == right
    }

    private fun encodePoint(point: ECPoint): ByteArray = byteArrayOf(0x04) + fixed(point.affineX) + fixed(point.affineY)

    private fun fixed(value: BigInteger): ByteArray {
        val bytes = value.toByteArray()
        return when {
            bytes.size == COORDINATE_BYTES -> bytes
            bytes.size > COORDINATE_BYTES -> bytes.copyOfRange(bytes.size - COORDINATE_BYTES, bytes.size)
            else -> ByteArray(COORDINATE_BYTES - bytes.size) + bytes
        }
    }

    fun sharedSecret(
        own: ECPrivateKey,
        peer: ECPublicKey,
    ): ByteArray =
        KeyAgreement.getInstance("ECDH").run {
            init(own)
            doPhase(peer, true)
            generateSecret()
        }

    /** RFC 5869 HKDF-SHA256 built from HmacSHA256. */
    fun hkdf(
        ikm: ByteArray,
        salt: ByteArray,
        info: ByteArray,
        length: Int,
    ): ByteArray {
        require(length in 1..255 * 32)
        val prk = hmac(salt.takeIf { it.isNotEmpty() } ?: ByteArray(32), ikm)
        val output = java.io.ByteArrayOutputStream()
        var previous = ByteArray(0)
        var counter = 1
        while (output.size() < length) {
            previous = hmac(prk, previous + info + byteArrayOf(counter.toByte()))
            output.write(previous)
            counter++
        }
        return output.toByteArray().copyOf(length)
    }

    private fun hmac(
        key: ByteArray,
        data: ByteArray,
    ): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(data)
        }

    /** AES-256-GCM; returns ciphertext || 16-byte tag. */
    fun seal(
        key: ByteArray,
        nonce: ByteArray,
        aad: ByteArray,
        plaintext: ByteArray,
    ): ByteArray = cipher(Cipher.ENCRYPT_MODE, key, nonce, aad).doFinal(plaintext)

    /** Returns null when the box does not authenticate. */
    fun open(
        key: ByteArray,
        nonce: ByteArray,
        aad: ByteArray,
        box: ByteArray,
    ): ByteArray? = runCatching { cipher(Cipher.DECRYPT_MODE, key, nonce, aad).doFinal(box) }.getOrNull()

    private fun cipher(
        mode: Int,
        key: ByteArray,
        nonce: ByteArray,
        aad: ByteArray,
    ): Cipher =
        Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_BITS, nonce))
            updateAAD(aad)
        }
}
