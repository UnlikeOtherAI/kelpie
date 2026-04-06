package com.kelpie.browser

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.kelpie.browser.ai.AIHandler
import com.kelpie.browser.browser.BookmarkStore
import com.kelpie.browser.browser.HistoryStore
import com.kelpie.browser.browser.HomeStore
import com.kelpie.browser.device.DeviceInfo
import com.kelpie.browser.devtools.ConsoleHandler
import com.kelpie.browser.devtools.MutationHandler
import com.kelpie.browser.devtools.NetworkLogHandler
import com.kelpie.browser.handlers.BookmarkHandler
import com.kelpie.browser.handlers.BrowserManagementHandler
import com.kelpie.browser.handlers.CommentaryHandler
import com.kelpie.browser.handlers.DOMHandler
import com.kelpie.browser.handlers.DeviceHandler
import com.kelpie.browser.handlers.EvaluateHandler
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.HighlightHandler
import com.kelpie.browser.handlers.HistoryHandler
import com.kelpie.browser.handlers.InteractionHandler
import com.kelpie.browser.handlers.NavigationHandler
import com.kelpie.browser.handlers.NetworkInspectorHandler
import com.kelpie.browser.handlers.ScreenshotHandler
import com.kelpie.browser.handlers.ScriptHandler
import com.kelpie.browser.handlers.ScriptPlaybackState
import com.kelpie.browser.handlers.ScrollHandler
import com.kelpie.browser.handlers.Snapshot3DHandler
import com.kelpie.browser.handlers.SwipeHandler
import com.kelpie.browser.llm.LLMHandler
import com.kelpie.browser.network.HTTPServer
import com.kelpie.browser.network.MDNSAdvertiser
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import com.kelpie.browser.ui.BrowserScreen
import com.kelpie.browser.ui.theme.KelpieTheme

class MainActivity : ComponentActivity() {
    private val router = Router()
    private val handlerContext = HandlerContext()
    private val scriptPlaybackState = ScriptPlaybackState()
    private var httpServer: HTTPServer? = null
    private var mdnsAdvertiser: MDNSAdvertiser? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val deviceInfo = DeviceInfo.collect(this)
        HomeStore.init(this)
        BookmarkStore.init(this)
        HistoryStore.init(this)

        setContent {
            KelpieTheme {
                BrowserScreen(
                    deviceInfo = deviceInfo,
                    router = router,
                    handlerContext = handlerContext,
                    scriptPlaybackState = scriptPlaybackState,
                    activity = this@MainActivity,
                    isServerRunning = httpServer?.isRunning == true,
                    isMDNSAdvertising = mdnsAdvertiser?.isRegistered == true,
                )
            }
        }

        registerHandlers(deviceInfo)
        startServer(deviceInfo)
    }

    private fun registerHandlers(deviceInfo: DeviceInfo) {
        router.handlerContext = handlerContext
        router.scriptPlaybackState = scriptPlaybackState
        handlerContext.scriptPlaybackState = scriptPlaybackState

        NavigationHandler(handlerContext).register(router)
        ScreenshotHandler(handlerContext).register(router)
        DOMHandler(handlerContext).register(router)
        InteractionHandler(handlerContext).register(router)
        ScrollHandler(handlerContext).register(router)
        DeviceHandler(handlerContext, deviceInfo, this).register(router)
        EvaluateHandler(handlerContext).register(router)
        ConsoleHandler(handlerContext).register(router)
        NetworkLogHandler(handlerContext).register(router)
        MutationHandler(handlerContext).register(router)
        BrowserManagementHandler(handlerContext, applicationContext).register(router)
        LLMHandler(handlerContext).register(router)
        AIHandler(applicationContext, handlerContext).register(router)
        Snapshot3DHandler(handlerContext) { FeatureFlags.is3DInspectorEnabled(applicationContext) }.register(router)
        CommentaryHandler(handlerContext).register(router)
        HighlightHandler(handlerContext).register(router)
        SwipeHandler(handlerContext).register(router)
        ScriptHandler(handlerContext, router, scriptPlaybackState).register(router)
        BookmarkHandler(handlerContext).register(router)
        HistoryHandler(handlerContext).register(router)
        NetworkInspectorHandler(handlerContext).register(router)

        router.register("show-panel") { body ->
            val panel =
                body["panel"] as? String
                    ?: return@register errorResponse("MISSING_PARAM", "panel is required")
            val valid = listOf("history", "bookmarks", "network-inspector", "settings", "ai")
            if (panel !in valid) {
                return@register errorResponse("INVALID_PARAM", "panel must be one of: ${valid.joinToString()}")
            }
            handlerContext.requestPanel(panel)
            successResponse(mapOf("panel" to panel))
        }

        router.register("toast") { body ->
            val message = body["message"] as? String ?: "No message"
            handlerContext.showToast(message)
            mapOf("success" to true)
        }

        router.register("safari-auth") { body ->
            val wv = handlerContext.webView
            if (wv == null) {
                mapOf("success" to false, "error" to mapOf("code" to "NO_WEBVIEW", "message" to "No WebView"))
            } else {
                val url = (body["url"] as? String) ?: wv.url ?: ""
                kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
                    handlerContext.chromeAuth.authenticate(url, wv, this@MainActivity)
                }
                mapOf("success" to true, "started" to true, "url" to url)
            }
        }

        router.registerStubs() // Fill remaining unimplemented methods
    }

    private fun startServer(deviceInfo: DeviceInfo) {
        httpServer = HTTPServer(port = deviceInfo.port, router = router).also { it.start() }

        mdnsAdvertiser =
            MDNSAdvertiser(
                context = this,
                deviceInfo = deviceInfo,
            ).also { it.register() }
    }

    override fun onResume() {
        super.onResume()
        handlerContext.chromeAuth.onResume(handlerContext.webView)
    }

    override fun onDestroy() {
        handlerContext.dialogState.dismissPending()
        super.onDestroy()
        httpServer?.stop()
        mdnsAdvertiser?.unregister()
    }
}
