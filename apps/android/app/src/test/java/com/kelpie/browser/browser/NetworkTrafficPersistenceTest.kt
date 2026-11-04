package com.kelpie.browser.browser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class NetworkTrafficPersistenceTest {
    private fun entry(url: String) = TrafficEntry(method = "GET", url = url, statusCode = 200, contentType = "text/plain")

    @Test
    fun coalescesBodiesAndClearCannotBeOverwrittenByAnOlderSnapshot() {
        val directory = Files.createTempDirectory("kelpie-network").toFile()
        try {
            val writes = AtomicInteger()
            val file = directory.resolve("traffic.json")
            val writer =
                NetworkTrafficPersistence(file, { entries ->
                    writes.incrementAndGet()
                    entries.joinToString { it.url }
                }, {}, 3_600_000)
            repeat(2000) { writer.save(listOf(entry("url-$it"))) }
            assertFalse(file.exists())
            writer.flush()
            assertEquals(1, writes.get())
            assertEquals("url-1999", file.readText())
            writer.save(emptyList())
            writer.flush()
            assertEquals("", file.readText())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun concurrentWriteKeepsOnlyTheNewestPendingSnapshot() {
        val directory = Files.createTempDirectory("kelpie-network").toFile()
        try {
            val started = CountDownLatch(1)
            val release = CountDownLatch(1)
            val file = directory.resolve("traffic.json")
            val writer =
                NetworkTrafficPersistence(file, { entries ->
                    if (entries.firstOrNull()?.url == "old") {
                        started.countDown()
                        check(release.await(5, TimeUnit.SECONDS))
                    }
                    entries.joinToString { it.url }
                }, {}, 3_600_000)
            writer.save(listOf(entry("old")))
            val flush = Thread { writer.flush() }.apply { start() }
            assertTrue(started.await(5, TimeUnit.SECONDS))
            repeat(100) { writer.save(listOf(entry("new-$it"))) }
            release.countDown()
            flush.join(5000)
            writer.flush()
            assertEquals("new-99", file.readText())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun unreadableHistoryIsPreservedAndMigrationWaitsForSuccessfulWrite() {
        val directory = Files.createTempDirectory("kelpie-network").toFile()
        try {
            val file = directory.resolve("traffic.json").apply { writeText("malformed") }
            var migrated = false
            val writer = NetworkTrafficPersistence(file, { "replacement" }, { migrated = true }, 3_600_000)
            writer.preserveUnreadableFile()
            writer.save(listOf(entry("next")))
            assertFalse(migrated)
            writer.flush()
            assertTrue(migrated)
            assertEquals("replacement", file.readText())
            assertEquals("malformed", directory.listFiles()!!.single { it.name.contains("unreadable-") }.readText())
        } finally {
            directory.deleteRecursively()
        }
    }
}
