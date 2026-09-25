package com.kelpie.browser.ui

import android.content.Context
import android.content.Intent
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable

@Composable
internal fun BrowserMoreMenu(onDismiss: () -> Unit, onShowTabs: () -> Unit, onAddTab: () -> Unit,
    tabCount: Int, onShare: () -> Unit, onWelcome: () -> Unit, onChromeAuth: () -> Unit,
    onSettings: () -> Unit, onBookmarks: () -> Unit, onHistory: () -> Unit,
    onNetworkInspector: () -> Unit, onAI: () -> Unit, onSnapshot3D: () -> Unit,
    show3DInspector: Boolean, showMobileViewportToggle: Boolean,
    mobileViewportPresets: List<TabletViewportPreset>, selectedMobileViewportPresetId: String?,
    onSelectMobileViewportPreset: (String) -> Unit) {
    @Composable fun item(label: String, action: () -> Unit) {
        DropdownMenuItem(text = { Text(label) }, onClick = { onDismiss(); action() })
    }
    item("Tabs ($tabCount)", onShowTabs)
    item("New tab", onAddTab)
    item("Bookmarks", onBookmarks)
    item("Share page", onShare)
    HorizontalDivider()
    item("History", onHistory)
    item("Sign in with Chrome", onChromeAuth)
    item("AI", onAI)
    item("Network inspector", onNetworkInspector)
    if (show3DInspector) item("3D inspector", onSnapshot3D)
    if (showMobileViewportToggle) {
        HorizontalDivider()
        mobileViewportPresets.forEach { preset ->
            item((if (preset.id == selectedMobileViewportPresetId) "✓ " else "") + preset.menuLabel) { onSelectMobileViewportPreset(preset.id) }
        }
    }
    HorizontalDivider()
    item("Settings", onSettings)
    item("Show welcome screen", onWelcome)
}

internal fun sharePage(context: Context, url: String) {
    if (url.isBlank()) return
    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, url)
    }, "Share page"))
}
