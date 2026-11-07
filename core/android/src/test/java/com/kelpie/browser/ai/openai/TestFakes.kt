package com.kelpie.browser.ai.openai

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import java.util.Collections
import kotlin.random.Random

/** Canned response for [FakeTransport]; [body] is delivered in [chunkSizes] pieces (random when null). */
class FakeResponse(
    val status: Int = 200,
    val contentType: String? = "application/json",
    val body: ByteArray = ByteArray(0),
    val chunkSizes: List<Int>? = null,
    val failure: OpenAIException? = null,
    val hang: Boolean = false,
) {
    constructor(status: Int, body: String, contentType: String? = "application/json") :
        this(status = status, contentType = contentType, body = body.toByteArray(Charsets.UTF_8))
}

/** Records requests and replays responses chosen by [respond]. */
class FakeTransport(
    private val random: Random = Random(42),
    var respond: (TransportRequest) -> FakeResponse,
) : OpenAITransport {
    val requests: MutableList<TransportRequest> = Collections.synchronizedList(mutableListOf())
    val started = CompletableDeferred<Unit>()

    @Volatile
    var cancelled = false

    override suspend fun execute(
        request: TransportRequest,
        onBody: (ByteArray, Int) -> Unit,
    ): TransportResponse {
        requests += request
        started.complete(Unit)
        val response = respond(request)
        response.failure?.let { throw it }
        if (response.hang) {
            try {
                awaitCancellation()
            } finally {
                cancelled = true
            }
        }
        if (response.status !in 200..299) {
            return TransportResponse(response.status, response.contentType, String(response.body, Charsets.UTF_8))
        }
        var offset = 0
        var index = 0
        while (offset < response.body.size) {
            val size = (response.chunkSizes?.getOrNull(index++) ?: (1 + random.nextInt(7))).coerceAtMost(response.body.size - offset)
            onBody(response.body.copyOfRange(offset, offset + size), size)
            offset += size
        }
        return TransportResponse(response.status, response.contentType, null)
    }
}

class MapStorage : KeyValueStorage {
    val values = mutableMapOf<String, String>()

    override fun getString(key: String): String? = values[key]

    override fun putString(
        key: String,
        value: String?,
    ) {
        if (value == null) values.remove(key) else values[key] = value
    }
}

class MapSecrets : SecretStorage {
    val values = mutableMapOf<String, String>()

    override fun get(name: String): String? = values[name]

    override fun set(
        name: String,
        value: String,
    ) {
        values[name] = value
    }

    override fun remove(name: String) {
        values.remove(name)
    }
}

class FakeBackend(
    var backend: String = "platform",
) : BackendSelector {
    override fun currentBackend(): String = backend

    override fun selectOpenAI() {
        backend = OpenAIEndpointService.OPENAI_BACKEND
    }

    override fun unloadOpenAI() {
        if (backend == OpenAIEndpointService.OPENAI_BACKEND) backend = "platform"
    }
}

object Fixtures {
    const val MODELS_JSON = """{"object":"list","data":[{"id":"qwen3-q4","meta":{"n_ctx":131072}},{"id":"other","status":{"value":"loading"}}]}"""

    fun sse(vararg frames: String): String = frames.joinToString("") { "data: $it\n\n" } + "data: [DONE]\n\n"

    fun contentFrame(text: String) = """{"choices":[{"index":0,"delta":{"content":${quote(text)}}}]}"""

    fun quote(text: String) = OpenAIJson.encode(kotlinx.serialization.json.JsonPrimitive(text))
}
