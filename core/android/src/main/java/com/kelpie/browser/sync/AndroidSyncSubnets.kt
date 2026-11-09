package com.kelpie.browser.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities

/**
 * Directly connected subnets of physical Wi-Fi and Ethernet networks. A network
 * that is (or runs over) a VPN, or that is cellular, contributes nothing, so
 * neither do tun/ppp interfaces.
 */
class AndroidSyncSubnets(
    context: Context,
) : SyncSubnets {
    private val connectivity = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun eligible(): List<SyncSubnet> =
        runCatching {
            @Suppress("DEPRECATION")
            connectivity.allNetworks.flatMap { network ->
                val capabilities = connectivity.getNetworkCapabilities(network) ?: return@flatMap emptyList()
                val physical =
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                val excluded =
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
                        capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
                if (!physical || excluded) return@flatMap emptyList()
                val link = connectivity.getLinkProperties(network) ?: return@flatMap emptyList()
                val name = link.interfaceName.orEmpty()
                if (name.startsWith("tun") || name.startsWith("ppp") || name.startsWith("ipsec")) return@flatMap emptyList()
                link.linkAddresses.map { SyncSubnet(it.address, it.prefixLength) }
            }
        }.getOrDefault(emptyList())
}
