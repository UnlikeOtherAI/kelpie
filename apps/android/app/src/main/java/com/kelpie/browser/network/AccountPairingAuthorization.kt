package com.kelpie.browser.network

import com.kelpie.browser.account.UOALocalPairing
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/** Account proofs share the existing ephemeral pairing store; no parallel durable trust exists. */
class AccountPairingAuthorization(
    private val store: PairingStore,
    private val session: suspend () -> String? = UOALocalPairing::session,
    private val verify: suspend (String, String, String, String) -> Long? = UOALocalPairing::verify,
) {
    companion object {
        private fun parse(body: String): JsonObject? = runCatching { Json.parseToJsonElement(body) as? JsonObject }.getOrNull()

        fun handles(body: String): Boolean = (parse(body)?.get("account") as? JsonPrimitive)?.booleanOrNull == true

        private fun string(
            value: JsonObject,
            key: String,
        ): String? = (value[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    }

    suspend fun handlePost(
        body: String,
        sourceAddress: String,
    ): PairEndpoints.JsonResult {
        val value = parse(body) ?: return error(400, "INVALID_JSON", "Request body is not valid JSON")
        val clientId =
            string(value, "clientId")?.takeIf { it.isNotEmpty() && it.length <= 200 }
                ?: return error(400, "MISSING_PARAM", "clientId is required")
        val current = session() ?: return error(409, "ACCOUNT_PAIRING_UNAVAILABLE", "Kelpie is not signed in")
        if (value.containsKey("accountTicket") || value.containsKey("requestId")) {
            val ticket =
                string(value, "accountTicket")?.takeIf { it.isNotEmpty() && it.toByteArray().size <= 8192 }
                    ?: return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            val challenge = string(value, "requestId") ?: return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            val pending = store.pendingRequest(challenge)
            if (pending == null || pending.clientId != clientId || pending.sourceAddress != sourceAddress || pending.accountSession != current) {
                return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            }
            val expiry = verify(ticket, challenge, clientId, current)
            val now = System.currentTimeMillis()
            if (expiry == null || expiry <= now || expiry > now + 120_000 || session() != current) {
                return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            }
            val grantedExpiry = minOf(expiry, pending.expiresAt)
            val grant = PairingStore.AccountGrant(current, ticket, challenge, grantedExpiry, sourceAddress)
            if (store.approve(challenge, false, grant) == null) return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            val issued = store.takeIssuance(challenge, sourceAddress) ?: return error(403, "ACCOUNT_AUTH_FAILED", "Account pairing verification failed")
            return PairEndpoints.JsonResult(200, mapOf("status" to "approved", "scope" to "session", "token" to issued.token, "expiresAt" to grantedExpiry))
        }
        val start = store.startPairing(clientId, string(value, "clientName").orEmpty(), sourceAddress, current)
        val pending = start.request ?: return error(403, "DENIED", "Pair requests from this source are currently suppressed")
        return PairEndpoints.JsonResult(202, mapOf("status" to "account_challenge", "requestId" to pending.requestId, "expiresAt" to pending.expiresAt))
    }

    suspend fun evaluate(request: ParsedRequest): AuthDecision {
        val middleware = AuthMiddleware(store)
        val decision = middleware.evaluate(request)
        if (decision !is AuthDecision.Reject || decision.status != 401) return decision
        val header = request.headers["authorization"]?.firstOrNull()?.takeIf { it.lowercase().startsWith("bearer ") } ?: return decision
        val token = header.drop(7).trim()
        val approval = store.accountApproval(token) ?: return decision
        val grant = approval.accountGrant ?: return decision
        if (session() != grant.session) return decision
        val expiry = verify(grant.ticket, grant.challenge, approval.clientId, grant.session) ?: return decision
        if (expiry <= System.currentTimeMillis() || session() != grant.session || store.accountApproval(token) != approval) return decision
        return middleware.evaluate(request, verifiedAccountClientId = approval.clientId)
    }

    private fun error(
        status: Int,
        code: String,
        message: String,
    ): PairEndpoints.JsonResult = PairEndpoints.JsonResult(status, mapOf("success" to false, "error" to mapOf("code" to code, "message" to message)))
}
