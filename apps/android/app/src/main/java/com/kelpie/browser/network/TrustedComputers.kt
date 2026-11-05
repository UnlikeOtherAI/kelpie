package com.kelpie.browser.network

import com.kelpie.browser.nativecore.NativeCore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.File

@Serializable
data class TrustedComputer(
    val address: String,
    val name: String,
    val approvedAt: Long,
)

/** Host permissions are independent of client UUIDs and UOA account grants. */
interface ComputerTrust {
    fun canonicalAddress(address: String): String?

    fun safeHost(host: String): Boolean

    fun clientId(address: String): String?

    fun approve(
        address: String,
        name: String,
    ): Boolean

    fun revoke(address: String): Boolean

    fun list(): List<TrustedComputer>
}

class TrustedComputers(
    private val file: File,
) : ComputerTrust {
    private val json = Json { ignoreUnknownKeys = true }

    private fun request(
        operation: String,
        body: Map<String, String> = emptyMap(),
    ): JsonObject =
        runCatching {
            json.parseToJsonElement(
                NativeCore.peerTrustRequest(file.absolutePath, operation, JsonObject(body.mapValues { JsonPrimitive(it.value) }).toString()),
            ) as JsonObject
        }.getOrDefault(JsonObject(emptyMap()))

    override fun canonicalAddress(address: String): String? = request("normalize", mapOf("address" to address))["address"]?.jsonPrimitive?.contentOrNull

    override fun safeHost(host: String): Boolean = request("safe-host", mapOf("host" to host))["safe"]?.jsonPrimitive?.booleanOrNull == true

    override fun clientId(address: String): String? {
        val canonical = canonicalAddress(address) ?: return null
        return if (request("check", mapOf("address" to canonical))["trusted"]?.jsonPrimitive?.booleanOrNull == true) "host:$canonical" else null
    }

    override fun approve(
        address: String,
        name: String,
    ): Boolean = request("approve", mapOf("address" to address, "name" to name))["success"]?.jsonPrimitive?.booleanOrNull == true

    override fun revoke(address: String): Boolean = request("revoke", mapOf("address" to address))["success"]?.jsonPrimitive?.booleanOrNull == true

    override fun list(): List<TrustedComputer> = runCatching { json.decodeFromString<List<TrustedComputer>>(request("list")["computers"].toString()) }.getOrDefault(emptyList())
}
