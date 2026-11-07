package com.kelpie.browser.ui

import android.webkit.WebView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.kelpie.browser.browser.BrowserState
import com.kelpie.browser.browser.TabStore
import com.kelpie.browser.handlers.HandlerContext

@Composable
internal fun BrowserViewport(
    tabStore: TabStore,
    browserState: BrowserState,
    handlerContext: HandlerContext,
    tabletMobileStagePresetId: String?,
    onAvailablePresets: (List<TabletViewportPreset>) -> Unit,
    onScrollDirectionChange: (ScrollDirection) -> Unit,
    onScrolled: () -> Unit,
    onWebViewReady: (WebView) -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(
        modifier = modifier,
    ) {
        val fittingPresets = tabletViewportPresetsThatFit(maxWidth = maxWidth, maxHeight = maxHeight)
        val selectedPreset = fittingPresets.firstOrNull { it.id == tabletMobileStagePresetId }
        val mobileStageActive = selectedPreset != null
        val stageSize =
            selectedPreset?.let {
                tabletMobileStageSize(
                    preset = it,
                    maxWidth = maxWidth,
                    maxHeight = maxHeight,
                )
            }

        LaunchedEffect(maxWidth, maxHeight) {
            onAvailablePresets(fittingPresets)
            TabletViewportPresetStore.updateAvailableState(
                availablePresetIds = fittingPresets.map { it.id },
                stageWidthDp = maxWidth.value,
                stageHeightDp = maxHeight.value,
            )
        }

        Box(
            modifier =
                Modifier
                    .fillMaxSize()
                    .background(
                        if (mobileStageActive) MaterialTheme.colorScheme.surfaceVariant else MaterialTheme.colorScheme.background,
                    ),
            contentAlignment = Alignment.Center,
        ) {
            val tabWebView: @Composable (Modifier) -> Unit = { mod ->
                TabWebViewContent(
                    tabStore = tabStore,
                    browserState = browserState,
                    handlerContext = handlerContext,
                    onScrollDirectionChange = onScrollDirectionChange,
                    onScrolled = onScrolled,
                    onWebViewReady = onWebViewReady,
                    modifier = mod,
                )
            }

            if (mobileStageActive && stageSize != null) {
                TabletViewportStage(
                    preset = selectedPreset,
                    stageSize = stageSize,
                    onClose = { TabletViewportPresetStore.setSelectedPresetId(null) },
                ) {
                    tabWebView(Modifier.fillMaxSize())
                }
            } else {
                tabWebView(Modifier.fillMaxSize())
            }
        }
    }
}
