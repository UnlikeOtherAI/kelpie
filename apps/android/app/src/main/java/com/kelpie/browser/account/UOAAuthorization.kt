package com.kelpie.browser.account

import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/** Public native OAuth uses S256 PKCE and a one-use exact callback. */
class UOAAuthorization(
    val state: String = randomValue(),
    val verifier: String = randomValue(),
) {
    val challenge: String = base64(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))

    fun url(clientId: String): String {
        val fields =
            linkedMapOf(
                "response_type" to "code",
                "client_id" to clientId,
                "redirect_uri" to CALLBACK,
                "scope" to SCOPES,
                "state" to state,
                "code_challenge" to challenge,
                "code_challenge_method" to "S256",
            )
        return UOATransport.ORIGIN + "/oauth/authorize?" + fields.entries.joinToString("&") { "${encode(it.key)}=${encode(it.value)}" }
    }

    private fun fields(callback: String): List<Pair<String, String>> {
        val uri = URI(callback)
        require(
            uri.scheme == "com.unlikeotherai.kelpie" &&
                uri.host == "oauth" &&
                uri.path == "/callback" &&
                uri.userInfo == null &&
                uri.port == -1 &&
                uri.fragment == null,
        ) { "Invalid login callback" }
        val fields =
            uri.rawQuery.orEmpty().split('&').map { item ->
                val pair = item.split('=', limit = 2)
                decode(pair[0]) to decode(pair.getOrElse(1) { "" })
            }
        require(fields.count { it.first == "state" } == 1 && fields.single { it.first == "state" }.second == state) { "Invalid login response" }
        return fields
    }

    fun denied(callback: String): Boolean = fields(callback).any { it.first == "error" }

    fun code(callback: String): String {
        val fields = fields(callback)
        require(fields.count { it.first == "code" } == 1 && fields.none { it.first == "error" }) { "Invalid login response" }
        return fields.single { it.first == "code" }.second.also { require(it.isNotBlank()) }
    }

    companion object {
        const val CALLBACK = "com.unlikeotherai.kelpie://oauth/callback"
        const val SCOPES = "openid profile settings.read settings.write"

        private fun randomValue(): String = base64(ByteArray(32).also(SecureRandom()::nextBytes))

        private fun base64(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

        private fun encode(value: String) = URLEncoder.encode(value, "UTF-8")

        private fun decode(value: String) = URLDecoder.decode(value, "UTF-8")
    }
}
