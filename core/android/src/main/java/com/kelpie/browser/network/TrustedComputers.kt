package com.kelpie.browser.network

import com.kelpie.browser.nativecore.NativeCore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

@Serializable
data class TrustedComputer(val publicKey: String, val address: String, val name: String, val approvedAt: Long)

@Serializable
data class ComputerRequest(val requestId: String, val clientName: String, val sourceAddress: String, val publicKey: String)

/** The native queue owns signing-key trust; IP is only routing/display data. */
interface ComputerTrust {
    fun request(operation: String, body: JsonObject = JsonObject(emptyMap())): JsonObject

    fun canonicalAddress(address: String): String? = request("normalize", fields("address" to address))["address"]?.jsonPrimitive?.contentOrNull

    fun safeHost(host: String): Boolean = request("safe-host", fields("host" to host))["safe"]?.jsonPrimitive?.booleanOrNull == true

    fun clientId(address: String, token: String = ""): String? = request("authorize", fields("address" to address, "token" to token))["clientId"]?.jsonPrimitive?.contentOrNull

    fun approve(requestId: String): Boolean = request("approve", fields("requestId" to requestId))["success"]?.jsonPrimitive?.booleanOrNull == true

    fun deny(requestId: String) { request("deny", fields("requestId" to requestId)) }

    fun revoke(publicKey: String): Boolean = request("revoke", fields("publicKey" to publicKey))["success"]?.jsonPrimitive?.booleanOrNull == true

    fun list(): List<TrustedComputer> = runCatching { computerJson.decodeFromString<List<TrustedComputer>>(request("list")["computers"].toString()) }.getOrDefault(emptyList())

    fun pending(): ComputerRequest? = runCatching { computerJson.decodeFromString<ComputerRequest>(request("pending").toString()) }.getOrNull()

    fun start(body: JsonObject, source: String): PairEndpoints.JsonResult {
        val response = request("start", JsonObject(mapOf("address" to JsonPrimitive(source), "body" to body)))
        return PairEndpoints.JsonResult(response["status"]?.jsonPrimitive?.intOrNull ?: 500, toValues(response["body"] as? JsonObject ?: JsonObject(emptyMap())))
    }

    fun status(requestId: String, source: String): Map<String, Any?> = toValues(request("status", fields("requestId" to requestId, "address" to source)))
}

private val computerJson = Json { ignoreUnknownKeys = true }

private fun fields(vararg pairs: Pair<String, String>) = JsonObject(pairs.associate { it.first to JsonPrimitive(it.second) })

private fun toValues(value: JsonObject): Map<String, Any?> = value.mapValues { (_, element) ->
    if (element is JsonObject) toValues(element) else (element as? JsonPrimitive)?.let { if (it.isString) it.contentOrNull else it.booleanOrNull ?: it.longOrNull ?: it.doubleOrNull }
}

class TrustedComputers(private val file: File) : ComputerTrust {
    override fun request(operation: String, body: JsonObject): JsonObject = runCatching {
        computerJson.parseToJsonElement(NativeCore.peerTrustRequest(file.absolutePath, operation, body.toString())) as? JsonObject
    }.getOrNull() ?: JsonObject(emptyMap())
}
