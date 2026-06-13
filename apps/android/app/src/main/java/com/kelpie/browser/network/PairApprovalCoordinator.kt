package com.kelpie.browser.network

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Observable bridge between the headless [PairingStore] and Compose UI.
 *
 * The HTTPServer pokes [refresh] after creating a pending pair request; the
 * Compose layer collects [currentPrompt] to drive the modal.
 */
class PairApprovalCoordinator(
    val store: PairingStore,
) {
    private val _currentPrompt = MutableStateFlow<PairingStore.PendingRequest?>(null)
    val currentPrompt: StateFlow<PairingStore.PendingRequest?> = _currentPrompt

    fun refresh() {
        _currentPrompt.value = store.visiblePending().firstOrNull()
    }

    fun approve(
        requestId: String,
        persist: Boolean,
    ) {
        store.approve(requestId, persist)
        refresh()
    }

    fun deny(requestId: String) {
        store.deny(requestId)
        refresh()
    }
}
