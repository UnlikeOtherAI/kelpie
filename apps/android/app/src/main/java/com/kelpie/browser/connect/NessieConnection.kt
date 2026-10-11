package com.kelpie.browser.connect

import android.content.Context
import com.kelpie.browser.account.UOAAccount
import com.kelpie.browser.account.UOATransport
import com.kelpie.browser.ai.AIHttpJson
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.storage.SecretStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.WebSocket
import org.json.JSONObject
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Native account-backed outbound WSS; no account access token reaches Nessie. */
object NessieConnection {
    const val RESOURCE = "https://api.nessie.works/api/kelpie/connect"
    const val GATEWAY = "wss://api.nessie.works/api/kelpie/connect"

    data class State(
        val status: String = "Signed out",
        val paused: Boolean = false,
        val running: Boolean = false,
        val requiresSignIn: Boolean = false,
    )

    private val mutableState = MutableStateFlow(State())
    val state = mutableState.asStateFlow()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val client = OkHttpClient.Builder().build()
    private var appContext: Context? = null
    private var host: HandlerContext? = null
    private var browser: ConnectBrowser? = null
    private var secrets: SecretStore? = null
    private var ledger: ConnectLedger? = null
    private var owner: String? = null
    private var generation: String? = null
    private var epoch = UUID.randomUUID()
    private var socket: WebSocket? = null
    private var transportAuthority: AtomicBoolean? = null
    private var lifetime: Job? = null
    private var renewal: Job? = null
    private var heartbeat: Job? = null
    private var action: Job? = null
    private var currentCommand: Map<String, Any?>? = null
    private var accountObserver: Job? = null
    private var foreground = false
    private var controlledTab: String? = null
    private var remoteTabMutation = false

    fun start(
        context: Context,
        handlers: HandlerContext,
    ) {
        appContext = context.applicationContext
        secrets = SecretStore.get(context)
        host = handlers
        browser = ConnectBrowser(handlers, java.io.File(context.filesDir, "local-models"))
        if (accountObserver == null) {
            accountObserver =
                scope.launch {
                    UOAAccount.state
                        .map { it.profile?.subject }
                        .distinctUntilChanged()
                        .collect { accountChanged(it) }
                }
        }
    }

    fun detach(handlers: HandlerContext) {
        if (host !== handlers) return
        setForeground(false)
        host = null
        browser = null
    }

    fun setForeground(active: Boolean) {
        foreground = active
        if (!active) stopCurrent("App entered background")
        publishLifecycle()
    }

    fun togglePause() {
        mutableState.value = state.value.copy(paused = !state.value.paused)
        if (state.value.paused) stopCurrent("Paused on device")
        publishLifecycle()
    }

    fun stop() {
        mutableState.value = state.value.copy(paused = true)
        stopCurrent("Stopped on device")
        publishLifecycle()
    }

    fun claimTab(tabId: String) {
        controlledTab = tabId
    }

    fun personChangedTab() {
        personTookControl("The person changed tabs")
    }

    fun personInteracted() {
        personTookControl("The person took control of the page")
    }

    private fun personTookControl(reason: String) {
        if (controlledTab == null || remoteTabMutation) return
        mutableState.value = state.value.copy(paused = true)
        stopCurrent(reason)
        publishLifecycle()
    }

    fun <T> changeTabRemotely(action: () -> T): T {
        remoteTabMutation = true
        return try {
            action()
        } finally {
            remoteTabMutation = false
        }
    }

    fun renewConsent() {
        UOAAccount.signOut()
        UOAAccount.signIn()
    }

    private val lifecycle: String get() = if (foreground && !state.value.paused && browser?.ready == true) "ready" else "paused"
    val canMutate: Boolean get() =
        foreground &&
            !state.value.paused &&
            socket != null &&
            transportAuthority?.get() == true &&
            generation != null &&
            owner != null &&
            UOAAccount.state.value.profile
                ?.subject == owner

    private fun accountChanged(subject: String?) {
        if (owner == subject) return
        val hadOwner = owner != null
        stopCurrent("Account changed")
        lifetime?.cancel()
        close()
        epoch = UUID.randomUUID()
        owner = subject
        controlledTab = null
        ledger?.close()
        ledger = null
        mutableState.value = State()
        val store = secrets ?: return
        if (hadOwner) {
            try {
                ConnectLedger.clear(store)
            } catch (_: Exception) {
                mutableState.value = State(status = "Recovery storage unavailable")
                return
            }
        }
        if (subject == null) return
        try {
            ledger = ConnectLedger(store, subject)
        } catch (_: Exception) {
            mutableState.value = State(status = "Recovery storage unavailable")
            return
        }
        val current = epoch
        lifetime = scope.launch { connectLoop(current) }
    }

    fun authorizes(command: Map<String, Any?>): Boolean =
        canMutate &&
            state.value.running &&
            ConnectAuthorization.from(command)?.matches(currentCommand) == true

    private suspend fun connectLoop(current: UUID) {
        var backoff = 2000L
        while (scope.isActive && epoch == current && owner != null) {
            try {
                mutableState.value = state.value.copy(status = "Connecting to Nessie")
                val ticket = issueTicket()
                if (epoch != current) return
                val frames = Channel<String>(64)
                val opened = kotlinx.coroutines.CompletableDeferred<Unit>()
                val authority = AtomicBoolean(true)
                val connection = client.newWebSocket(Request.Builder().url(GATEWAY).build(), ConnectSocketListener(frames, opened, authority))
                socket = connection
                transportAuthority = authority
                opened.await()
                val ready = browser?.modelReady() ?: false
                send(
                    mapOf(
                        "type" to "hello",
                        "protocol" to 1,
                        "ticket" to ticket.value,
                        "installationId" to installationId(),
                        "label" to
                            deviceLabel(),
                        "platform" to "android",
                        "capabilities" to listOf("browser.control", "page.extract"),
                        "lifecycle" to lifecycle,
                        "modelReady" to ready,
                        "modelInstalled" to (browser?.modelInstalled ?: false),
                        "modelCapabilities" to listOf("text"),
                        "delegatedBrowsing" to false,
                    ),
                    connection,
                )
                renewal = scope.launch { renewTickets(connection, current, ticket.expires) }
                for (raw in frames) {
                    if (epoch != current || socket !== connection) return
                    receive(AIHttpJson.parseJsonObject(raw), connection)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (epoch != current) return
                mutableState.value = state.value.copy(status = "Nessie connection unavailable")
                if (error is UOATransport.Failure && error.status == 403) {
                    mutableState.value = state.value.copy(status = "Sign in again to connect Nessie", requiresSignIn = true)
                    close()
                    return
                }
            }
            stopCurrent("Connection lost; reconcile page before continuing")
            close()
            delay(backoff)
            backoff = (backoff * 2).coerceAtMost(60000)
        }
    }

    private data class Ticket(
        val value: String,
        val expires: Long,
    )

    private suspend fun issueTicket(): Ticket {
        val response = UOAAccount.request("/oauth/kelpie/connect", "POST", JSONObject(mapOf("resource" to RESOURCE)).toString())
        val json = JSONObject(String(response.data, Charsets.UTF_8))
        check(json.getString("gateway_url") == GATEWAY && json.getString("token_type") == "Bearer")
        val ticket = json.getString("connection_ticket")
        val expires = json.getLong("expires_in")
        check(ticket.isNotEmpty() && expires in 1..120)
        return Ticket(ticket, expires)
    }

    private suspend fun renewTickets(
        connection: WebSocket,
        current: UUID,
        expires: Long,
    ) {
        var expiry = expires
        while (epoch == current && socket === connection) {
            delay((expiry / 2).coerceIn(1, 60) * 1000)
            if (epoch != current || socket !== connection) return
            try {
                val ticket = issueTicket()
                val gen = generation ?: return
                if (socket !== connection) return
                send(mapOf("type" to "auth", "generation" to gen, "ticket" to ticket.value), connection)
                expiry = ticket.expires
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                stopCurrent("Connection authority unavailable; reconcile page before continuing")
                transportAuthority?.set(false)
                connection.cancel()
                return
            }
        }
    }

    private suspend fun receive(
        frame: Map<String, Any?>,
        connection: WebSocket,
    ) {
        val journal = ledger ?: error("Recovery storage unavailable")
        val decision = journal.execute("receive", frame)
        if (decision["kind"] == "welcome") {
            generation = frame["generation"] as String
            publishLifecycle()
            startHeartbeat(connection)
        }
        sendFrames(decision, connection)
        when (decision["kind"]) {
            "command" -> {
                @Suppress("UNCHECKED_CAST")
                val command = decision["command"] as Map<String, Any?>
                if (state.value.running || lifecycle != "ready" || !canMutate || socket !== connection) {
                    finish(command, "failed", error = "Device is paused or busy", connection = connection)
                    return
                }
                currentCommand = command
                mutableState.value = state.value.copy(running = true)
                action = scope.launch { perform(command, connection) }
            }
            "cancel" ->
                if (frame["jobId"] == currentCommand?.get("jobId") && frame["attemptId"] == currentCommand?.get("attemptId")) {
                    action?.cancel()
                    browser?.cancelInference()
                    currentCommand = null
                    mutableState.value = state.value.copy(running = false)
                }
        }
    }

    private suspend fun perform(
        command: Map<String, Any?>,
        connection: WebSocket,
    ) {
        var expiry: Job? = null
        try {
            val remaining = Instant.parse(command["deadline"] as String).toEpochMilli() - System.currentTimeMillis()
            check(remaining in 1..86400000) { "Job deadline expired" }
            expiry =
                scope.launch {
                    delay(remaining)
                    stopCurrent("Job deadline expired; reconcile page before continuing")
                }
            val target = browser ?: error("Browser unavailable")
            val output = target.execute(command)
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            finish(command, "completed", output = output, connection = connection)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            runCatching { finish(command, "failed", error = ConnectText.bounded(error.message ?: "Browser action failed", 2000), connection = connection) }
        } finally {
            expiry?.cancel()
            if (command["jobId"] == currentCommand?.get("jobId") && command["attemptId"] == currentCommand?.get("attemptId")) {
                currentCommand = null
                mutableState.value = state.value.copy(running = false)
            }
        }
    }

    private fun finish(
        command: Map<String, Any?>,
        state: String,
        output: Map<String, Any?>? = null,
        error: String? = null,
        connection: WebSocket? = null,
    ) {
        val result = mutableMapOf("jobId" to command["jobId"], "attemptId" to command["attemptId"], "state" to state)
        if (output != null) result["output"] = output
        if (error != null) result["error"] = error
        val decision = ledger?.execute("complete", result) ?: return
        if (connection != null && socket === connection) sendFrames(decision, connection)
    }

    private fun stopCurrent(reason: String) {
        action?.cancel()
        browser?.cancelInference()
        val command = currentCommand ?: return
        currentCommand = null
        mutableState.value = state.value.copy(running = false)
        try {
            finish(command, "cancelled", error = reason, connection = socket)
        } catch (_: Exception) {
            mutableState.value = state.value.copy(status = "Recovery storage unavailable")
            close()
        }
    }

    private fun startHeartbeat(connection: WebSocket) {
        heartbeat?.cancel()
        heartbeat =
            scope.launch {
                while (socket === connection) {
                    publishHeartbeat(connection)
                    delay(10000)
                }
            }
    }

    private fun publishLifecycle() {
        val connection = socket ?: return
        mutableState.value = state.value.copy(status = if (lifecycle == "ready") "Connected to Nessie" else "Nessie paused")
        scope.launch { publishHeartbeat(connection) }
    }

    private suspend fun publishHeartbeat(connection: WebSocket) {
        val gen = generation ?: return
        val ready = browser?.modelReady() ?: false
        runCatching {
            send(
                mapOf(
                    "type" to "heartbeat",
                    "generation" to gen,
                    "lifecycle" to lifecycle,
                    "modelReady" to ready,
                    "modelInstalled" to (browser?.modelInstalled ?: false),
                    "modelCapabilities" to listOf("text"),
                    "delegatedBrowsing" to false,
                ),
                connection,
            )
        }
    }

    private fun sendFrames(
        decision: Map<String, Any?>,
        connection: WebSocket,
    ) {
        @Suppress("UNCHECKED_CAST")
        val frames = decision["frames"] as? List<Map<String, Any?>> ?: return
        frames.forEach { send(it, connection) }
    }

    private fun send(
        frame: Map<String, Any?>,
        connection: WebSocket,
    ) {
        val raw = JSONObject(frame).toString()
        check(raw.toByteArray().size <= 1024 * 1024 && connection.send(raw)) { "Gateway send failed" }
    }

    private fun close() {
        transportAuthority?.set(false)
        renewal?.cancel()
        heartbeat?.cancel()
        socket?.cancel()
        socket = null
        generation = null
    }

    private fun deviceLabel(): String =
        ConnectText.bounded(
            runCatching {
                android.provider.Settings.Global
                    .getString(appContext?.contentResolver, android.provider.Settings.Global.DEVICE_NAME)
                    ?.takeIf { it.isNotBlank() }
            }.getOrNull() ?: android.os.Build.MODEL,
            120,
        )

    private fun installationId(): String {
        val prefs = appContext?.getSharedPreferences("nessie.connect", Context.MODE_PRIVATE) ?: error("App unavailable")
        val stored = prefs.getString("installation", null)
        if (stored != null && runCatching { UUID.fromString(stored) }.isSuccess) return stored
        val id = UUID.randomUUID().toString()
        check(prefs.edit().putString("installation", id).commit())
        return id
    }
}
