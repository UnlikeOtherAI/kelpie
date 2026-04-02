package com.mollotov.browser.ai

import android.content.Context
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PlatformAIEngine(private val context: Context) {
    companion object {
        @Suppress("UNUSED_PARAMETER")
        fun isAvailable(context: Context): Boolean {
            // TODO: Check via Google AI Edge SDK GenerativeModel.isAvailable()
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        }
    }

    suspend fun infer(prompt: String): String = withContext(Dispatchers.IO) {
        if (!isAvailable(context)) {
            throw IllegalStateException("Platform AI is unavailable on this device")
        }
        if (prompt.isBlank()) {
            throw IllegalArgumentException("Prompt must not be blank")
        }
        // TODO: Use com.google.ai.edge GenerativeModel when the SDK is integrated.
        throw UnsupportedOperationException("Platform AI not yet wired - requires AI Edge SDK")
    }
}
