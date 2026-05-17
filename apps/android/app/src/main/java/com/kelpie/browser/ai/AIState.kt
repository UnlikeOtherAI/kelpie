package com.kelpie.browser.ai

import android.content.Context
import com.kelpie.browser.storage.SecretStore

object AIState {
    const val PLATFORM_BACKEND = "platform"
    const val OLLAMA_BACKEND = "ollama"
    const val PLATFORM_MODEL_ID = "platform"
    const val DEFAULT_OLLAMA_ENDPOINT = "http://localhost:11434"

    private const val LEGACY_PREFS_NAME = "kelpie_ai"
    private const val KEY_HF_TOKEN = "huggingFaceToken"

    private var secretStore: SecretStore? = null

    var isAvailable: Boolean = false
        private set
    var backend: String = PLATFORM_BACKEND
    var activeModel: String? = null
    var ollamaEndpoint: String? = null

    var huggingFaceToken: String
        get() = secretStore?.get(KEY_HF_TOKEN) ?: ""
        set(value) {
            val store = secretStore ?: return
            if (value.isEmpty()) {
                store.remove(KEY_HF_TOKEN)
            } else {
                store.set(KEY_HF_TOKEN, value)
            }
        }

    fun initialize(context: Context) {
        val store = SecretStore.get(context)
        secretStore = store
        migrateLegacyHfToken(context, store)
        isAvailable = PlatformAIEngine.isAvailable(context)
        backend = PLATFORM_BACKEND
        activeModel = null
    }

    /**
     * Move any plaintext HF token previously stored in `SharedPreferences("kelpie_ai")`
     * into the encrypted [SecretStore] and remove the plaintext copy.
     */
    private fun migrateLegacyHfToken(
        context: Context,
        store: SecretStore,
    ) {
        val legacy = context.getSharedPreferences(LEGACY_PREFS_NAME, Context.MODE_PRIVATE)
        val plaintext = legacy.getString(KEY_HF_TOKEN, null) ?: return
        if (plaintext.isNotEmpty() && store.get(KEY_HF_TOKEN) == null) {
            store.set(KEY_HF_TOKEN, plaintext)
        }
        legacy.edit().remove(KEY_HF_TOKEN).apply()
    }
}
