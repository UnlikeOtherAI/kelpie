package com.kelpie.browser

import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.kelpie.browser.ai.AIHandler
import com.kelpie.browser.browser.BookmarkStore
import com.kelpie.browser.browser.HistoryStore
import com.kelpie.browser.browser.HomeStore
import com.kelpie.browser.device.DeviceInfo
import com.kelpie.browser.devtools.NetworkLogHandler
import com.kelpie.browser.handlers.BookmarkHandler
import com.kelpie.browser.handlers.BrowserManagementHandler
import com.kelpie.browser.handlers.CommentaryHandler
import com.kelpie.browser.handlers.ConsoleHandler
import com.kelpie.browser.handlers.CoordinateDiagnosticsHandler
import com.kelpie.browser.handlers.DOMHandler
import com.kelpie.browser.handlers.DeviceHandler
import com.kelpie.browser.handlers.EvaluateHandler
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.HighlightHandler
import com.kelpie.browser.handlers.HistoryHandler
import com.kelpie.browser.handlers.InteractionHandler
import com.kelpie.browser.handlers.MutationHandler
import com.kelpie.browser.handlers.NavigationHandler
import com.kelpie.browser.handlers.NetworkInspectorHandler
import com.kelpie.browser.handlers.ScreenshotHandler
import com.kelpie.browser.handlers.ScriptHandler
import com.kelpie.browser.handlers.ScriptPlaybackState
import com.kelpie.browser.handlers.ScrollHandler
import com.kelpie.browser.handlers.ShadowDOMHandler
import com.kelpie.browser.handlers.Snapshot3DHandler
import com.kelpie.browser.handlers.SwipeHandler
import com.kelpie.browser.handlers.TapCalibrationHandler
import com.kelpie.browser.handlers.TapCalibrationStore
import com.kelpie.browser.handlers.WebSocketHandler
import com.kelpie.browser.llm.LLMHandler
import com.kelpie.browser.network.FeedbackStore
import com.kelpie.browser.network.HTTPServer
import com.kelpie.browser.network.KelpieNetworkService
import com.kelpie.browser.network.MDNSAdvertiser
import com.kelpie.browser.network.NetworkServiceStage
import com.kelpie.browser.network.NetworkServiceState
import com.kelpie.browser.network.PairApprovalCoordinator
import com.kelpie.browser.network.PairingStore
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import com.kelpie.browser.ui.BrowserScreen
import com.kelpie.browser.ui.theme.KelpieTheme
import kotlinx.coroutines.launch

class KelpieBrowserSession(
    private val activity: ComponentActivity,
    private val localControlEnabled: Boolean = true,
    uoaSession: com.kelpie.browser.account.KelpieUOASession? = null,
    profileSubject: String? = uoaSession?.identity?.value?.subject,
) {
    private val browserContext get() = KelpieEnvironment.context(activity)
    private val applicationContext get() = KelpieEnvironment.app
    private var closed = false
    private val browserView: ComposeView
    private val lifecycleObserver =
        LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> onResume()
                Lifecycle.Event.ON_PAUSE -> onPause()
                Lifecycle.Event.ON_STOP -> onStop()
                Lifecycle.Event.ON_DESTROY -> close()
                else -> Unit
            }
        }

    fun view(): ComposeView = browserView

    fun attachTo(container: ViewGroup) {
        (browserView.parent as? ViewGroup)?.removeView(browserView)
        container.addView(browserView, ViewGroup.LayoutParams(-1, -1))
    }

    private val accountLogin =
        activity.activityResultRegistry.register(
            "com.unlikeotherai.kelpie.account-login",
            androidx.activity.result.contract.ActivityResultContracts
                .StartActivityForResult(),
        ) { result ->
            com.kelpie.browser.account.UOAAccount.finishLogin(
                result.resultCode,
                result.data?.dataString,
                result.data?.getStringExtra("nonce"),
            )
        }

    fun openAccountLogin(
        url: String,
        nonce: String,
    ) {
        accountLogin.launch(
            android.content
                .Intent(activity, com.kelpie.browser.account.AccountLoginActivity::class.java)
                .putExtra("url", url)
                .putExtra("nonce", nonce),
        )
    }

    private val router = Router()
    private val handlerContext = HandlerContext()
    private val scriptPlaybackState = ScriptPlaybackState()
    private var httpServer: HTTPServer? = null
    private var mdnsAdvertiser: MDNSAdvertiser? = null
    private var networkStage: NetworkServiceStage? = null
    private val pairingStore: PairingStore
    private val pairingCoordinator: PairApprovalCoordinator

    init {
        if (uoaSession != null) {
            KelpieEnvironment.requireProfile(profileSubject)
            require(uoaSession.identity.value.subject == null || uoaSession.identity.value.subject == profileSubject)
        }
        KelpieEnvironment.initialize(activity.applicationContext)
        uoaSession?.let(com.kelpie.browser.account.UOAAccount::useHostSession)

        val deviceInfo = DeviceInfo.collect(browserContext)
        HomeStore.init(browserContext)
        BookmarkStore.init(browserContext)
        com.kelpie.browser.account.UOAAccount
            .attach(activity, ::openAccountLogin, browserContext)
        HistoryStore.init(browserContext)
        TapCalibrationStore.init(browserContext)
        pairingStore = PairingStore.forContext(browserContext)
        pairingCoordinator = PairApprovalCoordinator(pairingStore)

        browserView =
            ComposeView(browserContext).apply {
                id = View.generateViewId()
                setViewTreeLifecycleOwner(activity)
                setViewTreeViewModelStoreOwner(activity)
                setViewTreeSavedStateRegistryOwner(activity)
                setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
                setContent {
                    KelpieTheme {
                        BrowserScreen(
                            deviceInfo = deviceInfo,
                            router = router,
                            handlerContext = handlerContext,
                            scriptPlaybackState = scriptPlaybackState,
                            activity = activity,
                            isServerRunning = httpServer?.isRunning == true,
                            isMDNSAdvertising = mdnsAdvertiser?.isRegistered == true,
                            pairingCoordinator = pairingCoordinator,
                        )
                    }
                }
            }
        registerHandlers(deviceInfo)
        com.kelpie.browser.connect.NessieConnection
            .start(browserContext, handlerContext)
        if (localControlEnabled) startServer(deviceInfo)
        activity.lifecycle.addObserver(lifecycleObserver)
    }

    private fun onResume() {
        com.kelpie.browser.browser.BookmarkStore
            .refreshAccountBookmarks()
        com.kelpie.browser.connect.NessieConnection
            .setForeground(true)
    }

    private fun onPause() {
        com.kelpie.browser.connect.NessieConnection
            .setForeground(false)
    }

    private fun registerHandlers(deviceInfo: DeviceInfo) {
        router.handlerContext = handlerContext
        router.scriptPlaybackState = scriptPlaybackState
        handlerContext.scriptPlaybackState = scriptPlaybackState

        NavigationHandler(handlerContext).register(router)
        ScreenshotHandler(handlerContext).register(router)
        DOMHandler(handlerContext).register(router)
        InteractionHandler(handlerContext).register(router)
        TapCalibrationHandler().register(router)
        ScrollHandler(handlerContext).register(router)
        CoordinateDiagnosticsHandler(handlerContext).register(router)
        DeviceHandler(handlerContext, deviceInfo, router, activity).register()
        EvaluateHandler(handlerContext).register(router)
        ConsoleHandler(handlerContext).register(router)
        NetworkLogHandler(handlerContext).register(router)
        WebSocketHandler(handlerContext).register(router)
        MutationHandler(handlerContext).register(router)
        ShadowDOMHandler(handlerContext).register(router)
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

        router.register("report-issue") { body ->
            val category =
                body["category"] as? String
                    ?: return@register errorResponse("MISSING_PARAM", "category is required")
            val command =
                body["command"] as? String
                    ?: return@register errorResponse("MISSING_PARAM", "command is required")
            val record =
                FeedbackStore.save(
                    context = applicationContext,
                    body = body + mapOf("category" to category, "command" to command),
                    platform = "android",
                    deviceId = deviceInfo.id,
                    deviceName = deviceInfo.name,
                )
            successResponse(
                mapOf(
                    "reportId" to record.reportId,
                    "storedAt" to record.storedAt,
                    "platform" to "android",
                    "deviceId" to deviceInfo.id,
                ),
            )
        }

        router.registerFallbacks()
        com.kelpie.browser.network
            .BrowserGatewayBinding(router, handlerContext)
            .register()
    }

    private fun startServer(deviceInfo: DeviceInfo) {
        val server =
            HTTPServer(
                port = deviceInfo.port,
                router = router,
                appContext = applicationContext,
                pairingStore = pairingStore,
                deviceInfo = deviceInfo,
                onPendingPairChanged = { pairingCoordinator.refresh() },
            )
        val advertiser =
            MDNSAdvertiser(
                appContext = applicationContext,
                deviceInfo = deviceInfo,
            )
        httpServer = server
        mdnsAdvertiser = advertiser

        // Hand off lifecycle to the foreground service so Doze cannot stall
        // incoming HTTP requests and the user sees a persistent "reachable"
        // notification.
        val stage = NetworkServiceStage(server, advertiser)
        networkStage = stage
        NetworkServiceState.stage(stage)
        KelpieNetworkService.start(applicationContext)
    }

    fun trimMemory() {
        handlerContext.tabStore?.discardPreviews()
    }

    private fun onStop() {
        com.kelpie.browser.browser.NetworkTrafficStore
            .flush()
    }

    fun close() {
        if (closed) return
        closed = true
        activity.lifecycle.removeObserver(lifecycleObserver)
        accountLogin.unregister()
        com.kelpie.browser.connect.NessieConnection
            .detach(handlerContext)
        com.kelpie.browser.account.UOAAccount
            .detach(activity)
        handlerContext.dialogState.dismissPending()
        val tabs = handlerContext.tabStore
        browserView.disposeComposition()
        (browserView.parent as? ViewGroup)?.removeView(browserView)
        tabs?.destroyAllTabs()
        // Release this Activity's listener before its replacement binds the port.
        // Keep foreground promotion intact across configuration changes.
        networkStage?.let {
            it.stop()
            NetworkServiceState.clearIf(it)
        }
        networkStage = null
        kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            router.browserGateway?.close()
        }
        if (!activity.isChangingConfigurations) KelpieNetworkService.stop(applicationContext)
        httpServer = null
        mdnsAdvertiser = null
    }
}
