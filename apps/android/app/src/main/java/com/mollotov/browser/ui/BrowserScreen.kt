package com.mollotov.browser.ui

import android.app.Activity
import android.webkit.WebView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.mollotov.browser.browser.BrowserState
import com.mollotov.browser.browser.HistoryStore
import com.mollotov.browser.browser.WebViewContainer
import com.mollotov.browser.device.DeviceInfo
import com.mollotov.browser.handlers.HandlerContext
import com.mollotov.browser.network.Router

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
    val context = LocalContext.current
    var showWelcome by remember { mutableStateOf(shouldShowWelcome(context)) }
    var webView by remember { mutableStateOf<WebView?>(null) }
    var lastRecordedUrl by remember { mutableStateOf("") }

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
            )

            WebViewContainer(
                browserState = browserState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                onWebViewCreated = { wv ->
                    webView = wv
                    router.webView = wv
                    handlerContext.webView = wv
                },
            )
        }

        if (showWelcome) {
            WelcomeCard(onDismiss = { showWelcome = false })
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
            )
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
        // Brief delay for Compose to process dismissals
        kotlinx.coroutines.delay(400)
        when (panel) {
            "history" -> showHistory = true
            "bookmarks" -> showBookmarks = true
            "network-inspector" -> showNetworkInspector = true
            "settings" -> showSettings = true
        }
    }
}
