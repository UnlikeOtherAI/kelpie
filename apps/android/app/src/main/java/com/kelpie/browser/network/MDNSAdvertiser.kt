package com.kelpie.browser.network

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.util.Log
import com.kelpie.browser.device.DeviceInfo

class MDNSAdvertiser(
    private val context: Context,
    private val deviceInfo: DeviceInfo,
) {
    private var nsdManager: NsdManager? = null
    private var activeListener: NsdManager.RegistrationListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var registrationInFlight = false
    private var shouldBeRegistered = false
    var isRegistered = false
        private set

    fun ensureRegistered() {
        shouldBeRegistered = true
        if (isRegistered || registrationInFlight) {
            return
        }

        registerService()
    }

    private fun registerService() {
        acquireMulticastLock()
        val serviceInfo =
            NsdServiceInfo().apply {
                serviceName = deviceInfo.name
                serviceType = SERVICE_TYPE
                port = deviceInfo.port
                setAttribute("id", deviceInfo.id)
                setAttribute("name", deviceInfo.name)
                setAttribute("model", deviceInfo.model)
                setAttribute("platform", "android")
                setAttribute("width", deviceInfo.width.toString())
                setAttribute("height", deviceInfo.height.toString())
                setAttribute("port", deviceInfo.port.toString())
                setAttribute("version", deviceInfo.version)
                setAttribute("engine", "webview")
            }

        // NsdManager throws IllegalArgumentException ("listener already in use") if a listener
        // instance is registered a second time. Always allocate a fresh listener per registration.
        val listener = newRegistrationListener()
        activeListener = listener
        registrationInFlight = true
        nsdManager =
            (context.getSystemService(Context.NSD_SERVICE) as NsdManager).also {
                it.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, listener)
            }
    }

    fun unregister() {
        shouldBeRegistered = false
        unregisterInternal()
    }

    /** Releases all resources, including the multicast lock. Call from Activity.onDestroy. */
    fun shutdown() {
        shouldBeRegistered = false
        unregisterInternal()
        releaseMulticastLock()
    }

    private fun unregisterInternal() {
        val listener = activeListener
        if (listener == null || (!isRegistered && !registrationInFlight)) {
            releaseMulticastLockIfIdle()
            return
        }

        try {
            nsdManager?.unregisterService(listener)
        } catch (e: Exception) {
            Log.w(TAG, "Unregister error: ${e.message}")
            registrationInFlight = false
            isRegistered = false
            activeListener = null
            nsdManager = null
            releaseMulticastLock()
        }
    }

    private fun newRegistrationListener(): NsdManager.RegistrationListener =
        object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(serviceInfo: NsdServiceInfo) {
                registrationInFlight = false
                isRegistered = true
                Log.i(TAG, "Registered: ${serviceInfo.serviceName}")
            }

            override fun onRegistrationFailed(
                serviceInfo: NsdServiceInfo,
                errorCode: Int,
            ) {
                registrationInFlight = false
                isRegistered = false
                if (activeListener === this) {
                    activeListener = null
                }
                releaseMulticastLockIfIdle()
                Log.e(TAG, "Registration failed: $errorCode")
            }

            override fun onServiceUnregistered(serviceInfo: NsdServiceInfo) {
                registrationInFlight = false
                isRegistered = false
                if (activeListener === this) {
                    activeListener = null
                }
                Log.i(TAG, "Unregistered: ${serviceInfo.serviceName}")
                if (shouldBeRegistered) {
                    registerService()
                } else {
                    releaseMulticastLockIfIdle()
                }
            }

            override fun onUnregistrationFailed(
                serviceInfo: NsdServiceInfo,
                errorCode: Int,
            ) {
                registrationInFlight = false
                Log.e(TAG, "Unregistration failed: $errorCode")
            }
        }

    private fun acquireMulticastLock() {
        if (multicastLock?.isHeld == true) return
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wifi == null) {
            Log.w(TAG, "WifiManager unavailable; cannot acquire multicast lock")
            return
        }
        multicastLock =
            wifi.createMulticastLock(MULTICAST_LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire()
            }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { lock ->
            if (lock.isHeld) {
                try {
                    lock.release()
                } catch (e: Exception) {
                    Log.w(TAG, "Multicast lock release error: ${e.message}")
                }
            }
        }
        multicastLock = null
    }

    private fun releaseMulticastLockIfIdle() {
        if (!shouldBeRegistered && !isRegistered && !registrationInFlight) {
            releaseMulticastLock()
        }
    }

    companion object {
        private const val TAG = "MDNSAdvertiser"
        private const val SERVICE_TYPE = "_kelpie._tcp"
        private const val MULTICAST_LOCK_TAG = "kelpie-mdns"
    }
}
