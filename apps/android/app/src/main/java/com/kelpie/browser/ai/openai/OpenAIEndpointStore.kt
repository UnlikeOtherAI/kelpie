package com.kelpie.browser.ai.openai

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.util.UUID

/** Plain string persistence (SharedPreferences on Android, a map in tests). */
interface KeyValueStorage {
    fun getString(key: String): String?

    fun putString(
        key: String,
        value: String?,
    )
}

/** Encrypted secret persistence (the Keystore-backed `SecretStore` on Android). */
interface SecretStorage {
    fun get(name: String): String?

    fun set(
        name: String,
        value: String,
    )

    fun remove(name: String)
}

/** The selected endpoint + model (`ai.openaiActive.v1`). */
data class ActiveSelection(
    val endpointId: String,
    val model: String?,
)

/** Tri-state field update: null = keep, `Patch(null)` = clear, `Patch(value)` = set. */
data class Patch<T>(
    val value: T?,
)

data class EndpointSaveInput(
    val id: String? = null,
    val name: String,
    val baseURL: String,
    val apiKey: String? = null,
    val clearApiKey: Boolean = false,
    val model: Patch<String>? = null,
    val contextWindow: Patch<Int>? = null,
    val vision: Patch<Boolean>? = null,
    val toolCalling: Patch<Boolean>? = null,
    val jsonSchema: Patch<Boolean>? = null,
)

/**
 * Persists endpoints as JSON under [ENDPOINTS_KEY] and the active selection under
 * [ACTIVE_KEY]. API keys go to [SecretStorage] as `openai-endpoint.<id>.apiKey`.
 */
class OpenAIEndpointStore(
    private val storage: KeyValueStorage,
    private val secrets: SecretStorage,
    private val newId: () -> String = { UUID.randomUUID().toString() },
) {
    @Volatile
    private var cache: List<OpenAIEndpoint>? = null

    @Synchronized
    fun all(): List<OpenAIEndpoint> {
        cache?.let { return it }
        val parsed =
            storage
                .getString(ENDPOINTS_KEY)
                ?.let { OpenAIJson.parseOrNull(it) as? JsonArray }
                ?.mapNotNull(OpenAIEndpoint::fromJson)
                .orEmpty()
        cache = parsed
        return parsed
    }

    fun get(id: String): OpenAIEndpoint? = all().firstOrNull { it.id == id }

    /** Resolves an id first, then a case-insensitive name. */
    fun find(idOrName: String): OpenAIEndpoint? {
        val key = idOrName.trim()
        return get(key) ?: all().firstOrNull { it.name.equals(key, ignoreCase = true) }
    }

    /** Validates and saves; does not connect. Throws [OpenAIException] on invalid input. */
    @Synchronized
    fun save(input: EndpointSaveInput): OpenAIEndpoint {
        val url = OpenAIEndpointURL.normalize(input.baseURL)
        val name = input.name.trim()
        if (name.isEmpty()) throw OpenAIException("MISSING_PARAM", "name is required")
        input.contextWindow?.value?.let { require(it > 0, "contextWindow must be a positive integer") }
        val existing =
            input.id?.let { id ->
                get(id) ?: throw OpenAIException(OpenAIErrorCode.ENDPOINT_NOT_FOUND, "No endpoint with id $id")
            }
        val base = existing ?: OpenAIEndpoint(id = newId(), name = name, baseURL = url.baseURL)
        val urlChanged = existing != null && existing.baseURL != url.baseURL
        val updated =
            base.copy(
                name = name,
                baseURL = url.baseURL,
                model =
                    input.model
                        .applyTo(base.model)
                        ?.trim()
                        ?.takeIf(String::isNotEmpty),
                user =
                    CapabilityOverrides(
                        contextWindow = input.contextWindow.applyTo(base.user.contextWindow),
                        vision = input.vision.applyTo(base.user.vision),
                        toolCalling = input.toolCalling.applyTo(base.user.toolCalling),
                        jsonSchema = input.jsonSchema.applyTo(base.user.jsonSchema),
                    ),
                models = if (urlChanged) emptyList() else base.models,
                modelsDiscoveredAtMs = if (urlChanged) null else base.modelsDiscoveredAtMs,
                testedToolCalling = if (urlChanged) null else base.testedToolCalling,
                testedToolCallingModel = if (urlChanged) null else base.testedToolCallingModel,
            )
        when {
            input.clearApiKey -> secrets.remove(apiKeyName(updated.id))
            !input.apiKey.isNullOrBlank() -> secrets.set(apiKeyName(updated.id), input.apiKey.trim())
        }
        put(updated)
        return updated
    }

    /** Replaces an existing endpoint record (discovery results, test evidence, model selection). */
    @Synchronized
    fun put(endpoint: OpenAIEndpoint) {
        val list = all().toMutableList()
        val index = list.indexOfFirst { it.id == endpoint.id }
        if (index >= 0) list[index] = endpoint else list += endpoint
        write(list)
    }

    /** Removes the endpoint, its API key and (if it was active) the active selection. */
    @Synchronized
    fun remove(id: String): Boolean {
        val list = all()
        if (list.none { it.id == id }) return false
        write(list.filterNot { it.id == id })
        secrets.remove(apiKeyName(id))
        if (active()?.endpointId == id) setActive(null)
        return true
    }

    fun apiKey(id: String): String? = secrets.get(apiKeyName(id))?.takeIf { it.isNotEmpty() }

    fun hasApiKey(id: String): Boolean = apiKey(id) != null

    fun active(): ActiveSelection? {
        val obj = storage.getString(ACTIVE_KEY)?.let { OpenAIJson.parseObjectOrNull(it) } ?: return null
        val id = OpenAIJson.string(obj["endpointId"]) ?: return null
        return ActiveSelection(id, OpenAIJson.string(obj["model"]))
    }

    fun setActive(selection: ActiveSelection?) {
        if (selection == null) {
            storage.putString(ACTIVE_KEY, null)
            return
        }
        val json = OpenAIJson.fromAny(mapOf("endpointId" to selection.endpointId, "model" to selection.model)) as JsonObject
        storage.putString(ACTIVE_KEY, OpenAIJson.encode(json))
    }

    private fun write(list: List<OpenAIEndpoint>) {
        cache = list
        storage.putString(ENDPOINTS_KEY, OpenAIJson.encode(JsonArray(list.map { it.toJson() })))
    }

    private fun <T> Patch<T>?.applyTo(current: T?): T? = if (this == null) current else value

    private fun require(
        condition: Boolean,
        message: String,
    ) {
        if (!condition) throw OpenAIException("INVALID_PARAM", message)
    }

    companion object {
        const val ENDPOINTS_KEY = "ai.openaiEndpoints.v1"
        const val ACTIVE_KEY = "ai.openaiActive.v1"

        fun apiKeyName(id: String): String = "openai-endpoint.$id.apiKey"
    }
}
