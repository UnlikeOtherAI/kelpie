package com.mollotov.browser

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.mollotov.browser.device.DeviceInfo
import com.mollotov.browser.devtools.ConsoleHandler
import com.mollotov.browser.devtools.MutationHandler
import com.mollotov.browser.devtools.NetworkLogHandler
import com.mollotov.browser.handlers.BrowserManagementHandler
import com.mollotov.browser.handlers.DOMHandler
import com.mollotov.browser.handlers.DeviceHandler
import com.mollotov.browser.handlers.EvaluateHandler
import com.mollotov.browser.handlers.HandlerContext
import com.mollotov.browser.handlers.InteractionHandler
import com.mollotov.browser.handlers.NavigationHandler
import com.mollotov.browser.handlers.ScreenshotHandler
import com.mollotov.browser.handlers.ScrollHandler
import com.mollotov.browser.llm.LLMHandler
import com.mollotov.browser.network.HTTPServer
import com.mollotov.browser.network.MDNSAdvertiser
import com.mollotov.browser.network.Router
import com.mollotov.browser.ui.BrowserScreen
import com.mollotov.browser.ui.theme.MollotovTheme

class MainActivity : ComponentActivity() {
    private val router = Router()
    private val handlerContext = HandlerContext()
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
                    handlerContext = handlerContext,
                    isServerRunning = httpServer?.isRunning == true,
                    isMDNSAdvertising = mdnsAdvertiser?.isRegistered == true,
                )
            }
        }

        registerHandlers(deviceInfo)
        startServer(deviceInfo)
    }

    private fun registerHandlers(deviceInfo: DeviceInfo) {
        NavigationHandler(handlerContext).register(router)
        ScreenshotHandler(handlerContext).register(router)
        DOMHandler(handlerContext).register(router)
        InteractionHandler(handlerContext).register(router)
        ScrollHandler(handlerContext).register(router)
        DeviceHandler(handlerContext, deviceInfo).register(router)
        EvaluateHandler(handlerContext).register(router)
        ConsoleHandler(handlerContext).register(router)
        NetworkLogHandler(handlerContext).register(router)
        MutationHandler(handlerContext).register(router)
        BrowserManagementHandler(handlerContext, applicationContext).register(router)
        LLMHandler(handlerContext).register(router)

        router.registerStubs() // Fill remaining unimplemented methods
    }

    private fun startServer(deviceInfo: DeviceInfo) {
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
