package com.kelpie.browser.ai.openai

import java.time.Instant

enum class HealthState(
    val wire: String,
    val online: Boolean,
) {
    UNKNOWN("unknown", false),
    UNREACHABLE("unreachable", false),
    AUTH_FAILED("auth_failed", false),
    LOADING("loading", true),
    NO_MODEL("no_model", true),
    MODEL_MISSING("model_missing", true),
    READY("ready", true),
    BUSY("busy", true),
}

/** The last health observation for one endpoint. Times are epoch milliseconds. */
data class EndpointHealth(
    val state: HealthState = HealthState.UNKNOWN,
    val checkedAtMs: Long? = null,
    val latencyMs: Long? = null,
    val message: String? = null,
    val modelListed: Boolean? = null,
    val modelStatus: String? = null,
    val generationVerifiedAtMs: Long? = null,
) {
    fun isStale(nowMs: Long): Boolean = checkedAtMs == null || nowMs - checkedAtMs > STALE_AFTER_MS

    /**
     * The state callers should see now: stale results read as `unknown`, and a ready
     * endpoint with Kelpie requests in flight reads as `busy`.
     */
    fun effectiveState(
        nowMs: Long,
        inFlight: Int,
    ): HealthState =
        when {
            isStale(nowMs) -> HealthState.UNKNOWN
            state == HealthState.READY && inFlight > 0 -> HealthState.BUSY
            else -> state
        }

    fun toPublic(
        nowMs: Long,
        inFlight: Int,
    ): Map<String, Any?> {
        val effective = effectiveState(nowMs, inFlight)
        return linkedMapOf(
            "state" to effective.wire,
            "online" to effective.online,
            "checkedAt" to checkedAtMs?.let(::isoTimestamp),
            "stale" to isStale(nowMs),
            "latencyMs" to latencyMs,
            "message" to message,
            "modelListed" to modelListed,
            "modelStatus" to modelStatus,
            "generationVerifiedAt" to generationVerifiedAtMs?.let(::isoTimestamp),
        )
    }

    companion object {
        const val STALE_AFTER_MS = 90_000L

        fun isoTimestamp(epochMs: Long): String = Instant.ofEpochMilli(epochMs).toString()
    }
}

/** What one probe of `GET {base}/models` observed. */
sealed class ProbeOutcome {
    abstract val latencyMs: Long?

    data class Discovered(
        val models: List<DiscoveredModel>,
        override val latencyMs: Long?,
    ) : ProbeOutcome()

    data class DiscoveryUnsupported(
        override val latencyMs: Long?,
    ) : ProbeOutcome()

    data class Failed(
        val code: String,
        val message: String,
        val httpStatus: Int? = null,
        override val latencyMs: Long? = null,
    ) : ProbeOutcome()
}

/** Pure health state machine. A 200 alone never means `ready`. */
object HealthEvaluator {
    fun evaluate(
        previous: EndpointHealth?,
        outcome: ProbeOutcome,
        selectedModel: String?,
        nowMs: Long,
    ): EndpointHealth {
        val next =
            when (outcome) {
                is ProbeOutcome.Failed -> fromFailure(outcome)
                is ProbeOutcome.Discovered -> fromDiscovery(outcome.models, selectedModel)
                is ProbeOutcome.DiscoveryUnsupported -> fromUnsupported(previous, selectedModel)
            }
        // generationVerifiedAt survives only while the endpoint stays online.
        val carried = if (previous?.state?.online == true) previous.generationVerifiedAtMs else null
        return next.copy(
            checkedAtMs = nowMs,
            latencyMs = outcome.latencyMs,
            generationVerifiedAtMs = if (next.state.online) next.generationVerifiedAtMs ?: carried else null,
        )
    }

    /** Records a successful generation test; resolves an unsupported-discovery endpoint to `ready`. */
    fun recordGeneration(
        previous: EndpointHealth,
        selectedModel: String?,
        nowMs: Long,
    ): EndpointHealth {
        val verified = previous.copy(generationVerifiedAtMs = nowMs)
        if (previous.state.online && previous.modelListed == null && selectedModel != null) {
            return verified.copy(state = HealthState.READY, message = null)
        }
        return verified
    }

    private fun fromFailure(outcome: ProbeOutcome.Failed): EndpointHealth {
        val state =
            when {
                outcome.code == OpenAIErrorCode.ENDPOINT_AUTH_FAILED -> HealthState.AUTH_FAILED
                outcome.httpStatus == 429 -> HealthState.BUSY
                outcome.httpStatus == 503 && outcome.message.contains("busy", ignoreCase = true) -> HealthState.BUSY
                outcome.code == OpenAIErrorCode.ENDPOINT_LOADING -> HealthState.LOADING
                else -> HealthState.UNREACHABLE
            }
        return EndpointHealth(state = state, message = outcome.message)
    }

    private fun fromDiscovery(
        models: List<DiscoveredModel>,
        selectedModel: String?,
    ): EndpointHealth {
        if (selectedModel.isNullOrEmpty()) {
            return EndpointHealth(state = HealthState.NO_MODEL, message = "No model selected")
        }
        val model =
            models.firstOrNull { it.id == selectedModel }
                ?: return EndpointHealth(
                    state = HealthState.MODEL_MISSING,
                    modelListed = false,
                    message = "The server does not list $selectedModel",
                )
        if (model.isLoading) {
            return EndpointHealth(
                state = HealthState.LOADING,
                modelListed = true,
                modelStatus = model.status,
                message = "The model is ${model.status}",
            )
        }
        return EndpointHealth(state = HealthState.READY, modelListed = true, modelStatus = model.status)
    }

    private fun fromUnsupported(
        previous: EndpointHealth?,
        selectedModel: String?,
    ): EndpointHealth {
        if (selectedModel.isNullOrEmpty()) {
            return EndpointHealth(state = HealthState.NO_MODEL, message = "No model selected")
        }
        val verified = if (previous?.state?.online == true) previous.generationVerifiedAtMs else null
        if (verified != null) {
            return EndpointHealth(state = HealthState.READY, generationVerifiedAtMs = verified)
        }
        return EndpointHealth(
            state = HealthState.MODEL_MISSING,
            message = "The server does not list models; run a generation test to confirm $selectedModel",
        )
    }
}

/** Polling cadence: 30 s while healthy, 5→10→20→40→60 s while failing. */
object HealthPollSchedule {
    const val HEALTHY_INTERVAL_MS = 30_000L
    private val BACKOFF_MS = longArrayOf(5_000, 10_000, 20_000, 40_000, 60_000)

    fun isHealthy(state: HealthState): Boolean = state.online && state != HealthState.LOADING

    /** [consecutiveFailures] counts unhealthy checks in a row, including the latest one. */
    fun nextDelayMs(
        state: HealthState,
        consecutiveFailures: Int,
    ): Long {
        if (isHealthy(state)) return HEALTHY_INTERVAL_MS
        val index = (consecutiveFailures - 1).coerceIn(0, BACKOFF_MS.lastIndex)
        return BACKOFF_MS[index]
    }
}
