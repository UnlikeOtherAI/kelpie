package com.mollotov.browser.device

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import com.mollotov.browser.BuildConfig
import java.net.Inet4Address
import java.net.NetworkInterface

data class DeviceInfo(
    val id: String,
    val name: String,
    val model: String,
    val width: Int,
    val height: Int,
    val ip: String,
    val port: Int,
    val version: String,
) {
    companion object {
        fun collect(context: Context, port: Int = 8420): DeviceInfo {
            val id = DeviceIdentity.getOrCreate(context)
            val name = "${Build.MANUFACTURER} ${Build.MODEL}".trim()
            val model = Build.MODEL

            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            wm.defaultDisplay.getRealMetrics(metrics)

            return DeviceInfo(
                id = id,
                name = name,
                model = model,
                width = metrics.widthPixels,
                height = metrics.heightPixels,
                ip = getLocalIpAddress(),
                port = port,
                version = BuildConfig.VERSION_NAME,
            )
        }

        private fun getLocalIpAddress(): String {
            try {
                val interfaces = NetworkInterface.getNetworkInterfaces() ?: return "0.0.0.0"
                for (intf in interfaces) {
                    if (!intf.isUp || intf.isLoopback) continue
                    for (addr in intf.inetAddresses) {
                        if (addr is Inet4Address && !addr.isLoopbackAddress) {
                            return addr.hostAddress ?: continue
                        }
                    }
                }
            } catch (_: Exception) {}
            return "0.0.0.0"
        }
    }
}
