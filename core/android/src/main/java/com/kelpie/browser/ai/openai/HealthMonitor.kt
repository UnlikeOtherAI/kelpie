package com.kelpie.browser.ai.openai

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Polls the selected endpoint only while the openai backend is active or the AI sheet
 * is open: every 30 s while healthy, 5→10→20→40→60 s while failing. A network change
 * (or selection change) triggers an immediate re-check.
 */
class HealthMonitor(
    private val service: OpenAIEndpointService,
    private val scope: CoroutineScope,
) {
    private val wake = Channel<Unit>(Channel.CONFLATED)
    private var job: Job? = null

    @Volatile
    private var sheetOpen = false

    fun setSheetOpen(open: Boolean) {
        sheetOpen = open
        refresh()
    }

    /** Call after selection or backend changes. */
    @Synchronized
    fun refresh() {
        val shouldRun = service.activeEndpoint() != null && (service.isOpenAIActive || sheetOpen)
        if (!shouldRun) {
            job?.cancel()
            job = null
            return
        }
        if (job?.isActive == true) {
            wake.trySend(Unit)
            return
        }
        job = scope.launch { pollLoop() }
    }

    fun onNetworkChanged() {
        wake.trySend(Unit)
    }

    private suspend fun pollLoop() {
        var failures = 0
        while (scope.isActive) {
            val endpoint = service.activeEndpoint() ?: return
            if (!service.isOpenAIActive && !sheetOpen) return
            service.probe(endpoint, service.store.active()?.model ?: endpoint.model)
            val state = service.healthOf(endpoint.id).state
            failures = if (HealthPollSchedule.isHealthy(state)) 0 else failures + 1
            withTimeoutOrNull(HealthPollSchedule.nextDelayMs(state, failures)) { wake.receive() }
        }
    }
}
