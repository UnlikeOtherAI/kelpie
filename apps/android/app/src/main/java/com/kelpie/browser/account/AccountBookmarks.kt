package com.kelpie.browser.account

import com.kelpie.browser.browser.Bookmark
import com.kelpie.browser.browser.BookmarkMutation
import com.kelpie.browser.browser.BookmarkTree
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.put
import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

/** CAS mutations preserve every untouched raw entry, including foreign metadata. */
class AccountBookmarks(
    private val publish: (List<Bookmark>) -> Unit,
    private val status: (Boolean, String?) -> Unit,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    private val request: suspend (String, String, String?, String?) -> UOATransport.Response = { path, method, body, version -> UOAAccount.request(path, method, body, version) },
) {
    private var active = true
    private var queued = 0
    private var events: UOASettingsStream? = null
    fun enableEvents() {
        events = UOASettingsStream(scope, "browser", "bookmarks", UOAAccount::settingsRequest) { value ->
            if (active && queued == 0) {
                val raw = if (value == kotlinx.serialization.json.JsonNull) JsonArray(emptyList()) else value as? JsonArray
                    ?: error("Invalid favourites snapshot")
                publish(decode(raw))
            }
        }
    }

    private var pending: Deferred<Unit>? = null

    fun invalidate() {
        active = false
        events?.stop()
        pending?.cancel()
    }

    fun enqueue(mutation: BookmarkMutation? = null): Deferred<Unit> {
        events?.stop()
        queued += 1
        val previous = pending
        val operation =
            scope.async {
                runCatching { previous?.await() }
                if (!active) throw kotlinx.coroutines.CancellationException()
                status(true, null)
                try {
                    val result = perform(mutation)
                    if (active) {
                        publish(result)
                        status(false, null)
                    }
                } catch (error: Exception) {
                    if (active) status(false, error.message ?: "Favourites could not be synced.")
                    throw error
                } finally {
                    queued -= 1
                    if (active && queued == 0) events?.start()
                }
            }
        pending = operation
        return operation
    }

    suspend fun flush() {
        pending?.await()
    }

    private suspend fun perform(mutation: BookmarkMutation?): List<Bookmark> {
        repeat(3) { attempt ->
            val latest = request(PATH, "GET", null, null)
            if (!active) throw kotlinx.coroutines.CancellationException()
            val existing = listValue(latest)
            if (mutation == null) return decode(existing)
            val version = latest.version ?: throw UOATransport.Failure(428)
            val changed = apply(existing, mutation)
            try {
                val saved = request(PATH, "PUT", buildJsonObject { put("value", changed) }.toString(), version)
                return decode(listValue(saved))
            } catch (error: UOATransport.Failure) {
                if (error.status != 409 || attempt == 2) throw error
            }
        }
        throw UOATransport.Failure(409)
    }

    companion object {
        private fun listValue(response: UOATransport.Response): JsonArray {
            val value = response.json()["value"]
            if (value == null || value == kotlinx.serialization.json.JsonNull) return JsonArray(emptyList())
            return value as? JsonArray ?: throw IllegalStateException("Favourites have an unsupported format.")
        }

        private const val PATH = "/oauth/me/settings/browser/bookmarks"

        fun decode(raw: JsonArray): List<Bookmark> = BookmarkTree.normalized(raw.mapNotNull(::decodeNode))

        private fun decodeNode(value: kotlinx.serialization.json.JsonElement): Bookmark? {
            val item = value as? JsonObject ?: return null
            val kind = (item["kind"] as? JsonPrimitive)?.contentOrNull ?: "bookmark"
            val url = (item["url"] as? JsonPrimitive)?.contentOrNull.orEmpty()
            if (kind !in setOf("bookmark", "folder") || (kind == "bookmark" && url.isEmpty())) return null
            if (kind == "folder" && runCatching { UUID.fromString((item["id"] as? JsonPrimitive)?.contentOrNull) }.isFailure) return null
            val parent = (item["parentId"] as? JsonPrimitive)?.contentOrNull?.let { runCatching { UUID.fromString(it).toString() }.getOrNull() }
            return Bookmark(id = identifier(item), title = (item["title"] as? JsonPrimitive)?.contentOrNull
                ?: (item["name"] as? JsonPrimitive)?.contentOrNull ?: url,
                url = url, createdAt = date(item["createdAt"] as? JsonPrimitive ?: item["created_at"] as? JsonPrimitive), kind = kind, parentId = parent)
        }

        fun encode(nodes: List<Bookmark>): JsonArray = JsonArray(nodes.map { node -> buildJsonObject {
            put("id", node.id)
            put("title", node.title)
            put("url", node.url)
            put("createdAt", node.createdAt)
            put("kind", node.kind)
            put("parentId", node.parentId?.let(::JsonPrimitive) ?: kotlinx.serialization.json.JsonNull)
        } })

        fun apply(raw: JsonArray, mutation: BookmarkMutation): JsonArray {
            val changed = BookmarkTree.apply(decode(raw), mutation)
            val known = raw.mapNotNull { value -> decodeNode(value)?.let { it.id to (value as JsonObject) } }.toMap()
            val merged = encode(changed).map { encoded ->
                val node = encoded as JsonObject
                JsonObject((known[(node["id"] as JsonPrimitive).content] ?: emptyMap()) + node)
            }
            return JsonArray(merged + raw.filter { decodeNode(it) == null })
        }

        private fun date(value: JsonPrimitive?): String {
            if (value == null) return ""
            if (value.isString) return value.content
            val seconds = value.doubleOrNull ?: return ""
            return runCatching {
                java.time.Instant
                    .ofEpochMilli(((seconds + 978307200) * 1000).toLong())
                    .toString()
            }.getOrDefault("")
        }

        private fun identifier(item: JsonObject): String {
            val id = (item["id"] as? JsonPrimitive)?.contentOrNull.orEmpty()
            runCatching { UUID.fromString(id) }.getOrNull()?.let { return it.toString() }
            val url = (item["url"] as? JsonPrimitive)?.contentOrNull.orEmpty()
            val bytes = ByteBuffer.wrap(MessageDigest.getInstance("SHA-256").digest(url.toByteArray(Charsets.UTF_8)))
            return UUID(bytes.long, bytes.long).toString()
        }
    }
}
