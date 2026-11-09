package com.kelpie.browser.sync

import java.net.InetAddress

/** `_kelpie-sync._tcp` advertising and browsing. */
interface SyncDiscovery {
    /** TXT `v=1`, `id=<replica>`, `h=<account hint>`. */
    data class Advert(
        val replica: String,
        val hint: String,
        val port: Int,
    )

    data class Found(
        val replica: String,
        val hint: String,
        val addresses: List<InetAddress>,
        val port: Int,
    )

    interface Listener {
        fun found(peer: Found)

        fun lost(replica: String)
    }

    fun start(
        advert: Advert,
        listener: Listener,
    )

    /** Re-advertises with a new TXT record (the UTC date changed). */
    fun update(advert: Advert)

    fun stop()
}

/** Tracks the first store open in this process; only that open is a launch. */
class SyncLaunches {
    @Volatile private var launched = false

    val pending: Boolean get() = !launched

    fun consumed() {
        launched = true
    }

    companion object {
        val process = SyncLaunches()
    }
}

/** Log sink. Messages never contain cookie names, domains, values, tickets, keys or boxes. */
fun interface SyncLog {
    fun log(
        level: Int,
        message: String,
    )

    companion object {
        const val INFO = 4
        const val WARN = 5
        val none = SyncLog { _, _ -> }
    }
}

/** Page loads from unpartitioned tabs, shared by the scan scheduler and Android coverage. */
class RecentLoads(
    private val clock: () -> Long,
    private val windowMs: Long = 10 * 60_000L,
    private val capacity: Int = 64,
) {
    private val loads = LinkedHashMap<String, Pair<String, Long>>() // host → (url, at)

    @Synchronized fun record(
        host: String,
        url: String,
    ) {
        loads.remove(host)
        loads[host] = url to clock()
        while (loads.size > capacity) loads.remove(loads.keys.first())
    }

    @Synchronized fun hosts(): Set<String> = live().keys

    @Synchronized fun urls(): List<String> = live().values.map { it.first }

    private fun live(): Map<String, Pair<String, Long>> {
        val cutoff = clock() - windowMs
        return loads.filterValues { it.second >= cutoff }
    }
}
