package com.mollotov.browser.ui

import android.app.Activity
import android.content.Context
import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.mollotov.browser.browser.BrowserState
import com.mollotov.browser.browser.HistoryStore
import com.mollotov.browser.browser.WebViewContainer
import com.mollotov.browser.device.DeviceInfo
import com.mollotov.browser.FeatureFlags
import com.mollotov.browser.handlers.HandlerContext
import com.mollotov.browser.handlers.Snapshot3DBridge
import com.mollotov.browser.network.Router
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowserScreen(
    deviceInfo: DeviceInfo,
    router: Router,
    handlerContext: HandlerContext,
    activity: Activity,
    isServerRunning: Boolean,
    isMDNSAdvertising: Boolean,
) {
    val browserState = remember { BrowserState() }
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
    val context = LocalContext.current
    val isTablet = remember(context) { context.isTabletDevice() }
    val coroutineScope = rememberCoroutineScope()
    var showWelcome by remember { mutableStateOf(shouldShowWelcome(context)) }
    var forceShowWelcome by remember { mutableStateOf(false) }
    var pendingWelcomeFromHelp by remember { mutableStateOf(false) }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var lastRecordedUrl by remember { mutableStateOf("") }
    val tabletMobileStagePresetId by TabletViewportPresetStore.selectedPresetId.collectAsState()
    var availableTabletViewportPresets by remember { mutableStateOf(TABLET_VIEWPORT_PRESETS) }

    // Record history when URL changes
    if (currentUrl != lastRecordedUrl && currentUrl.isNotEmpty()) {
        lastRecordedUrl = currentUrl
        HistoryStore.record(currentUrl, pageTitle)
    }

    if (currentUrl.isNotEmpty() && pageTitle.isNotBlank()) {
        HistoryStore.updateLatestTitle(currentUrl, pageTitle)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            if (isLoading) {
                LinearProgressIndicator(
                    progress = { progress / 100f },
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            URLBar(
                currentUrl = currentUrl,
                canGoBack = canGoBack,
                canGoForward = canGoForward,
                onNavigate = { url -> webView?.loadUrl(url) },
                onBack = { webView?.goBack() },
                onForward = { webView?.goForward() },
                onAI = { showAI = true },
                onSnapshot3D = {
                    coroutineScope.launch {
                        if (handlerContext.isIn3DInspector) {
                            runCatching { handlerContext.evaluateJS(Snapshot3DBridge.EXIT_SCRIPT) }
                            handlerContext.mark3DInspectorInactive()
                        } else {
                            runCatching { handlerContext.evaluateJS(Snapshot3DBridge.ENTER_SCRIPT) }
                            val active = runCatching { handlerContext.evaluateJS("!!window.__m3d") }.getOrNull()
                            if (active?.contains("true") == true) {
                                handlerContext.isIn3DInspector = true
                            }
                        }
                    }
                },
            )

            BoxWithConstraints(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
            ) {
                val fittingPresets = tabletViewportPresetsThatFit(maxWidth = maxWidth, maxHeight = maxHeight)
                val selectedPreset = fittingPresets.firstOrNull { it.id == tabletMobileStagePresetId }
                val mobileStageActive = selectedPreset != null
                val stageSize = selectedPreset?.let {
                    tabletMobileStageSize(
                        preset = it,
                        maxWidth = maxWidth,
                        maxHeight = maxHeight,
                    )
                }

                LaunchedEffect(maxWidth, maxHeight) {
                    availableTabletViewportPresets = fittingPresets
                    TabletViewportPresetStore.updateAvailableState(
                        availablePresetIds = fittingPresets.map { it.id },
                        stageWidthDp = maxWidth.value,
                        stageHeightDp = maxHeight.value,
                    )
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            if (mobileStageActive) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.background,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    if (mobileStageActive && stageSize != null) {
                        TabletViewportStage(
                            preset = selectedPreset,
                            stageSize = stageSize,
                            onClose = { TabletViewportPresetStore.setSelectedPresetId(null) },
                        ) {
                            WebViewContainer(
                                browserState = browserState,
                                handlerContext = handlerContext,
                                modifier = Modifier.fillMaxSize(),
                                onWebViewCreated = { wv ->
                                    webView = wv
                                    router.webView = wv
                                    handlerContext.webView = wv
                                },
                            )
                        }
                    } else {
                        WebViewContainer(
                            browserState = browserState,
                            handlerContext = handlerContext,
                            modifier = Modifier.fillMaxSize(),
                            onWebViewCreated = { wv ->
                                webView = wv
                                router.webView = wv
                                handlerContext.webView = wv
                            },
                        )
                    }
                }
            }
        }

        if (showWelcome && (forceShowWelcome || shouldShowWelcome(context))) {
            WelcomeCard(
                onDismiss = {
                    showWelcome = false
                    forceShowWelcome = false
                },
            )
        }

        // Floating action menu overlay
        FloatingMenu(
            onReload = { webView?.reload() },
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
                coroutineScope.launch {
                    if (handlerContext.isIn3DInspector) {
                        runCatching { handlerContext.evaluateJS(Snapshot3DBridge.EXIT_SCRIPT) }
                        handlerContext.mark3DInspectorInactive()
                    } else {
                        runCatching { handlerContext.evaluateJS(Snapshot3DBridge.ENTER_SCRIPT) }
                        val active = runCatching { handlerContext.evaluateJS("!!window.__m3d") }.getOrNull()
                        if (active?.contains("true") == true) {
                            handlerContext.isIn3DInspector = true
                        }
                    }
                }
            },
            show3DInspector = FeatureFlags.is3DInspectorEnabled(context),
            showMobileViewportToggle = isTablet,
            mobileViewportPresets = availableTabletViewportPresets,
            selectedMobileViewportPresetId = availableTabletViewportPresets
                .firstOrNull { it.id == tabletMobileStagePresetId }
                ?.id,
            onSelectMobileViewportPreset = { presetId ->
                val nextPresetId = if (tabletMobileStagePresetId == presetId) null else presetId
                TabletViewportPresetStore.setSelectedPresetId(nextPresetId)
            },
        )
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
            )
        }
    }

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

@Composable
private fun AIStatusSheet(onDismiss: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 16.dp),
    ) {
        Text("Local AI", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.size(12.dp))
        AIInfoRow("Backend", if (com.mollotov.browser.ai.AIState.backend == com.mollotov.browser.ai.AIState.OLLAMA_BACKEND) "Ollama" else "Platform")
        AIInfoRow("Availability", if (com.mollotov.browser.ai.AIState.isAvailable) "Available" else "Unavailable")
        AIInfoRow("Active Model", com.mollotov.browser.ai.AIState.activeModel ?: if (com.mollotov.browser.ai.AIState.isAvailable) "Platform AI" else "None")
        AIInfoRow(
            "Capabilities",
            if (com.mollotov.browser.ai.AIState.isAvailable || com.mollotov.browser.ai.AIState.activeModel != null) "text" else "None",
        )
        com.mollotov.browser.ai.AIState.ollamaEndpoint?.let { endpoint ->
            AIInfoRow("Ollama", endpoint)
        }
        Spacer(Modifier.size(12.dp))
        Text(
            text = if (com.mollotov.browser.ai.AIState.isAvailable) {
                "AI is available from the browser shell and the HTTP API."
            } else {
                "Platform AI is unavailable on this device right now. You can still load an Ollama model over the API."
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.size(16.dp))
        TextButton(onClick = onDismiss, modifier = Modifier.align(Alignment.End)) {
            Text("Done")
        }
    }
}

@Composable
private fun AIInfoRow(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        Text(value)
    }
}

private fun Context.isTabletDevice(): Boolean =
    resources.configuration.smallestScreenWidthDp >= 600

@Composable
private fun TabletViewportStage(
    preset: TabletViewportPreset,
    stageSize: Pair<Dp, Dp>,
    onClose: () -> Unit,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .size(stageSize.first, stageSize.second + 48.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .size(height = 38.dp, width = stageSize.first),
        ) {
            Text(
                text = "${preset.displaySizeLabel} • ${preset.pixelResolutionLabel}",
                color = Color.White,
                fontSize = 11.sp,
                modifier = Modifier
                    .align(Alignment.Center)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color.Black.copy(alpha = 0.9f))
                    .border(1.dp, Color.White.copy(alpha = 0.9f), RoundedCornerShape(18.dp))
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )

            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 0.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    contentAlignment = Alignment.Center,
                    modifier = Modifier
                        .size(34.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.9f))
                        .border(1.dp, Color.White.copy(alpha = 0.9f), CircleShape)
                        .clickable { onClose() },
                ) {
                    Icon(
                        imageVector = Icons.Filled.Close,
                        contentDescription = "Close staged viewport",
                        tint = Color.White,
                        modifier = Modifier.size(16.dp),
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
            }
        }

        Box(
            modifier = Modifier
                .padding(top = 10.dp)
                .size(stageSize.first, stageSize.second)
                .shadow(18.dp, RoundedCornerShape(26.dp)),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clip(RoundedCornerShape(26.dp))
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.7f), RoundedCornerShape(26.dp)),
            ) {
                content()
            }
        }
    }
}
