package com.kelpie.browser.ui

import android.content.Context
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

const val KEY_TABLET_MOBILE_STAGE = "tablet_mobile_stage_enabled"
const val KEY_TABLET_MOBILE_STAGE_PRESET = "tablet_mobile_stage_preset"
const val KEY_TABLET_MOBILE_STAGE_AVAILABLE_PRESET_IDS = "tablet_mobile_stage_available_preset_ids"
const val KEY_TABLET_MOBILE_STAGE_AVAILABLE_WIDTH_DP = "tablet_mobile_stage_available_width_dp"
const val KEY_TABLET_MOBILE_STAGE_AVAILABLE_HEIGHT_DP = "tablet_mobile_stage_available_height_dp"
const val DEFAULT_TABLET_MOBILE_STAGE_PRESET = "compact-base"
const val UI_PREFS_NAME = "kelpie_prefs"
private val TABLET_VIEWPORT_STAGE_PADDING = 24.dp
private val TABLET_VIEWPORT_STAGE_TOP_CHROME = 48.dp

data class TabletViewportPreset(
    val id: String,
    val name: String,
    val label: String,
    val menuLabel: String,
    val displaySizeLabel: String,
    val pixelResolutionLabel: String,
    val portraitWidth: Dp,
    val portraitHeight: Dp,
)

data class TabletViewportStageMetrics(
    val widthDp: Float = 0f,
    val heightDp: Float = 0f,
)

private fun viewportPresetSortValue(label: String): Float {
    val match = Regex("""[0-9]+(?:\.[0-9]+)?""").find(label) ?: return Float.MAX_VALUE
    return match.value.toFloatOrNull() ?: Float.MAX_VALUE
}

val TABLET_VIEWPORT_PRESETS =
    listOf(
        // Phones
        TabletViewportPreset(
            id = "flip-fold-cover",
            name = "Flip Fold (Cover)",
            label = "Flip C",
            menuLabel = "3.4\" Flip Cover",
            displaySizeLabel = "3.4\"",
            pixelResolutionLabel = "360 x 380",
            portraitWidth = 360.dp,
            portraitHeight = 380.dp,
        ),
        TabletViewportPreset(
            id = "book-fold-cover",
            name = "Book Fold (Cover)",
            label = "Book C",
            menuLabel = "6.3\" Book Cover",
            displaySizeLabel = "6.3\"",
            pixelResolutionLabel = "360 x 800",
            portraitWidth = 360.dp,
            portraitHeight = 800.dp,
        ),
        TabletViewportPreset(
            id = "compact-base",
            name = "Compact / Base",
            label = "Compact",
            menuLabel = "6.1\" Compact",
            displaySizeLabel = "6.1\"",
            pixelResolutionLabel = "393 x 852",
            portraitWidth = 393.dp,
            portraitHeight = 852.dp,
        ),
        TabletViewportPreset(
            id = "standard-pro",
            name = "Standard / Pro",
            label = "Standard",
            menuLabel = "6.2\" Standard",
            displaySizeLabel = "6.2\"",
            pixelResolutionLabel = "402 x 874",
            portraitWidth = 402.dp,
            portraitHeight = 874.dp,
        ),
        TabletViewportPreset(
            id = "flip-fold-internal",
            name = "Flip Fold (Internal)",
            label = "Flip In",
            menuLabel = "6.7\" Flip Fold",
            displaySizeLabel = "6.7\"",
            pixelResolutionLabel = "412 x 914",
            portraitWidth = 412.dp,
            portraitHeight = 914.dp,
        ),
        TabletViewportPreset(
            id = "large-plus",
            name = "Large / Plus",
            label = "Large",
            menuLabel = "6.7\" Large",
            displaySizeLabel = "6.7\"",
            pixelResolutionLabel = "430 x 932",
            portraitWidth = 430.dp,
            portraitHeight = 932.dp,
        ),
        TabletViewportPreset(
            id = "ultra-pro-max",
            name = "Ultra / Pro Max",
            label = "Ultra",
            menuLabel = "6.8\" Ultra",
            displaySizeLabel = "6.8\"",
            pixelResolutionLabel = "440 x 956",
            portraitWidth = 440.dp,
            portraitHeight = 956.dp,
        ),
        TabletViewportPreset(
            id = "book-fold-internal",
            name = "Book Fold (Internal)",
            label = "Book In",
            menuLabel = "7.6\" Book Fold",
            displaySizeLabel = "7.6\"",
            pixelResolutionLabel = "904 x 1136",
            portraitWidth = 904.dp,
            portraitHeight = 1136.dp,
        ),
        TabletViewportPreset(
            id = "tri-fold-internal",
            name = "Tri-Fold (Internal)",
            label = "Tri",
            menuLabel = "10\" Tri-Fold",
            displaySizeLabel = "~10.0\"",
            pixelResolutionLabel = "980 x 1120",
            portraitWidth = 980.dp,
            portraitHeight = 1120.dp,
        ),
        // Tablets
        TabletViewportPreset(
            id = "ipad-mini",
            name = "iPad mini",
            label = "mini",
            menuLabel = "8.3\" iPad mini",
            displaySizeLabel = "8.3\"",
            pixelResolutionLabel = "744 x 1133",
            portraitWidth = 744.dp,
            portraitHeight = 1133.dp,
        ),
        TabletViewportPreset(
            id = "ipad-10",
            name = "iPad 10.9\"",
            label = "iPad",
            menuLabel = "10.9\" iPad",
            displaySizeLabel = "10.9\"",
            pixelResolutionLabel = "820 x 1180",
            portraitWidth = 820.dp,
            portraitHeight = 1180.dp,
        ),
        TabletViewportPreset(
            id = "tab-s-11",
            name = "Galaxy Tab S 11\"",
            label = "Tab 11",
            menuLabel = "11\" Galaxy Tab S",
            displaySizeLabel = "11\"",
            pixelResolutionLabel = "800 x 1280",
            portraitWidth = 800.dp,
            portraitHeight = 1280.dp,
        ),
        TabletViewportPreset(
            id = "ipad-pro-11",
            name = "iPad Pro 11\"",
            label = "Pro 11",
            menuLabel = "11\" iPad Pro",
            displaySizeLabel = "11\"",
            pixelResolutionLabel = "834 x 1194",
            portraitWidth = 834.dp,
            portraitHeight = 1194.dp,
        ),
        TabletViewportPreset(
            id = "tab-s-12",
            name = "Galaxy Tab S 12.4\"",
            label = "Tab 12",
            menuLabel = "12.4\" Galaxy Tab",
            displaySizeLabel = "12.4\"",
            pixelResolutionLabel = "840 x 1344",
            portraitWidth = 840.dp,
            portraitHeight = 1344.dp,
        ),
        TabletViewportPreset(
            id = "ipad-air-13",
            name = "iPad Air 13\"",
            label = "Air 13",
            menuLabel = "13\" iPad Air",
            displaySizeLabel = "13\"",
            pixelResolutionLabel = "1024 x 1366",
            portraitWidth = 1024.dp,
            portraitHeight = 1366.dp,
        ),
        TabletViewportPreset(
            id = "ipad-pro-13",
            name = "iPad Pro 13\"",
            label = "Pro 13",
            menuLabel = "13\" iPad Pro",
            displaySizeLabel = "13\"",
            pixelResolutionLabel = "1032 x 1376",
            portraitWidth = 1032.dp,
            portraitHeight = 1376.dp,
        ),
        // Laptops
        TabletViewportPreset(
            id = "laptop-13",
            name = "13\" Laptop",
            label = "13\"",
            menuLabel = "13\" Laptop",
            displaySizeLabel = "13\"",
            pixelResolutionLabel = "1280 x 800",
            portraitWidth = 800.dp,
            portraitHeight = 1280.dp,
        ),
        TabletViewportPreset(
            id = "laptop-15",
            name = "15\" Laptop",
            label = "15\"",
            menuLabel = "15\" Laptop",
            displaySizeLabel = "15\"",
            pixelResolutionLabel = "1440 x 900",
            portraitWidth = 900.dp,
            portraitHeight = 1440.dp,
        ),
        TabletViewportPreset(
            id = "laptop-16",
            name = "16\" Laptop",
            label = "16\"",
            menuLabel = "16\" Laptop",
            displaySizeLabel = "16\"",
            pixelResolutionLabel = "1728 x 1117",
            portraitWidth = 1117.dp,
            portraitHeight = 1728.dp,
        ),
    ).sortedWith(compareBy<TabletViewportPreset>({ viewportPresetSortValue(it.displaySizeLabel) }, { it.name }))

fun tabletViewportPreset(id: String?): TabletViewportPreset? = TABLET_VIEWPORT_PRESETS.firstOrNull { it.id == id }

fun orientedTabletViewportSize(
    preset: TabletViewportPreset,
    maxWidth: Dp,
    maxHeight: Dp,
): Pair<Dp, Dp> =
    if (maxWidth > maxHeight) {
        preset.portraitHeight to preset.portraitWidth
    } else {
        preset.portraitWidth to preset.portraitHeight
    }

fun tabletViewportPresetsThatFit(
    maxWidth: Dp,
    maxHeight: Dp,
): List<TabletViewportPreset> {
    val availableWidth = (maxWidth - TABLET_VIEWPORT_STAGE_PADDING * 2).coerceAtLeast(1.dp)
    val availableHeight = (maxHeight - TABLET_VIEWPORT_STAGE_PADDING * 2 - TABLET_VIEWPORT_STAGE_TOP_CHROME).coerceAtLeast(1.dp)
    return TABLET_VIEWPORT_PRESETS.filter { preset ->
        val targetSize = orientedTabletViewportSize(preset = preset, maxWidth = maxWidth, maxHeight = maxHeight)
        targetSize.first <= availableWidth && targetSize.second <= availableHeight
    }
}

fun tabletMobileStageSize(
    preset: TabletViewportPreset,
    maxWidth: Dp,
    maxHeight: Dp,
): Pair<Dp, Dp> {
    val availableWidth = (maxWidth - TABLET_VIEWPORT_STAGE_PADDING * 2).coerceAtLeast(1.dp)
    val availableHeight = (maxHeight - TABLET_VIEWPORT_STAGE_PADDING * 2 - TABLET_VIEWPORT_STAGE_TOP_CHROME).coerceAtLeast(1.dp)
    val targetSize = orientedTabletViewportSize(preset = preset, maxWidth = maxWidth, maxHeight = maxHeight)

    return minOf(targetSize.first, availableWidth) to minOf(targetSize.second, availableHeight)
}

object TabletViewportPresetStore {
    private var initialized = false
    private lateinit var appContext: Context

    private val _selectedPresetId = MutableStateFlow<String?>(null)
    val selectedPresetId: StateFlow<String?> = _selectedPresetId.asStateFlow()

    private val _availablePresetIds = MutableStateFlow<List<String>>(emptyList())
    val availablePresetIds: StateFlow<List<String>> = _availablePresetIds.asStateFlow()

    private val _stageMetrics = MutableStateFlow(TabletViewportStageMetrics())
    val stageMetrics: StateFlow<TabletViewportStageMetrics> = _stageMetrics.asStateFlow()

    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        initialized = true

        val prefs = appContext.getSharedPreferences(UI_PREFS_NAME, Context.MODE_PRIVATE)
        val storedPreset = prefs.getString(KEY_TABLET_MOBILE_STAGE_PRESET, null)
        val legacyEnabled = prefs.getBoolean(KEY_TABLET_MOBILE_STAGE, false)
        val migratedPreset = storedPreset ?: if (legacyEnabled) DEFAULT_TABLET_MOBILE_STAGE_PRESET else null
        if (storedPreset == null && legacyEnabled) {
            prefs
                .edit()
                .putString(KEY_TABLET_MOBILE_STAGE_PRESET, migratedPreset)
                .putBoolean(KEY_TABLET_MOBILE_STAGE, false)
                .apply()
        }

        _selectedPresetId.value = migratedPreset
        _availablePresetIds.value =
            prefs
                .getString(KEY_TABLET_MOBILE_STAGE_AVAILABLE_PRESET_IDS, "")
                .orEmpty()
                .split(",")
                .filter { it.isNotBlank() }
        _stageMetrics.value =
            TabletViewportStageMetrics(
                widthDp = prefs.getFloat(KEY_TABLET_MOBILE_STAGE_AVAILABLE_WIDTH_DP, 0f),
                heightDp = prefs.getFloat(KEY_TABLET_MOBILE_STAGE_AVAILABLE_HEIGHT_DP, 0f),
            )
    }

    fun setSelectedPresetId(presetId: String?) {
        check(initialized) { "TabletViewportPresetStore.init() must be called before use" }
        _selectedPresetId.value = presetId
        appContext
            .getSharedPreferences(UI_PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TABLET_MOBILE_STAGE_PRESET, presetId)
            .putBoolean(KEY_TABLET_MOBILE_STAGE, false)
            .apply()
    }

    fun updateAvailableState(
        availablePresetIds: List<String>,
        stageWidthDp: Float,
        stageHeightDp: Float,
    ) {
        check(initialized) { "TabletViewportPresetStore.init() must be called before use" }
        _availablePresetIds.value = availablePresetIds
        _stageMetrics.value = TabletViewportStageMetrics(stageWidthDp, stageHeightDp)

        appContext
            .getSharedPreferences(UI_PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TABLET_MOBILE_STAGE_AVAILABLE_PRESET_IDS, availablePresetIds.joinToString(","))
            .putFloat(KEY_TABLET_MOBILE_STAGE_AVAILABLE_WIDTH_DP, stageWidthDp)
            .putFloat(KEY_TABLET_MOBILE_STAGE_AVAILABLE_HEIGHT_DP, stageHeightDp)
            .apply()

        val activePresetId = _selectedPresetId.value
        if (activePresetId != null && activePresetId !in availablePresetIds) {
            setSelectedPresetId(null)
        }
    }
}
