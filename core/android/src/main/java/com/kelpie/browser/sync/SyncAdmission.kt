package com.kelpie.browser.sync

import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress

/** A directly connected subnet of an eligible (physical Wi-Fi or Ethernet) interface. */
data class SyncSubnet(
    val address: InetAddress,
    val prefixLength: Int,
) {
    fun contains(candidate: InetAddress): Boolean {
        val network = address.address
        val other = candidate.address
        if (network.size != other.size || prefixLength !in 0..network.size * 8) return false
        val fullBytes = prefixLength / 8
        for (i in 0 until fullBytes) if (network[i] != other[i]) return false
        val remainder = prefixLength % 8
        if (remainder == 0) return true
        val mask = (0xFF shl (8 - remainder)) and 0xFF
        return (network[fullBytes].toInt() and mask) == (other[fullBytes].toInt() and mask)
    }
}

/** Supplies the directly connected subnets of eligible interfaces, read fresh on each call. */
fun interface SyncSubnets {
    fun eligible(): List<SyncSubnet>
}

/**
 * The peer-address rule, applied to incoming connections and to resolved
 * outgoing addresses: loopback, IPv4/IPv6 link-local, or inside a directly
 * connected subnet of a physical Wi-Fi or Ethernet interface. VPN, tunnel,
 * point-to-point and cellular interfaces never contribute subnets.
 */
class SyncAddressRule(
    private val subnets: SyncSubnets,
) {
    fun permits(address: InetAddress): Boolean {
        val candidate = unmapped(address)
        if (candidate.isLoopbackAddress || candidate.isLinkLocalAddress) return true
        return subnets.eligible().any { it.contains(candidate) }
    }

    fun permits(literal: String): Boolean = parseLiteral(literal)?.let(::permits) ?: false

    /** Eligible addresses, IPv4 first, then link-local IPv6, then other IPv6. */
    fun outgoing(addresses: List<InetAddress>): List<InetAddress> =
        addresses
            .map(::unmapped)
            .distinct()
            .filter(::permits)
            .sortedBy {
                when {
                    it is Inet4Address -> 0
                    it.isLinkLocalAddress -> 1
                    else -> 2
                }
            }

    companion object {
        /** Parses an IP literal without any DNS lookup; returns null for host names. */
        fun parseLiteral(literal: String): InetAddress? {
            val text = literal.removePrefix("[").removeSuffix("]").substringBefore('%')
            val looksLikeIp = text.contains(':') || text.matches(Regex("""\d{1,3}(\.\d{1,3}){3}"""))
            if (!looksLikeIp) return null
            return runCatching { InetAddress.getByName(text) }.getOrNull()
        }

        private fun unmapped(address: InetAddress): InetAddress {
            if (address !is Inet6Address) return address
            val bytes = address.address
            val mapped = (0 until 10).all { bytes[it] == 0.toByte() } && bytes[10] == 0xFF.toByte() && bytes[11] == 0xFF.toByte()
            return if (mapped) InetAddress.getByAddress(bytes.copyOfRange(12, 16)) else address
        }
    }
}

/** Sliding one-minute windows for hello admission and outgoing handshakes. */
class SyncRateLimiter(
    private val clock: () -> Long,
    private val perKey: Int,
    private val total: Int,
    private val windowMs: Long = 60_000L,
) {
    private val events = ArrayDeque<Pair<Long, String>>()

    @Synchronized fun tryAcquire(key: String): Boolean {
        val now = clock()
        while (events.isNotEmpty() && events.first().first <= now - windowMs) events.removeFirst()
        if (events.size >= total) return false
        if (events.count { it.second == key } >= perKey) return false
        events.addLast(now to key)
        return true
    }

    /** When the oldest event leaves the window; used to delay an outgoing handshake. */
    @Synchronized fun nextSlotAt(): Long = events.firstOrNull()?.first?.plus(windowMs) ?: clock()
}
