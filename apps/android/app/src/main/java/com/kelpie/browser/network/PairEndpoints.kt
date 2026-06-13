package com.kelpie.browser.network

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

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
        val (clientId, clientName) =
            try {
                val element =
                    parser.parseToJsonElement(bodyText) as? JsonObject
                        ?: return errorResult(400, "INVALID_JSON", "Request body is not a JSON object")
                val id =
                    element["clientId"]?.jsonPrimitive?.contentOrNull
                        ?: return errorResult(400, "MISSING_PARAM", "clientId is required")
                val name = element["clientName"]?.jsonPrimitive?.contentOrNull ?: ""
                if (id.isEmpty()) return errorResult(400, "MISSING_PARAM", "clientId is required")
                id to name
            } catch (_: Throwable) {
                return errorResult(400, "INVALID_JSON", "Request body is not valid JSON")
            }

        val start = store.startPairing(clientId, clientName, sourceAddress)
        return when (start.result) {
            PairingStore.PairStartResult.DENIED ->
                errorResult(403, "DENIED", "Pair requests from this source are currently suppressed")
            PairingStore.PairStartResult.CREATED -> {
                val req = start.request ?: return errorResult(500, "INTERNAL", "Failed to create pending request")
                onPendingChanged()
                JsonResult(
                    status = 202,
                    json =
                        mapOf(
                            "status" to "pending",
                            "requestId" to req.requestId,
                            "expiresAt" to req.expiresAt,
                            "sourceAddress" to req.sourceAddress,
                        ),
                )
            }
        }
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
        return JsonResult(200, mapOf("status" to "not_found"))
    }

    fun handlePairDelete(authenticatedClientId: String): JsonResult {
        val removed = store.revoke(authenticatedClientId)
        return JsonResult(200, mapOf("success" to removed))
    }

    fun handleGetDeviceInfo(
        name: String,
        platform: String,
        version: String,
    ): JsonResult =
        JsonResult(
            200,
            mapOf(
                "name" to name,
                "platform" to platform,
                "version" to version,
                "requiresPairing" to true,
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
