package com.kelpie.browser.network

internal fun isLoopbackHost(rawHost: String): Boolean {
    val host = rawHost.lowercase().removePrefix("[").removeSuffix("]")
    if (host == "localhost" || host.endsWith(".localhost")) return true
    if (host == "::1" || host == "0:0:0:0:0:0:0:1") return true
    val octets = host.split('.')
    return octets.size == 4 && octets[0] == "127" && octets.all { it.toIntOrNull() in 0..255 }
}
