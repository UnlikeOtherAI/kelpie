package com.mollotov.browser.ui

import android.webkit.WebView
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.mollotov.browser.browser.BrowserState
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
    isServerRunning: Boolean,
    isMDNSAdvertising: Boolean,
) {
    val browserState = remember { BrowserState() }
    val currentUrl by browserState.currentUrl.collectAsState()
    val isLoading by browserState.isLoading.collectAsState()
    val canGoBack by browserState.canGoBack.collectAsState()
    val canGoForward by browserState.canGoForward.collectAsState()
    val progress by browserState.progress.collectAsState()
    var showSettings by remember { mutableStateOf(false) }
    var webView by remember { mutableStateOf<WebView?>(null) }

    Scaffold(
        floatingActionButton = {
            FloatingActionButton(onClick = { showSettings = true }) {
                Icon(Icons.Filled.Settings, contentDescription = "Settings")
            }
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
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
                onReload = { webView?.reload() },
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
}
