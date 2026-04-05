package com.kelpie.browser.ai

import android.content.Context

object AIState {
    const val PLATFORM_BACKEND = "platform"
    const val OLLAMA_BACKEND = "ollama"
    const val PLATFORM_MODEL_ID = "platform"
    const val DEFAULT_OLLAMA_ENDPOINT = "http://localhost:11434"

    var isAvailable: Boolean = false
        private set
    var backend: String = PLATFORM_BACKEND
    var activeModel: String? = null
    var ollamaEndpoint: String? = null

    fun initialize(context: Context) {
        isAvailable = PlatformAIEngine.isAvailable(context)
        backend = PLATFORM_BACKEND
        activeModel = null
    }
}
