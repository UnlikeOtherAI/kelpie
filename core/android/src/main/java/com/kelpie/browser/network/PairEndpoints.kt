package com.kelpie.browser.network

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/** Handler for the v1 pair endpoints. Kept separate from the routing layer. */
class PairEndpoints(
    private val store: PairingStore,
    private val onPendingChanged: () -> Unit,
) {
    data class JsonResult(
        val status: Int,
        val json: Map<String, Any?>,
    )

    private val parser =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
        }

    fun handlePairPost(
        bodyText: String,
        sourceAddress: String,
    ): JsonResult {
        val parsed = try {
            parser.parseToJsonElement(bodyText) as? JsonObject
                ?: return errorResult(400, "INVALID_JSON", "Expected a JSON object")
        } catch (_: Exception) { return errorResult(400, "INVALID_JSON", "Invalid JSON") }
        val result = store.trustedComputers.start(parsed, sourceAddress)
        onPendingChanged()
        return result
    }

    fun handlePairStatus(
        requestId: String?,
        sourceAddress: String,
    ): JsonResult {
        if (requestId.isNullOrEmpty()) {
            return errorResult(400, "MISSING_PARAM", "requestId is required")
        }
        val pending = store.pendingRequest(requestId)
        if (pending != null) {
            if (pending.sourceAddress != sourceAddress) {
                return JsonResult(200, mapOf("status" to "not_found"))
            }
            return JsonResult(200, mapOf("status" to "pending"))
        }
        val issuance = store.takeIssuance(requestId, sourceAddress)
        if (issuance != null) {
            return JsonResult(
                200,
                mapOf(
                    "status" to "approved",
                    "scope" to issuance.scope,
                    "token" to issuance.token,
                ),
            )
        }
        if (store.wasRecentlyDenied(sourceAddress)) {
            return JsonResult(200, mapOf("status" to "denied"))
        }
        onPendingChanged()
        return JsonResult(200, store.trustedComputers.status(requestId, sourceAddress))
    }

    fun handlePairDelete(authenticatedClientId: String, computerKey: String? = null): JsonResult {
        val removed = computerKey?.let { store.trustedComputers.revoke(it) } ?: store.revoke(authenticatedClientId)
        return JsonResult(200, mapOf("success" to removed))
    }

    fun handleGetDeviceInfo(
        name: String,
        platform: String,
        version: String,
        sourceAddress: String? = null,
    ): JsonResult =
        JsonResult(
            200,
            mapOf(
                "name" to name,
                "platform" to platform,
                "version" to version,
                "requiresPairing" to (sourceAddress?.let { store.trustedComputers.clientId(it) } == null),
                "approvalMode" to "computer-key",
                "localhostTrusted" to true,
            ),
        )

    private fun errorResult(
        status: Int,
        code: String,
        message: String,
    ): JsonResult =
        JsonResult(
            status = status,
            json =
                mapOf(
                    "success" to false,
                    "error" to mapOf("code" to code, "message" to message),
                ),
        )
}
