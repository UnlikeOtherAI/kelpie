package com.kelpie.browser.account

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.random.Random

class UOASettingsValue {
    var version: String? = null
        private set
    var value: JsonElement = JsonNull
        private set

    fun receive(
        text: String,
        namespace: String,
        key: String,
    ): Boolean {
        require(text.toByteArray().size <= 300 * 1024)
        val frame = Json.parseToJsonElement(text) as? JsonObject ?: error("Invalid settings frame")

        fun text(field: String) = (frame[field] as? JsonPrimitive)?.takeIf { it.isString }?.content
        require((frame["protocolVersion"] as? JsonPrimitive)?.takeUnless { it.isString }?.intOrNull == 1)
        require(text("namespace") == namespace && text("key") == key)
        val nextVersion = text("version") ?: error("Missing version")
        require(Regex("\"[a-f0-9]{64}\"").matches(nextVersion))
        if (version == nextVersion) return false
        val next =
            when (text("type")) {
                "settings.snapshot" -> frame["value"] ?: error("Missing snapshot")
                "settings.delta" -> {
                    require(version != null && text("baseVersion") == version)
                    val operation = frame["operation"] as? JsonObject ?: error("Missing operation")
                    when ((operation["type"] as? JsonPrimitive)?.contentOrNull) {
                        "replace" -> operation["value"] ?: error("Missing replacement")
                        "splice" -> {
                            val array = value as? JsonArray ?: error("Not an array")

                            fun integer(field: String): Int =
                                (operation[field] as? JsonPrimitive)
                                    ?.takeUnless { it.isString }
                                    ?.intOrNull
                                    ?.takeIf { it in 0..100_000 } ?: error("Invalid index")
                            val index = integer("index")
                            val count = integer("deleteCount")
                            val items = operation["items"] as? JsonArray ?: error("Missing items")
                            require(index <= array.size && count <= array.size - index && array.size - count + items.size <= 100_000)
                            JsonArray(array.take(index) + items + array.drop(index + count))
                        }
                        else -> error("Invalid operation")
                    }
                }
                else -> error("Invalid settings frame")
            }
        value = next
        version = nextVersion
        return true
    }
}

class UOASettingsStream(
    private val scope: CoroutineScope,
    private val namespace: String,
    private val key: String,
    private val request: suspend () -> Request,
    private val receive: (JsonElement) -> Unit,
) {
    private var job: Job? = null
    private var socket: WebSocket? = null
    private var generation = 0

    fun start() {
        if (job != null) return
        val current = ++generation
        job =
            scope.launch {
                var failures = 0
                while (true) {
                    ensureActive()
                    val messages = Channel<String>(32)
                    var connection: WebSocket? = null
                    try {
                        connection =
                            client.newWebSocket(
                                request().also {
                                    ensureActive()
                                    check(generation == current)
                                },
                                object : WebSocketListener() {
                                    override fun onMessage(
                                        webSocket: WebSocket,
                                        text: String,
                                    ) {
                                        if (text.toByteArray().size > 300 * 1024 || messages.trySend(text).isFailure) {
                                            messages.close(IllegalStateException("Settings stream overflow"))
                                            webSocket.cancel()
                                        }
                                    }

                                    override fun onClosing(
                                        webSocket: WebSocket,
                                        code: Int,
                                        reason: String,
                                    ) {
                                        webSocket.close(code, null)
                                    }

                                    override fun onClosed(
                                        webSocket: WebSocket,
                                        code: Int,
                                        reason: String,
                                    ) {
                                        messages.close()
                                    }

                                    override fun onFailure(
                                        webSocket: WebSocket,
                                        t: Throwable,
                                        response: Response?,
                                    ) {
                                        messages.close(t)
                                    }
                                },
                            )
                        socket = connection
                        val state = UOASettingsValue()
                        for (frame in messages) {
                            ensureActive()
                            if (generation != current) return@launch
                            if (state.receive(frame, namespace, key)) receive(state.value)
                            failures = 0
                        }
                    } catch (_: Exception) {
                        ensureActive()
                    } finally {
                        connection?.cancel()
                        if (socket === connection) socket = null
                        messages.cancel()
                    }
                    failures = min(failures + 1, 5)
                    delay(min(30_000L, 1000L shl failures) + Random.nextLong(1000))
                }
            }
    }

    fun stop() {
        generation++
        job?.cancel()
        job = null
        socket?.cancel()
        socket = null
    }

    companion object {
        private val client =
            OkHttpClient
                .Builder()
                .followRedirects(false)
                .followSslRedirects(false)
                .pingInterval(20, TimeUnit.SECONDS)
                .build()
    }
}
