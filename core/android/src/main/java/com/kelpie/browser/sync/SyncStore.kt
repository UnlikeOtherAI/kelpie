package com.kelpie.browser.sync

import com.kelpie.browser.nativecore.CookieSyncNative
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.util.concurrent.Executors

/**
 * One open core-sync store. Every call runs on [thread], a single-threaded
 * dispatcher; a merge transaction runs plan → engine writes → commit inside one
 * block on that thread, so nothing else touches the store in between.
 */
class SyncStore private constructor(
    private val handle: Long,
    val replica: String,
    private val file: File,
    private val thread: kotlinx.coroutines.ExecutorCoroutineDispatcher,
) {
    @Volatile private var closed = false
    private var locations: List<EntryLocation>? = null
    private var head = -1L

    /** Store access inside one dispatcher turn. Not valid outside [use]. */
    inner class Access internal constructor() {
        fun status(): JsonObject = SyncJson.native(CookieSyncNative.storeStatus(handle))

        fun finishWarmup() = CookieSyncNative.storeFinishWarmup(handle)

        fun scan(
            snapshot: CookieSnapshot,
            now: Long,
        ): JsonObject = mutated(SyncJson.native(CookieSyncNative.storeScan(handle, snapshot.cookies.toString(), snapshot.coverage.toString(), now)))

        fun answerPull(
            pull: JsonObject,
            snapshot: CookieSnapshot,
            now: Long,
        ): JsonObject = mutated(SyncJson.native(CookieSyncNative.storeAnswerPull(handle, pull.toString(), snapshot.cookies.toString(), snapshot.coverage.toString(), now)))

        fun buildPush(
            watermark: JsonObject,
            snapshot: CookieSnapshot,
            now: Long,
        ): JsonObject = mutated(SyncJson.native(CookieSyncNative.storeBuildPush(handle, watermark.toString(), snapshot.cookies.toString(), snapshot.coverage.toString(), now)))

        fun watermark(peerReplica: String): JsonObject = SyncJson.native(CookieSyncNative.storeWatermark(handle, peerReplica))

        /** Locations of every metadata entry, read from the store file (it holds no values). */
        fun entries(): List<EntryLocation> = locations ?: readLocations().also { locations = it }

        /**
         * Plans [records], applies each op through [source] while [current] holds,
         * and commits. Any failure aborts the transaction and leaves the store
         * unchanged.
         */
        fun merge(
            records: JsonArray,
            source: JsonObject?,
            now: Long,
            cookies: CookieSource,
            current: () -> Boolean,
        ): MergeOutcome {
            val plan = SyncJson.native(CookieSyncNative.storePlanMerge(handle, records.toString(), source?.toString(), now))
            val ops = plan.array("ops") ?: JsonArray(emptyList())
            val known = entries()
            val results =
                try {
                    ops.map { op ->
                        if (!current()) throw SyncFailure("STALE", "account changed during a merge")
                        cookies.apply(op as JsonObject, known)
                    }
                } catch (error: Throwable) {
                    CookieSyncNative.storeAbortMerge(handle)
                    throw error
                }
            val committed = SyncJson.native(CookieSyncNative.storeCommitMerge(handle, JsonArray(results).toString()))
            locations = null
            return MergeOutcome(applied = committed.long("applied") ?: 0, head = committed.long("head") ?: 0)
        }

        /** Every new or changed entry moves the head, so re-read locations only then. */
        private fun mutated(result: JsonObject): JsonObject {
            val now = result.long("head") ?: return result
            if (now != head) {
                head = now
                locations = null
            }
            return result
        }
    }

    data class MergeOutcome(
        val applied: Long,
        val head: Long,
    )

    private val access = Access()

    suspend fun <T> use(block: Access.() -> T): T =
        withContext(thread) {
            if (closed) throw SyncFailure("NO_STORE", "store is closed")
            access.block()
        }

    suspend fun close() {
        withContext(thread) {
            if (!closed) {
                closed = true
                CookieSyncNative.storeClose(handle)
            }
        }
        thread.close()
    }

    private fun readLocations(): List<EntryLocation> {
        val text = runCatching { file.readText() }.getOrNull() ?: return emptyList()
        val entries = SyncJson.parseObject(text)?.array("entries") ?: return emptyList()
        return entries.mapNotNull { element ->
            val entry = element as? JsonObject ?: return@mapNotNull null
            val domain = entry.string("d") ?: return@mapNotNull null
            EntryLocation(domain, entry.string("p") ?: "/")
        }
    }

    companion object {
        const val FILE_NAME = "cookie-sync.json"

        /** Opens `<dir>/cookie-sync.json` under [subject] with a fresh [replica]. */
        suspend fun open(
            directory: File,
            subject: String,
            replica: String,
            launch: Boolean,
            now: Long,
        ): SyncStore {
            val thread = Executors.newSingleThreadExecutor { Thread(it, "kelpie-cookie-sync") }.asCoroutineDispatcher()
            val file = File(directory, FILE_NAME)
            val options =
                buildJsonObject {
                    put("subject", subject)
                    put("replica", replica)
                    put("launch", launch)
                    put("nowMillis", now)
                }
            return try {
                withContext(thread) {
                    directory.mkdirs()
                    val opened = SyncJson.native(CookieSyncNative.storeOpen(file.path, options.toString()))
                    val handle = (opened["handle"] as? JsonPrimitive)?.content?.toLongOrNull() ?: throw SyncFailure("INTERNAL", "store handle missing")
                    SyncStore(handle, replica, file, thread)
                }
            } catch (error: Throwable) {
                thread.close()
                throw error
            }
        }
    }
}
