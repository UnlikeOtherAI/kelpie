package com.kelpie.browser.connect

import com.kelpie.browser.ai.AIHttpJson
import com.kelpie.browser.nativecore.NativeCore
import com.kelpie.browser.storage.SecretStore
import org.json.JSONObject

/** Serialized platform calls persist the encrypted recovery state before dispatch or send. */
class ConnectLedger(
    private val secrets: SecretStore,
    owner: String,
) {
    private val handle = NativeCore.connectCreate(secrets.get(KEY).orEmpty(), owner)

    init {
        check(handle != 0L) { "Recovery storage unavailable" }
    }

    fun execute(
        operation: String,
        body: Map<String, Any?>,
    ): Map<String, Any?> {
        val raw = NativeCore.connectExecute(handle, operation, JSONObject(body).toString()) ?: error("Invalid connection protocol")
        val envelope = JSONObject(raw)
        secrets.setDurably(KEY, envelope.getJSONObject("state").toString())
        return AIHttpJson.parseJsonObject(envelope.getJSONObject("decision").toString())
    }

    fun close() = NativeCore.connectDestroy(handle)

    companion object {
        private const val KEY = "nessie.connect.journal.v1"

        fun clear(secrets: SecretStore) = secrets.setDurably(KEY, "")
    }
}
