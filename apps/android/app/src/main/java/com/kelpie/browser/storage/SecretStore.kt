package com.kelpie.browser.storage

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Encrypted on-disk store for sensitive strings (API tokens, credentials).
 *
 * Backed by AndroidX `EncryptedSharedPreferences` (AES256-GCM keys, AES256-GCM values)
 * with the master key held in the Android Keystore. The manifest disables
 * `allowBackup`, so the encrypted file cannot be exfiltrated via `adb backup`.
 */
class SecretStore private constructor(
    private val prefs: SharedPreferences,
) {
    fun get(name: String): String? = prefs.getString(name, null)?.takeIf { it.isNotEmpty() }

    fun set(
        name: String,
        value: String,
    ) {
        prefs.edit().putString(name, value).apply()
    }

    fun remove(name: String) {
        prefs.edit().remove(name).apply()
    }

    companion object {
        private const val FILE_NAME = "kelpie_secrets"

        @Volatile
        private var instance: SecretStore? = null

        fun get(context: Context): SecretStore {
            instance?.let { return it }
            synchronized(this) {
                instance?.let { return it }
                val created = SecretStore(open(context))
                instance = created
                return created
            }
        }

        private fun open(context: Context): SharedPreferences {
            val masterKey =
                MasterKey
                    .Builder(context.applicationContext)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
            return EncryptedSharedPreferences.create(
                context.applicationContext,
                FILE_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }
    }
}
