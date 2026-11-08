package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** User-declared capability overrides. Null = not declared (server or test evidence applies). */
data class CapabilityOverrides(
    val contextWindow: Int? = null,
    val vision: Boolean? = null,
    val toolCalling: Boolean? = null,
    val jsonSchema: Boolean? = null,
)

/** A capability value with the evidence it came from (`server`, `user`, `test` or null). */
data class Capability<T>(
    val value: T?,
    val source: String?,
) {
    fun toPublic(): Map<String, Any?> = linkedMapOf("value" to value, "source" to source)

    companion object {
        fun <T> resolve(vararg candidates: Pair<T?, String>): Capability<T> {
            val hit = candidates.firstOrNull { it.first != null } ?: return Capability(null, null)
            return Capability(hit.first, hit.second)
        }
    }
}

/** A saved OpenAI-compatible endpoint. The API key lives in SecretStore, never here. */
data class OpenAIEndpoint(
    val id: String,
    val name: String,
    val baseURL: String,
    val model: String? = null,
    val user: CapabilityOverrides = CapabilityOverrides(),
    val testedToolCalling: Boolean? = null,
    val testedToolCallingModel: String? = null,
    val models: List<DiscoveredModel> = emptyList(),
    val modelsDiscoveredAtMs: Long? = null,
) {
    val url: OpenAIEndpointURL get() = OpenAIEndpointURL.normalize(baseURL)

    val loopback: Boolean get() = OpenAIEndpointURL.normalizeOrNull(baseURL)?.isLoopback ?: false

    private val selectedModelInfo: DiscoveredModel? get() = models.firstOrNull { it.id == model }

    val contextWindow: Capability<Int>
        get() = Capability.resolve(user.contextWindow to SOURCE_USER, selectedModelInfo?.contextWindow to SOURCE_SERVER)

    val vision: Capability<Boolean>
        get() = Capability.resolve(user.vision to SOURCE_USER, selectedModelInfo?.vision to SOURCE_SERVER)

    val toolCalling: Capability<Boolean>
        get() {
            val tested = testedToolCalling.takeIf { testedToolCallingModel != null && testedToolCallingModel == model }
            return Capability.resolve(user.toolCalling to SOURCE_USER, tested to SOURCE_TEST)
        }

    val jsonSchema: Capability<Boolean>
        get() = Capability.resolve(user.jsonSchema to SOURCE_USER)

    fun capabilitiesPublic(): Map<String, Any?> =
        linkedMapOf(
            "contextWindow" to contextWindow.toPublic(),
            "vision" to vision.toPublic(),
            "toolCalling" to toolCalling.toPublic(),
            "jsonSchema" to jsonSchema.toPublic(),
        )

    /** `EndpointPublic` from the contract. Never contains the API key. */
    fun toPublic(
        hasApiKey: Boolean,
        health: Map<String, Any?>,
    ): Map<String, Any?> =
        linkedMapOf(
            "id" to id,
            "name" to name,
            "baseURL" to baseURL,
            "loopback" to loopback,
            "hasApiKey" to hasApiKey,
            "model" to model,
            "capabilities" to capabilitiesPublic(),
            "models" to models.map { it.toPublic() },
            "modelsDiscoveredAt" to modelsDiscoveredAtMs?.let(EndpointHealth::isoTimestamp),
            "health" to health,
        )

    fun summaryPublic(): Map<String, Any?> = linkedMapOf("id" to id, "name" to name, "baseURL" to baseURL, "loopback" to loopback)

    fun toJson(): JsonObject =
        OpenAIJson.fromAny(
            linkedMapOf(
                "id" to id,
                "name" to name,
                "baseURL" to baseURL,
                "model" to model,
                "user" to
                    linkedMapOf(
                        "contextWindow" to user.contextWindow,
                        "vision" to user.vision,
                        "toolCalling" to user.toolCalling,
                        "jsonSchema" to user.jsonSchema,
                    ),
                "testedToolCalling" to testedToolCalling,
                "testedToolCallingModel" to testedToolCallingModel,
                "models" to models.map { it.toPublic() },
                "modelsDiscoveredAtMs" to modelsDiscoveredAtMs,
            ),
        ) as JsonObject

    companion object {
        const val SOURCE_SERVER = "server"
        const val SOURCE_USER = "user"
        const val SOURCE_TEST = "test"

        fun fromJson(element: JsonElement): OpenAIEndpoint? {
            val obj = element as? JsonObject ?: return null
            val id = OpenAIJson.string(obj["id"])?.takeIf { it.isNotEmpty() } ?: return null
            val baseURL = OpenAIJson.string(obj["baseURL"]) ?: return null
            val normalized = OpenAIEndpointURL.normalizeOrNull(baseURL) ?: return null
            val user = OpenAIJson.objectOrNull(obj["user"])
            return OpenAIEndpoint(
                id = id,
                name = OpenAIJson.string(obj["name"]) ?: normalized.host,
                baseURL = normalized.baseURL,
                model = OpenAIJson.string(obj["model"])?.takeIf { it.isNotEmpty() },
                user =
                    CapabilityOverrides(
                        contextWindow = OpenAIJson.int(user?.get("contextWindow")),
                        vision = OpenAIJson.boolean(user?.get("vision")),
                        toolCalling = OpenAIJson.boolean(user?.get("toolCalling")),
                        jsonSchema = OpenAIJson.boolean(user?.get("jsonSchema")),
                    ),
                testedToolCalling = OpenAIJson.boolean(obj["testedToolCalling"]),
                testedToolCallingModel = OpenAIJson.string(obj["testedToolCallingModel"]),
                models = (obj["models"] as? JsonArray)?.mapNotNull(DiscoveredModel::fromJson).orEmpty(),
                modelsDiscoveredAtMs = (obj["modelsDiscoveredAtMs"] as? JsonPrimitive)?.content?.toLongOrNull(),
            )
        }
    }
}
