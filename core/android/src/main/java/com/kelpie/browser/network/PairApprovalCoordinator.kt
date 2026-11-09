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
    private val _currentPrompt = MutableStateFlow<ComputerRequest?>(null)
    val currentPrompt: StateFlow<ComputerRequest?> = _currentPrompt

    private val _approvalError = MutableStateFlow<String?>(null)
    val approvalError: StateFlow<String?> = _approvalError

    fun refresh() {
        _currentPrompt.value = store.trustedComputers.pending()
    }

    fun approve(requestId: String) {
        if (!store.trustedComputers.approve(requestId)) {
            _approvalError.value = "Could not save approval. Check available storage and try again."
            return
        }
        _approvalError.value = null
        refresh()
    }

    fun deny(requestId: String) {
        store.trustedComputers.deny(requestId)
        _approvalError.value = null
        refresh()
    }
}
