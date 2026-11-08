package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/** One model entry from `GET {base}/models`, displayed exactly as the server names it. */
data class DiscoveredModel(
    val id: String,
    val contextWindow: Int? = null,
    val vision: Boolean? = null,
    val status: String? = null,
) {
    val isLoading: Boolean get() = status == ModelStatus.LOADING || status == ModelStatus.UNLOADED

    fun toPublic(): Map<String, Any?> =
        linkedMapOf(
            "id" to id,
            "contextWindow" to contextWindow,
            "vision" to vision,
            "status" to status,
        )

    fun toJson(): JsonObject = OpenAIJson.fromAny(toPublic()) as JsonObject

    companion object {
        fun fromJson(element: JsonElement?): DiscoveredModel? {
            val obj = OpenAIJson.objectOrNull(element) ?: return null
            val id = OpenAIJson.string(obj["id"])?.takeIf { it.isNotEmpty() } ?: return null
            return DiscoveredModel(
                id = id,
                contextWindow = OpenAIJson.int(obj["contextWindow"]),
                vision = OpenAIJson.boolean(obj["vision"]),
                status = OpenAIJson.string(obj["status"]),
            )
        }
    }
}

object ModelStatus {
    const val LOADED = "loaded"
    const val LOADING = "loading"
    const val UNLOADED = "unloaded"
}

/** Parses model discovery responses (`{"data":[…]}` or `{"models":[…]}`). */
object ModelsParser {
    private val CONTEXT_KEYS =
        listOf("context_length", "max_model_len", "loaded_context_length", "max_context_length", "context_window")

    /** Throws `ENDPOINT_MALFORMED_RESPONSE` for non-JSON or the wrong shape. */
    fun parse(body: String): List<DiscoveredModel> {
        val root =
            OpenAIJson.parseObjectOrNull(body)
                ?: throw malformed("The /models response is not a JSON object")
        val list =
            (root["data"] as? JsonArray)
                ?: (root["models"] as? JsonArray)
                ?: throw malformed("The /models response has no data or models array")
        val seen = HashSet<String>()
        return list.mapNotNull(::parseEntry).filter { seen.add(it.id) }
    }

    private fun parseEntry(element: JsonElement): DiscoveredModel? {
        val obj = element as? JsonObject ?: return null
        val id = OpenAIJson.string(obj["id"])?.takeIf { it.isNotEmpty() } ?: return null
        return DiscoveredModel(
            id = id,
            contextWindow = contextWindow(obj),
            vision = vision(obj),
            status = status(obj),
        )
    }

    private fun contextWindow(obj: JsonObject): Int? {
        OpenAIJson.int(OpenAIJson.objectOrNull(obj["meta"])?.get("n_ctx"))?.takeIf { it > 0 }?.let { return it }
        for (key in CONTEXT_KEYS) {
            OpenAIJson.int(obj[key])?.takeIf { it > 0 }?.let { return it }
        }
        return null
    }

    private fun vision(obj: JsonObject): Boolean? {
        val modalities = OpenAIJson.arrayOrNull(OpenAIJson.objectOrNull(obj["architecture"])?.get("input_modalities"))
        if (modalities != null) {
            return modalities.any { OpenAIJson.string(it)?.lowercase() == "image" }
        }
        val capabilities = OpenAIJson.arrayOrNull(obj["capabilities"]) ?: return null
        return if (capabilities.any { OpenAIJson.string(it)?.lowercase() == "vision" }) true else null
    }

    private fun status(obj: JsonObject): String? {
        val raw =
            OpenAIJson.string(OpenAIJson.objectOrNull(obj["status"])?.get("value"))
                ?: OpenAIJson.string(obj["status"])
                ?: OpenAIJson.string(obj["state"])
                ?: return null
        return when (raw.trim().lowercase()) {
            "loaded" -> ModelStatus.LOADED
            "loading" -> ModelStatus.LOADING
            "unloaded", "not-loaded", "not_loaded" -> ModelStatus.UNLOADED
            else -> null
        }
    }

    private fun malformed(message: String) = OpenAIException(OpenAIErrorCode.ENDPOINT_MALFORMED_RESPONSE, message)
}
