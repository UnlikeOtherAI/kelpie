package com.kelpie.browser.ai.openai

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** Reads and switches Kelpie's active AI backend (AIState on Android, a fake in tests). */
interface BackendSelector {
    fun currentBackend(): String

    fun selectOpenAI()

    /** Reverts to the platform default; used when the active endpoint is removed. */
    fun unloadOpenAI()
}

data class DiscoveryResult(
    val models: List<DiscoveredModel>,
    val warning: String?,
)

/**
 * Endpoint management: CRUD, model discovery, health and backend selection.
 * Saving never connects; only discovery, tests, health checks and selection do.
 */
class OpenAIEndpointService(
    val store: OpenAIEndpointStore,
    val client: OpenAIClient,
    private val backend: BackendSelector,
    val clock: () -> Long = System::currentTimeMillis,
) {
    private val health = ConcurrentHashMap<String, EndpointHealth>()
    private val inFlight = ConcurrentHashMap<String, AtomicInteger>()
    private val revisionFlow = MutableStateFlow(0L)

    /** Bumped on every endpoint, health or selection change so UI can refresh. */
    val revision: StateFlow<Long> get() = revisionFlow

    val isOpenAIActive: Boolean get() = backend.currentBackend() == OPENAI_BACKEND

    fun activeEndpoint(): OpenAIEndpoint? = store.active()?.let { store.get(it.endpointId) }

    fun healthOf(id: String): EndpointHealth = health[id] ?: EndpointHealth()

    fun inFlightCount(id: String): Int = inFlight[id]?.get() ?: 0

    fun healthPublic(id: String): Map<String, Any?> = healthOf(id).toPublic(clock(), inFlightCount(id))

    fun endpointPublic(endpoint: OpenAIEndpoint): Map<String, Any?> = endpoint.toPublic(store.hasApiKey(endpoint.id), healthPublic(endpoint.id))

    /** `ai-endpoints` result. */
    fun listPublic(): Map<String, Any?> {
        val active = store.active()
        return linkedMapOf(
            "endpoints" to store.all().map(::endpointPublic),
            "activeEndpointId" to active?.endpointId,
            "activeModel" to active?.let { it.model ?: store.get(it.endpointId)?.model },
            "executionHost" to EXECUTION_HOST,
        )
    }

    fun resolve(id: String?): OpenAIEndpoint {
        val key = id?.trim().orEmpty()
        if (key.isEmpty()) throw OpenAIException("MISSING_PARAM", "id is required")
        return store.find(key) ?: throw OpenAIException(OpenAIErrorCode.ENDPOINT_NOT_FOUND, "No endpoint named or with id $key")
    }

    fun save(input: EndpointSaveInput): OpenAIEndpoint {
        val previous = input.id?.let(store::get)
        val saved = store.save(input)
        if (previous != null && (previous.baseURL != saved.baseURL || previous.model != saved.model)) {
            health.remove(saved.id)
        }
        if (store.active()?.endpointId == saved.id && previous?.model != saved.model) {
            store.setActive(ActiveSelection(saved.id, saved.model))
        }
        bump()
        return saved
    }

    /** Removing the active endpoint unloads the openai backend (no fallback endpoint is chosen). */
    fun remove(id: String): Boolean {
        val endpoint = resolve(id)
        val wasActive = store.active()?.endpointId == endpoint.id
        val removed = store.remove(endpoint.id)
        health.remove(endpoint.id)
        if (wasActive && isOpenAIActive) backend.unloadOpenAI()
        bump()
        return removed
    }

    /** `ai-endpoint-models`: discovery errors propagate as [OpenAIException]. */
    suspend fun discover(id: String): DiscoveryResult {
        val endpoint = resolve(id)
        val outcome = probe(endpoint, endpoint.model)
        if (outcome is ProbeOutcome.Failed) throw OpenAIException(outcome.code, outcome.message, outcome.httpStatus)
        if (outcome is ProbeOutcome.DiscoveryUnsupported) {
            throw OpenAIException(
                OpenAIErrorCode.MODEL_DISCOVERY_UNSUPPORTED,
                "This server does not list models; type the model ID instead",
            )
        }
        val models = (outcome as ProbeOutcome.Discovered).models
        return DiscoveryResult(models, if (models.isEmpty()) EMPTY_MODELS_WARNING else null)
    }

    /** Probes `GET /models`, caches discovered models on the endpoint and updates health. */
    suspend fun probe(
        endpoint: OpenAIEndpoint,
        selectedModel: String?,
    ): ProbeOutcome {
        val started = clock()
        val outcome =
            try {
                val models = client.listModels(endpoint.url, store.apiKey(endpoint.id))
                store.get(endpoint.id)?.let { store.put(it.copy(models = models, modelsDiscoveredAtMs = clock())) }
                ProbeOutcome.Discovered(models, clock() - started)
            } catch (e: CancellationException) {
                throw e
            } catch (e: OpenAIException) {
                if (e.code == OpenAIErrorCode.MODEL_DISCOVERY_UNSUPPORTED) {
                    ProbeOutcome.DiscoveryUnsupported(clock() - started)
                } else {
                    ProbeOutcome.Failed(e.code, e.message, e.httpStatus, clock() - started)
                }
            }
        recordProbe(endpoint.id, outcome, selectedModel)
        return outcome
    }

    fun recordProbe(
        id: String,
        outcome: ProbeOutcome,
        selectedModel: String?,
    ) {
        health[id] = HealthEvaluator.evaluate(health[id], outcome, selectedModel, clock())
        bump()
    }

    fun recordGeneration(
        id: String,
        selectedModel: String?,
    ) {
        health[id] = HealthEvaluator.recordGeneration(healthOf(id), selectedModel, clock())
        bump()
    }

    /** Records a failure observed during inference (offline / auth / loading) without a separate probe. */
    fun recordInferenceFailure(
        id: String,
        error: OpenAIException,
    ) {
        val relevant =
            error.code in
                setOf(OpenAIErrorCode.ENDPOINT_UNREACHABLE, OpenAIErrorCode.ENDPOINT_AUTH_FAILED, OpenAIErrorCode.ENDPOINT_LOADING) ||
                error.httpStatus == 429
        if (relevant) recordProbe(id, ProbeOutcome.Failed(error.code, error.message, error.httpStatus), store.get(id)?.model)
    }

    /** `ai-endpoint-health`: cached unless [refresh] or stale. Defaults to the active endpoint. */
    suspend fun health(
        id: String?,
        refresh: Boolean,
    ): Map<String, Any?> {
        val endpoint =
            if (id.isNullOrBlank()) {
                activeEndpoint() ?: throw OpenAIException(OpenAIErrorCode.ENDPOINT_NOT_FOUND, "No active endpoint; pass id")
            } else {
                resolve(id)
            }
        if (refresh) probe(endpoint, endpoint.model)
        return healthPublic(endpoint.id)
    }

    /** `ai-load` for the openai backend. Fails on unreachable / auth_failed without changing the backend. */
    suspend fun activate(
        idOrName: String?,
        model: String?,
    ): Map<String, Any?> {
        val endpoint = resolve(idOrName)
        val selected = model?.trim()?.takeIf { it.isNotEmpty() } ?: endpoint.model
        if (selected == null) {
            throw OpenAIException(OpenAIErrorCode.NO_MODEL_SELECTED, "Choose a model for ${endpoint.name} or pass model")
        }
        val started = clock()
        probe(endpoint, selected)
        val state = healthOf(endpoint.id).state
        if (state == HealthState.UNREACHABLE || state == HealthState.AUTH_FAILED) {
            val code = if (state == HealthState.AUTH_FAILED) OpenAIErrorCode.ENDPOINT_AUTH_FAILED else OpenAIErrorCode.ENDPOINT_UNREACHABLE
            throw OpenAIException(code, healthOf(endpoint.id).message ?: "The endpoint is ${state.wire}")
        }
        val current = store.get(endpoint.id) ?: endpoint
        if (current.model != selected) store.put(current.copy(model = selected))
        store.setActive(ActiveSelection(endpoint.id, selected))
        backend.selectOpenAI()
        bump()
        val result =
            linkedMapOf<String, Any?>(
                "model" to selected,
                "backend" to OPENAI_BACKEND,
                "endpoint" to endpoint.summaryPublic(),
                "health" to healthPublic(endpoint.id),
                "loadTimeMs" to (clock() - started),
            )
        if (state == HealthState.MODEL_MISSING) result["warning"] = healthOf(endpoint.id).message
        return result
    }

    /** Clears the persisted selection (ai-unload) so it is not restored on next launch. */
    fun clearSelection() {
        store.setActive(null)
        bump()
    }

    /** Restores the persisted selection at launch. Health starts `unknown` until the first probe. */
    fun restoreSelection() {
        if (activeEndpoint() != null) backend.selectOpenAI() else store.active()?.let { store.setActive(null) }
    }

    /** `ai-status` additions while the openai backend is active. */
    fun statusPublic(): Map<String, Any?> {
        val endpoint = activeEndpoint()
        return linkedMapOf(
            "backend" to OPENAI_BACKEND,
            "loaded" to (endpoint != null),
            "model" to (store.active()?.model ?: endpoint?.model),
            "endpoint" to endpoint?.summaryPublic(),
            "health" to endpoint?.let { healthPublic(it.id) },
            "capabilities" to capabilityList(endpoint),
            "endpointCapabilities" to endpoint?.capabilitiesPublic(),
            "executionHost" to EXECUTION_HOST,
        )
    }

    fun beginRequest(id: String) {
        inFlight.getOrPut(id) { AtomicInteger() }.incrementAndGet()
        bump()
    }

    fun endRequest(id: String) {
        inFlight[id]?.decrementAndGet()
        bump()
    }

    private fun capabilityList(endpoint: OpenAIEndpoint?): List<String> {
        if (endpoint == null) return emptyList()
        return if (endpoint.vision.value == true) listOf("text", "vision") else listOf("text")
    }

    fun bump() {
        revisionFlow.value = revisionFlow.value + 1
    }

    companion object {
        const val OPENAI_BACKEND = "openai"
        const val EMPTY_MODELS_WARNING = "The server returned no models."
        const val LOOPBACK_MEANS =
            "localhost means this phone. To use a server on your computer, enter its LAN or .local address " +
                "and make sure that server listens on the network."
        val EXECUTION_HOST: Map<String, Any?> = linkedMapOf("platform" to "android", "loopbackMeans" to LOOPBACK_MEANS)
    }
}
