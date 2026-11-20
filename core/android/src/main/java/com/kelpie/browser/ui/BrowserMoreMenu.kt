package com.kelpie.browser.ui

import android.content.Context
import android.content.Intent
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics

@Composable
internal fun BrowserMoreMenu(
    onDismiss: () -> Unit,
    onShowTabs: () -> Unit,
    onAddTab: () -> Unit,
    tabCount: Int,
    onShare: () -> Unit,
    onWelcome: () -> Unit,
    onSettings: () -> Unit,
    onBookmarks: () -> Unit,
    onHistory: () -> Unit,
    onNetworkInspector: () -> Unit,
    onAI: () -> Unit,
    onSnapshot3D: (() -> Unit)?,
    is3DInspectorActive: Boolean,
    showMobileViewportToggle: Boolean,
    mobileViewportPresets: List<TabletViewportPreset>,
    selectedMobileViewportPresetId: String?,
    onSelectMobileViewportPreset: (String) -> Unit,
) {
    @Composable fun item(
        label: String,
        modifier: Modifier = Modifier,
        action: () -> Unit,
    ) {
        DropdownMenuItem(
            text = { Text(label) },
            onClick = {
                onDismiss()
                action()
            },
            modifier = modifier,
        )
    }
    item("Tabs ($tabCount)", action = onShowTabs)
    item("New tab", action = onAddTab)
    item("Bookmarks", action = onBookmarks)
    item("Share page", action = onShare)
    HorizontalDivider()
    item("History", action = onHistory)
    item("AI", action = onAI)
    if (onSnapshot3D != null) {
        item(
            "3D inspector",
            modifier = Modifier.testTag("browser.snapshot-3d.menu").semantics { selected = is3DInspectorActive },
            action = onSnapshot3D,
        )
    }
    item("Network inspector", action = onNetworkInspector)
    if (showMobileViewportToggle) {
        HorizontalDivider()
        mobileViewportPresets.forEach { preset ->
            item((if (preset.id == selectedMobileViewportPresetId) "✓ " else "") + preset.menuLabel) { onSelectMobileViewportPreset(preset.id) }
        }
    }
    HorizontalDivider()
    item("Settings", action = onSettings)
    item("Show welcome screen", action = onWelcome)
}

internal fun sharePage(
    context: Context,
    url: String,
) {
    if (url.isBlank()) return
    context.startActivity(
        Intent.createChooser(
            Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, url)
            },
            "Share page",
        ),
    )
}
