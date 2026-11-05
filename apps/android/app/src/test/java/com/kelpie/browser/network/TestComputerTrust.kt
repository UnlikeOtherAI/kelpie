package com.kelpie.browser.network

import java.io.File
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

/** Model tests inject permissions; the shipped parser, lock and disk store run in native CTest. */
internal fun testPairingStore(file: File): PairingStore = PairingStore(file, TestComputerTrust(file.parentFile))

internal class TestComputerTrust(
    directory: File,
) : ComputerTrust {
    companion object {
        private val stores = ConcurrentHashMap<String, MutableMap<String, TrustedComputer>>()
    }

    private val computers = stores.getOrPut(directory.absolutePath) { ConcurrentHashMap() }

    override fun canonicalAddress(address: String): String? =
        runCatching {
            val literal = address.removeSurrounding("[", "]")
            require(literal.contains(':') || literal.matches(Regex("[0-9.]+")))
            InetAddress.getByName(literal).hostAddress
        }.getOrNull()

    override fun safeHost(host: String): Boolean = host.substringBefore(':') in setOf("127.0.0.1", "localhost", "192.0.2.10")

    override fun clientId(address: String): String? {
        val canonical = canonicalAddress(address) ?: return null
        val loopback = InetAddress.getByName(canonical).isLoopbackAddress
        return if (loopback || computers.containsKey(canonical)) "host:$canonical" else null
    }

    override fun approve(
        address: String,
        name: String,
    ): Boolean {
        val canonical = canonicalAddress(address) ?: return false
        computers[canonical] = TrustedComputer(canonical, name, System.currentTimeMillis())
        return true
    }

    override fun revoke(address: String): Boolean {
        canonicalAddress(address)?.let { computers.remove(it) }
        return true
    }

    override fun list(): List<TrustedComputer> = computers.values.toList()
}
