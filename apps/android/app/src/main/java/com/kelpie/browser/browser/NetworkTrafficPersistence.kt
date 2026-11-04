package com.kelpie.browser.browser

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** A bounded snapshot writer: one pending list of immutable entries, never a queue of body copies. */
class NetworkTrafficPersistence(
    private val file: File,
    private val encode: (List<TrafficEntry>) -> String,
    private val migrated: () -> Unit,
    private val intervalMillis: Long = 1000,
) {
    private val executor =
        Executors.newSingleThreadScheduledExecutor { task ->
            Thread(task, "kelpie-network-persistence").apply { isDaemon = true }
        }
    private val lock = Any()
    private var pending: List<TrafficEntry>? = null
    private var scheduled = false
    private var recoveryNeeded = false
    private var retryMillis = 1000L

    fun load(): String? =
        try {
            if (file.exists()) file.readText() else null
        } catch (_: Exception) {
            preserveUnreadableFile()
            null
        }

    fun preserveUnreadableFile() {
        recoveryNeeded = true
    }

    fun save(entries: List<TrafficEntry>) {
        val schedule =
            synchronized(lock) {
                pending = entries
                (!scheduled).also { scheduled = true }
            }
        if (schedule) schedule(intervalMillis)
    }

    fun flush() {
        executor.submit { writeLatest() }.get()
    }

    private fun schedule(delay: Long) {
        executor.schedule({ writeLatest() }, delay, TimeUnit.MILLISECONDS)
    }

    private fun writeLatest() {
        val snapshot = synchronized(lock) { pending.also { pending = null } } ?: return
        try {
            if (recoveryNeeded && file.exists()) {
                Files.move(file.toPath(), File(file.path + ".unreadable-${UUID.randomUUID()}").toPath())
            }
            recoveryNeeded = false
            val directory = requireNotNull(file.parentFile)
            check(directory.isDirectory || directory.mkdirs()) { "Cannot create network history directory" }
            val temporary = File.createTempFile(".traffic-", ".tmp", directory)
            try {
                temporary.outputStream().use { stream ->
                    stream.write(encode(snapshot).toByteArray(Charsets.UTF_8))
                    stream.fd.sync()
                }
                Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } finally {
                temporary.delete()
            }
            migrated()
            retryMillis = 1000
        } catch (failure: Exception) {
            System.err.println("Network history save failed: ${failure.javaClass.simpleName}")
            synchronized(lock) { if (pending == null) pending = snapshot }
            retryMillis = (retryMillis * 2).coerceAtMost(60_000)
        }
        val again = synchronized(lock) { (pending != null).also { scheduled = it } }
        if (again) schedule(maxOf(intervalMillis, retryMillis))
    }
}
