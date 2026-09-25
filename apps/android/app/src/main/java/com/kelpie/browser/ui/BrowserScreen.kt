package com.kelpie.browser.ui

import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import android.app.Activity
import android.content.Context
import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.kelpie.browser.FeatureFlags
import com.kelpie.browser.browser.BrowserState
import com.kelpie.browser.browser.KeyboardObserver
import com.kelpie.browser.browser.SessionStore
import com.kelpie.browser.browser.TabStore
import com.kelpie.browser.device.DeviceInfo
import com.kelpie.browser.handlers.HandlerContext
import com.kelpie.browser.handlers.ScriptPlaybackState
import com.kelpie.browser.handlers.Snapshot3DBridge
import com.kelpie.browser.network.PairApprovalCoordinator
import com.kelpie.browser.network.Router
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowserScreen(
    deviceInfo: DeviceInfo,
    router: Router,
    handlerContext: HandlerContext,
    scriptPlaybackState: ScriptPlaybackState,
    activity: Activity,
    isServerRunning: Boolean,
    isMDNSAdvertising: Boolean,
    pairingCoordinator: PairApprovalCoordinator,
) {
    var showPairedClients by remember { mutableStateOf(false) }
    val browserState = remember { BrowserState() }
    val context = LocalContext.current
    val tabStore = remember { TabStore(context, handlerContext, browserState) }
    val tabs by tabStore.tabs.collectAsState()
    val activeTabId by tabStore.activeTabId.collectAsState()
    val currentUrl by browserState.currentUrl.collectAsState()
    val isLoading by browserState.isLoading.collectAsState()
    val canGoBack by browserState.canGoBack.collectAsState()
    val canGoForward by browserState.canGoForward.collectAsState()
    val progress by browserState.progress.collectAsState()
    val pageTitle by browserState.pageTitle.collectAsState()
    var showSettings by remember { mutableStateOf(false) }
    var showBookmarks by remember { mutableStateOf(false) }
    var showHistory by remember { mutableStateOf(false) }
    var showNetworkInspector by remember { mutableStateOf(false) }
    var showAI by remember { mutableStateOf(false) }
    val composeView = LocalView.current
    val isTablet = remember(context) { context.isTabletDevice() }
    val coroutineScope = rememberCoroutineScope()
    var showWelcome by remember { mutableStateOf(shouldShowWelcome(context)) }
    var forceShowWelcome by remember { mutableStateOf(false) }
    var pendingWelcomeFromHelp by remember { mutableStateOf(false) }
    var webView by remember { mutableStateOf<WebView?>(null) }
    val tabletMobileStagePresetId by TabletViewportPresetStore.selectedPresetId.collectAsState()
    var availableTabletViewportPresets by remember { mutableStateOf(TABLET_VIEWPORT_PRESETS) }
    val isIn3DInspector by handlerContext.isIn3DInspectorFlow.collectAsState()
    val isScriptRecording by scriptPlaybackState.isRecording.collectAsState()
    var inspectorMode by remember { mutableStateOf("rotate") }
    val keyboardObserver = remember(composeView.rootView) { KeyboardObserver(composeView.rootView) }
    var showTabOverview by remember { mutableStateOf(false) }
    val sampler = remember(activity) { com.kelpie.browser.browser.ChromeSampler(activity.window) }
    val activeTab = tabs.firstOrNull { it.id == activeTabId }
    val pageColor = Color(activeTab?.chromeColor ?: -1)
    LaunchedEffect(activeTabId, currentUrl, isLoading) {
        if (!isLoading) activeTab?.let(sampler::request)
    }
    DisposableEffect(sampler) { onDispose { sampler.cancel() } }
    var bottomBarCollapsed by remember { mutableStateOf(false) }

    LaunchedEffect(activeTabId) { bottomBarCollapsed = false }

    fun showTabs() {
        activeTab?.let { tab ->
            val url = tab.currentUrl
            sampler.capture(tab.webView) { preview ->
                if (tabs.any { it.id == tab.id } && tab.currentUrl == url) tab.preview = preview
            }
        }
        tabs.filter { it.preview != null }.dropLast(11).forEach { it.preview = null }
        showTabOverview = true
        bottomBarCollapsed = false
    }

    DisposableEffect(keyboardObserver) {
        handlerContext.keyboardObserver = keyboardObserver
        onDispose {
            if (handlerContext.keyboardObserver === keyboardObserver) {
                handlerContext.keyboardObserver = null
            }
        }
    }

    DisposableEffect(tabStore) {
        handlerContext.tabStore = tabStore
        onDispose {
            if (handlerContext.tabStore === tabStore) {
                handlerContext.tabStore = null
            }
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer =
            LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_STOP) {
                    SessionStore.save(context, tabStore.tabs.value, tabStore.activeTabId.value)
                }
            }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    suspend fun toggle3DInspector() {
        if (handlerContext.isIn3DInspector) {
            runCatching { handlerContext.evaluateJS(Snapshot3DBridge.EXIT_SCRIPT) }
            handlerContext.mark3DInspectorInactive()
            inspectorMode = "rotate"
            return
        }

        runCatching { handlerContext.evaluateJS(Snapshot3DBridge.ENTER_SCRIPT) }
        val active = runCatching { handlerContext.evaluateJS("!!window.__m3d") }.getOrNull()
        if (active?.contains("true") == true) {
            handlerContext.isIn3DInspector = true
            inspectorMode = "rotate"
            runCatching { handlerContext.evaluateJS(Snapshot3DBridge.setModeScript(inspectorMode)) }
        }
    }

    suspend fun set3DInspectorMode(mode: String) {
        if (!handlerContext.isIn3DInspector) return
        val normalized = if (mode == "scroll") "scroll" else "rotate"
        runCatching { handlerContext.evaluateJS(Snapshot3DBridge.setModeScript(normalized)) }
        inspectorMode = normalized
    }

    suspend fun zoom3DInspector(delta: Double) {
        if (!handlerContext.isIn3DInspector) return
        runCatching { handlerContext.evaluateJS(Snapshot3DBridge.zoomByScript(delta)) }
    }

    suspend fun reset3DInspectorView() {
        if (!handlerContext.isIn3DInspector) return
        runCatching { handlerContext.evaluateJS(Snapshot3DBridge.RESET_VIEW_SCRIPT) }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().imePadding()) {
            if (isTablet && !isScriptRecording) {
                TabletTabStrip(tabs, activeTabId, pageColor, { tabStore.addTab() }, tabStore::selectTab, tabStore::closeTab)
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color(com.kelpie.browser.browser.ChromePalette.foreground(activeTab?.chromeColor ?: -1)).copy(alpha = 0.1f)))
            }

            if (isLoading && !isScriptRecording) {
                LinearProgressIndicator(
                    progress = { progress / 100f },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            BrowserViewport(
                tabStore, browserState, handlerContext, tabletMobileStagePresetId,
                onAvailablePresets = { availableTabletViewportPresets = it },
                onScrollDirectionChange = { bottomBarCollapsed = it == ScrollDirection.DOWN },
                onScrolled = { activeTab?.let(sampler::request) },
                onWebViewReady = { webView = it; router.webView = it; handlerContext.webView = it },
                modifier = Modifier.weight(1f).fillMaxWidth(),
            )

            if (!isScriptRecording) {
                BottomBar(
                    currentUrl = currentUrl,
                    canGoBack = canGoBack,
                    canGoForward = canGoForward,
                    isCollapsed = bottomBarCollapsed,
                    onNavigate = { url ->
                        tabStore.activeTab?.isStartPage = false
                        webView?.loadUrl(url)
                    },
                    onBack = { webView?.goBack() },
                    onForward = { webView?.goForward() },
                    isLoading = isLoading,
                    onReload = { if (isLoading) webView?.stopLoading() else webView?.reload() },
                    onBookmarks = { showBookmarks = true },
                    onShowTabs = ::showTabs,
                    onExpand = { bottomBarCollapsed = false },
                    moreContent = { dismiss ->
            BrowserMoreMenu(
                onDismiss = dismiss,
                onShowTabs = ::showTabs,
                onAddTab = { tabStore.addTab() },
                tabCount = tabs.size,
                onShare = { sharePage(context, currentUrl) },
                onWelcome = { forceShowWelcome = true; showWelcome = true },
                onChromeAuth = {
                    webView?.let { wv ->
                        handlerContext.chromeAuth.authenticate(wv.url ?: "", wv, activity)
                    }
                },
                onSettings = { showSettings = true },
                onBookmarks = { showBookmarks = true },
                onHistory = { showHistory = true },
                onNetworkInspector = { showNetworkInspector = true },
                onAI = { showAI = true },
                onSnapshot3D = {
                    coroutineScope.launch { toggle3DInspector() }
                },
                show3DInspector = FeatureFlags.is3DInspectorEnabled(context),
                showMobileViewportToggle = isTablet,
                mobileViewportPresets = availableTabletViewportPresets,
                selectedMobileViewportPresetId =
                    availableTabletViewportPresets
                        .firstOrNull { it.id == tabletMobileStagePresetId }
                        ?.id,
                onSelectMobileViewportPreset = { presetId ->
                    val nextPresetId = if (tabletMobileStagePresetId == presetId) null else presetId
                    TabletViewportPresetStore.setSelectedPresetId(nextPresetId)
                },
            )
                    },
                )
            }
        }

        if (!isScriptRecording && showWelcome && (forceShowWelcome || shouldShowWelcome(context))) {
            WelcomeCard(
                onDismiss = {
                    showWelcome = false
                    forceShowWelcome = false
                },
            )
        }

        if (isIn3DInspector && !isScriptRecording) {
            Box(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .padding(bottom = 88.dp),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Inspector3DControlsBar(
                    mode = inspectorMode,
                    onSelectMode = { mode ->
                        coroutineScope.launch { set3DInspectorMode(mode) }
                    },
                    onZoomOut = {
                        coroutineScope.launch { zoom3DInspector(-0.12) }
                    },
                    onZoomIn = {
                        coroutineScope.launch { zoom3DInspector(0.12) }
                    },
                    onReset = {
                        coroutineScope.launch { reset3DInspectorView() }
                    },
                    onExit = {
                        coroutineScope.launch { toggle3DInspector() }
                    },
                )
            }
        }

        if (isScriptRecording) {
            Box(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .statusBarsPadding()
                        .padding(top = 12.dp, end = 12.dp),
                contentAlignment = Alignment.TopEnd,
            ) {
                RecordingStopButton(
                    onClick = { scriptPlaybackState.requestAbort() },
                )
            }
        }
    }

    LaunchedEffect(isIn3DInspector) {
        if (!isIn3DInspector) {
            inspectorMode = "rotate"
        }
    }

    LaunchedEffect(isScriptRecording) {
        if (isScriptRecording) {
            showTabOverview = false
            showSettings = false
            showBookmarks = false
            showHistory = false
            showNetworkInspector = false
            showAI = false
            pendingWelcomeFromHelp = false
            forceShowWelcome = false
            showWelcome = false
        }
    }

    if (showTabOverview && !isScriptRecording) {
        ModalBottomSheet(onDismissRequest = { showTabOverview = false }, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
            BrowserTabOverview(tabs, activeTabId, { tabStore.selectTab(it); showTabOverview = false }, tabStore::closeTab, { tabStore.addTab(); showTabOverview = false }, { showTabOverview = false })
        }
    }

    if (showSettings) {
        ModalBottomSheet(
            onDismissRequest = { showSettings = false },
            sheetState = rememberModalBottomSheetState(),
        ) {
            SettingsScreen(
                deviceInfo = deviceInfo,
                isServerRunning = isServerRunning,
                isMDNSAdvertising = isMDNSAdvertising,
                onShowWelcome = {
                    showSettings = false
                    pendingWelcomeFromHelp = true
                },
                onNavigate = { url ->
                    showSettings = false
                    webView?.loadUrl(url)
                },
                onShowPairedClients = {
                    showSettings = false
                    showPairedClients = true
                },
            )
        }
    }

    if (showPairedClients) {
        ModalBottomSheet(
            onDismissRequest = { showPairedClients = false },
            sheetState = rememberModalBottomSheetState(),
        ) {
            PairedClientsScreen(
                coordinator = pairingCoordinator,
                onBack = { showPairedClients = false },
            )
        }
    }

    PairingDialog(coordinator = pairingCoordinator)

    LaunchedEffect(showSettings, pendingWelcomeFromHelp) {
        if (!showSettings && pendingWelcomeFromHelp) {
            pendingWelcomeFromHelp = false
            forceShowWelcome = true
            showWelcome = true
        }
    }

    if (showBookmarks) {
        ModalBottomSheet(
            onDismissRequest = { showBookmarks = false },
            sheetState = rememberModalBottomSheetState(),
        ) {
            BookmarksSheet(
                currentTitle = pageTitle,
                currentUrl = currentUrl,
                onNavigate = { url -> webView?.loadUrl(url) },
                onDismiss = { showBookmarks = false },
            )
        }
    }

    if (showHistory) {
        ModalBottomSheet(
            onDismissRequest = { showHistory = false },
            sheetState = rememberModalBottomSheetState(),
        ) {
            HistorySheet(
                onNavigate = { url -> webView?.loadUrl(url) },
                onDismiss = { showHistory = false },
            )
        }
    }

    if (showNetworkInspector) {
        ModalBottomSheet(
            onDismissRequest = { showNetworkInspector = false },
            sheetState = rememberModalBottomSheetState(),
        ) {
            NetworkInspectorSheet(onDismiss = { showNetworkInspector = false })
        }
    }

    if (showAI) {
        ModalBottomSheet(
            onDismissRequest = { showAI = false },
            sheetState = rememberModalBottomSheetState(),
        ) {
            AIStatusSheet(onDismiss = { showAI = false })
        }
    }

    // Observe programmatic panel requests from the HTTP API
    val activePanel by handlerContext.activePanel.collectAsState()
    LaunchedEffect(activePanel) {
        val panel = activePanel ?: return@LaunchedEffect
        handlerContext.clearPanel()
        // Dismiss any open sheet first
        showSettings = false
        showBookmarks = false
        showHistory = false
        showNetworkInspector = false
        showAI = false
        // Brief delay for Compose to process dismissals
        kotlinx.coroutines.delay(400)
        when (panel) {
            "history" -> showHistory = true
            "bookmarks" -> showBookmarks = true
            "network-inspector" -> showNetworkInspector = true
            "settings" -> showSettings = true
            "ai" -> showAI = true
        }
    }
}

private fun Context.isTabletDevice(): Boolean = resources.configuration.smallestScreenWidthDp >= 600
