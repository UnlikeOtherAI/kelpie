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

    private val _approvalError = MutableStateFlow<String?>(null)
    val approvalError: StateFlow<String?> = _approvalError

    fun refresh() {
        _currentPrompt.value = store.visiblePending().firstOrNull()
    }

    fun approve(
        requestId: String,
        persist: Boolean,
    ) {
        if (store.approve(requestId, persist) == null) {
            _approvalError.value = "Could not save approval. Check available storage and try again."
            return
        }
        _approvalError.value = null
        refresh()
    }

    fun deny(requestId: String) {
        store.deny(requestId)
        _approvalError.value = null
        refresh()
    }
}
