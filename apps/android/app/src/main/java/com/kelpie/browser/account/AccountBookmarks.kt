package com.kelpie.browser.account

import com.kelpie.browser.browser.Bookmark
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
    sealed class Mutation {
        data class Add(
            val bookmark: Bookmark,
        ) : Mutation()

        data class Remove(
            val id: String,
        ) : Mutation()

        data object Clear : Mutation()
    }

    private var active = true
    private var pending: Deferred<Unit>? = null

    fun invalidate() {
        active = false
        pending?.cancel()
    }

    fun enqueue(mutation: Mutation? = null): Deferred<Unit> {
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
                }
            }
        pending = operation
        return operation
    }

    suspend fun flush() {
        pending?.await()
    }

    private suspend fun perform(mutation: Mutation?): List<Bookmark> {
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

        fun decode(raw: JsonArray): List<Bookmark> =
            raw
                .mapNotNull { value ->
                    val item = value as? JsonObject ?: return@mapNotNull null
                    val url = (item["url"] as? JsonPrimitive)?.contentOrNull?.takeIf { it.isNotBlank() } ?: return@mapNotNull null
                    Bookmark(
                        id = identifier(item),
                        title =
                            (item["title"] as? JsonPrimitive)?.contentOrNull
                                ?: (item["name"] as? JsonPrimitive)?.contentOrNull ?: url,
                        url = url,
                        createdAt = date(item["createdAt"] as? JsonPrimitive ?: item["created_at"] as? JsonPrimitive),
                    )
                }.distinctBy { it.id }

        fun apply(
            raw: JsonArray,
            mutation: Mutation,
        ): JsonArray =
            when (mutation) {
                is Mutation.Clear -> JsonArray(emptyList())
                is Mutation.Remove -> JsonArray(raw.filterNot { it is JsonObject && identifier(it).equals(mutation.id, ignoreCase = true) })
                is Mutation.Add -> {
                    if (decode(raw).any { it.url == mutation.bookmark.url }) {
                        raw
                    } else {
                        JsonArray(
                            raw +
                                buildJsonObject {
                                    put("id", mutation.bookmark.id)
                                    put("title", mutation.bookmark.title)
                                    put("url", mutation.bookmark.url)
                                    put("createdAt", mutation.bookmark.createdAt)
                                },
                        )
                    }
                }
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
