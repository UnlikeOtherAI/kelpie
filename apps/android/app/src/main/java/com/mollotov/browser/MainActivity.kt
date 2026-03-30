package com.mollotov.browser

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.lifecycleScope
import com.mollotov.browser.device.DeviceIdentity
import com.mollotov.browser.device.DeviceInfo
import com.mollotov.browser.network.HTTPServer
import com.mollotov.browser.network.MDNSAdvertiser
import com.mollotov.browser.network.Router
import com.mollotov.browser.ui.BrowserScreen
import com.mollotov.browser.ui.theme.MollotovTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val router = Router()
    private var httpServer: HTTPServer? = null
    private var mdnsAdvertiser: MDNSAdvertiser? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val deviceInfo = DeviceInfo.collect(this)

        setContent {
            MollotovTheme {
                BrowserScreen(
                    deviceInfo = deviceInfo,
                    router = router,
                    isServerRunning = httpServer?.isRunning == true,
                    isMDNSAdvertising = mdnsAdvertiser?.isRegistered == true,
                )
            }
        }

        lifecycleScope.launch {
            startServer(deviceInfo)
        }
    }

    private fun startServer(deviceInfo: DeviceInfo) {
        router.registerStubs()

        httpServer = HTTPServer(port = deviceInfo.port, router = router).also { it.start() }

        mdnsAdvertiser = MDNSAdvertiser(
            context = this,
            deviceInfo = deviceInfo,
        ).also { it.register() }
    }

    override fun onDestroy() {
        super.onDestroy()
        httpServer?.stop()
        mdnsAdvertiser?.unregister()
    }
}
