package com.kelpie.browser.ai.openai

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import com.kelpie.browser.ai.AIState
import com.kelpie.browser.ai.LocalInference
import com.kelpie.browser.storage.SecretStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Process-wide wiring for OpenAI-compatible endpoints: SharedPreferences + Keystore
 * `SecretStore` persistence, the HTTP client, health polling and network-change re-checks.
 * Shared by the device HTTP API (AIHandler) and the AI settings sheet.
 */
object OpenAIRuntime {
    private const val PREFS_NAME = "kelpie_ai"

    @Volatile
    private var initialized: OpenAIRuntimeParts? = null

    val service: OpenAIEndpointService get() = parts().service
    val inference: OpenAIInference get() = parts().inference
    val tester: EndpointTester get() = parts().tester
    val monitor: HealthMonitor get() = parts().monitor

    val isInitialized: Boolean get() = initialized != null

    @Synchronized
    fun initialize(context: Context) {
        if (initialized != null) return
        val app = context.applicationContext
        val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val storage =
            object : KeyValueStorage {
                override fun getString(key: String): String? = prefs.getString(key, null)

                override fun putString(
                    key: String,
                    value: String?,
                ) {
                    prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
                }
            }
        val secretStore = SecretStore.get(app)
        val secrets =
            object : SecretStorage {
                override fun get(name: String): String? = secretStore.get(name)

                override fun set(
                    name: String,
                    value: String,
                ) = secretStore.set(name, value)

                override fun remove(name: String) = secretStore.remove(name)
            }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val service =
            OpenAIEndpointService(
                store = OpenAIEndpointStore(storage, secrets),
                client = OpenAIClient(HttpURLConnectionTransport()),
                backend = AIStateBackendSelector,
            )
        val components = OpenAIRuntimeParts(service, OpenAIInference(service, scope), EndpointTester(service), HealthMonitor(service, scope))
        initialized = components
        service.restoreSelection()
        components.monitor.refresh()
        registerNetworkCallback(app, components.monitor)
    }

    fun parts(): OpenAIRuntimeParts = initialized ?: error("OpenAIRuntime.initialize(context) has not been called")

    private fun registerNetworkCallback(
        context: Context,
        monitor: HealthMonitor,
    ) {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return
        runCatching {
            connectivity.registerDefaultNetworkCallback(
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) = monitor.onNetworkChanged()

                    override fun onLost(network: Network) = monitor.onNetworkChanged()
                },
            )
        }
    }
}

/** Maps backend selection onto the existing [AIState] globals. */
object AIStateBackendSelector : BackendSelector {
    override suspend fun prepareOpenAI() { LocalInference.execute("unload") }
    override fun currentBackend(): String = AIState.backend

    override fun selectOpenAI() {
        AIState.backend = AIState.OPENAI_BACKEND
        AIState.activeModel = null
    }

    override fun unloadOpenAI() {
        if (AIState.backend == AIState.OPENAI_BACKEND) {
            AIState.backend = AIState.PLATFORM_BACKEND
            AIState.activeModel = null
        }
    }
}
