package com.kelpie.browser.sync

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import java.net.InetAddress
import java.util.concurrent.Executors

/**
 * `_kelpie-sync._tcp` over Android NSD: one registration with TXT `v`, `id`,
 * `h`, and browsing that resolves each service to its addresses, port and TXT.
 * Holds its own multicast lock while running. Logs never include TXT values.
 */
class NsdSyncDiscovery(
    context: Context,
) : SyncDiscovery {
    private val context = context.applicationContext
    private val nsd = this.context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val resolver = Executors.newSingleThreadExecutor { Thread(it, "kelpie-sync-nsd") }
    private val lock = Any()
    private var listener: SyncDiscovery.Listener? = null
    private var registration: NsdManager.RegistrationListener? = null
    private var browsing: NsdManager.DiscoveryListener? = null
    private var multicast: WifiManager.MulticastLock? = null
    private val replicasByService = mutableMapOf<String, String>()
    private val serviceCallbacks = mutableMapOf<String, NsdManager.ServiceInfoCallback>()
    private var running = false

    override fun start(
        advert: SyncDiscovery.Advert,
        listener: SyncDiscovery.Listener,
    ) {
        synchronized(lock) {
            if (running) stopLocked()
            running = true
            this.listener = listener
            acquireMulticast()
            register(advert)
            browse()
        }
    }

    override fun update(advert: SyncDiscovery.Advert) {
        synchronized(lock) {
            if (!running) return
            registration?.let { runCatching { nsd.unregisterService(it) } }
            registration = null
            register(advert)
        }
    }

    override fun stop() {
        synchronized(lock) { stopLocked() }
    }

    private fun stopLocked() {
        running = false
        registration?.let { runCatching { nsd.unregisterService(it) } }
        registration = null
        browsing?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        browsing = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            serviceCallbacks.values.forEach { runCatching { nsd.unregisterServiceInfoCallback(it) } }
        }
        serviceCallbacks.clear()
        replicasByService.clear()
        listener = null
        multicast?.let { if (it.isHeld) runCatching { it.release() } }
        multicast = null
    }

    private fun register(advert: SyncDiscovery.Advert) {
        val info =
            NsdServiceInfo().apply {
                serviceName = "kelpie-sync-" + advert.replica.take(8)
                serviceType = SyncProtocol.SERVICE_TYPE
                port = advert.port
                setAttribute("v", SyncProtocol.VERSION.toString())
                setAttribute("id", advert.replica)
                setAttribute("h", advert.hint)
            }
        val callback =
            object : NsdManager.RegistrationListener {
                override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                    Log.i(TAG, "sync advertisement registered")
                }

                override fun onRegistrationFailed(
                    serviceInfo: NsdServiceInfo,
                    errorCode: Int,
                ) {
                    Log.w(TAG, "sync advertisement failed: $errorCode")
                }

                override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) = Unit

                override fun onUnregistrationFailed(
                    serviceInfo: NsdServiceInfo,
                    errorCode: Int,
                ) = Unit
            }
        registration = callback
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, callback)
    }

    private fun browse() {
        val callback =
            object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(serviceType: String) = Unit

                override fun onDiscoveryStopped(serviceType: String) = Unit

                override fun onStartDiscoveryFailed(
                    serviceType: String,
                    errorCode: Int,
                ) {
                    Log.w(TAG, "sync browsing failed: $errorCode")
                }

                override fun onStopDiscoveryFailed(
                    serviceType: String,
                    errorCode: Int,
                ) = Unit

                override fun onServiceFound(serviceInfo: NsdServiceInfo) = resolve(serviceInfo)

                override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                    val replica =
                        synchronized(lock) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                serviceCallbacks.remove(serviceInfo.serviceName)?.let { runCatching { nsd.unregisterServiceInfoCallback(it) } }
                            }
                            replicasByService.remove(serviceInfo.serviceName)
                        }
                    replica?.let { listener?.lost(it) }
                }
            }
        browsing = callback
        nsd.discoverServices(SyncProtocol.SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, callback)
    }

    private fun resolve(service: NsdServiceInfo) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val callback =
                object : NsdManager.ServiceInfoCallback {
                    override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) = Unit

                    override fun onServiceUpdated(serviceInfo: NsdServiceInfo) = deliver(serviceInfo, serviceInfo.hostAddresses)

                    override fun onServiceLost() = Unit

                    override fun onServiceInfoCallbackUnregistered() = Unit
                }
            synchronized(lock) {
                if (!running || serviceCallbacks.containsKey(service.serviceName)) return
                serviceCallbacks[service.serviceName] = callback
            }
            runCatching { nsd.registerServiceInfoCallback(service, resolver, callback) }
            return
        }
        // Before Android 14 NsdManager resolves one service at a time; queue them.
        resolver.execute {
            val done = java.util.concurrent.CountDownLatch(1)
            @Suppress("DEPRECATION")
            nsd.resolveService(
                service,
                object : NsdManager.ResolveListener {
                    override fun onResolveFailed(
                        serviceInfo: NsdServiceInfo,
                        errorCode: Int,
                    ) = done.countDown()

                    override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                        @Suppress("DEPRECATION")
                        deliver(serviceInfo, listOfNotNull(serviceInfo.host))
                        done.countDown()
                    }
                },
            )
            done.await(RESOLVE_TIMEOUT_S, java.util.concurrent.TimeUnit.SECONDS)
        }
    }

    private fun deliver(
        info: NsdServiceInfo,
        addresses: List<InetAddress>,
    ) {
        val txt = info.attributes

        fun text(key: String): String? = txt[key]?.toString(Charsets.UTF_8)
        if (text("v") != SyncProtocol.VERSION.toString()) return
        val replica = text("id")?.takeIf { SyncBase64.decode(it)?.size == 16 } ?: return
        val hint = text("h")?.takeIf { SyncBase64.decode(it)?.size == 8 } ?: return
        if (addresses.isEmpty() || info.port !in 1..65535) return
        val target =
            synchronized(lock) {
                if (!running) return
                replicasByService[info.serviceName] = replica
                listener
            }
        target?.found(SyncDiscovery.Found(replica, hint, addresses, info.port))
    }

    private fun acquireMulticast() {
        val wifi = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager ?: return
        multicast =
            wifi.createMulticastLock("kelpie-sync-mdns").apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private companion object {
        const val TAG = "KelpieCookieSync"
        const val RESOLVE_TIMEOUT_S = 10L
    }
}
