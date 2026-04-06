package com.kelpie.browser.ai

import android.content.Context
import android.content.SharedPreferences

object AIState {
    const val PLATFORM_BACKEND = "platform"
    const val OLLAMA_BACKEND = "ollama"
    const val PLATFORM_MODEL_ID = "platform"
    const val DEFAULT_OLLAMA_ENDPOINT = "http://localhost:11434"

    private const val PREFS_NAME = "kelpie_ai"
    private const val KEY_HF_TOKEN = "huggingFaceToken"

    private var prefs: SharedPreferences? = null

    var isAvailable: Boolean = false
        private set
    var backend: String = PLATFORM_BACKEND
    var activeModel: String? = null
    var ollamaEndpoint: String? = null

    var huggingFaceToken: String
        get() = prefs?.getString(KEY_HF_TOKEN, "") ?: ""
        set(value) {
            prefs?.edit()?.putString(KEY_HF_TOKEN, value)?.apply()
        }

    fun initialize(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        isAvailable = PlatformAIEngine.isAvailable(context)
        backend = PLATFORM_BACKEND
        activeModel = null
    }
}
