package com.kelpie.browser.handlers

import android.app.Activity
import android.content.pm.ActivityInfo
import com.kelpie.browser.device.DeviceInfo
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import com.kelpie.browser.ui.TABLET_VIEWPORT_PRESETS
import com.kelpie.browser.ui.TabletViewportPresetStore

class DeviceHandler(
    private val ctx: HandlerContext,
    private val deviceInfo: DeviceInfo,
    private val activity: Activity? = null,
) {
    fun register(router: Router) {
        router.register("get-viewport") { getViewport() }
        router.register("get-viewport-presets") { getViewportPresets() }
        router.register("get-device-info") { getDeviceInfo() }
        router.register("get-capabilities") { getCapabilities() }
        router.register("set-orientation") { body -> setOrientation(body) }
        router.register("get-orientation") { getOrientation() }
    }

    private suspend fun getViewport(): Map<String, Any?> {
        val wv = ctx.webView ?: return errorResponse("NO_WEBVIEW", "No WebView")
        return mapOf(
            "width" to wv.width,
            "height" to wv.height,
            "devicePixelRatio" to wv.context.resources.displayMetrics.density,
            "platform" to "android",
            "deviceName" to deviceInfo.name,
            "orientation" to if (wv.width > wv.height) "landscape" else "portrait",
        )
    }

    private fun getDeviceInfo(): Map<String, Any?> = mapOf(
        "device" to mapOf("id" to deviceInfo.id, "name" to deviceInfo.name, "model" to deviceInfo.model, "platform" to "android"),
        "display" to mapOf("width" to deviceInfo.width, "height" to deviceInfo.height, "scale" to 1),
        "network" to mapOf("ip" to deviceInfo.ip, "port" to deviceInfo.port),
        "browser" to mapOf("engine" to "Chromium", "version" to android.os.Build.VERSION.RELEASE),
        "app" to mapOf("version" to deviceInfo.version, "build" to "1"),
        "system" to mapOf("os" to "Android", "osVersion" to android.os.Build.VERSION.RELEASE),
    )

    private fun getViewportPresets(): Map<String, Any?> {
        val availablePresetIds = TabletViewportPresetStore.availablePresetIds.value
        val activePresetId = TabletViewportPresetStore.selectedPresetId.value
            ?.takeIf { it in availablePresetIds }

        return successResponse(mapOf(
            "supportsViewportPresets" to true,
            "presets" to TABLET_VIEWPORT_PRESETS.map { preset ->
                mapOf(
                    "id" to preset.id,
                    "name" to preset.name,
                    "inches" to preset.displaySizeLabel,
                    "pixels" to preset.pixelResolutionLabel,
                    "viewport" to mapOf(
                        "portrait" to mapOf("width" to preset.portraitWidth.value.toInt(), "height" to preset.portraitHeight.value.toInt()),
                        "landscape" to mapOf("width" to preset.portraitHeight.value.toInt(), "height" to preset.portraitWidth.value.toInt()),
                    ),
                )
            },
            "availablePresetIds" to availablePresetIds,
            "activePresetId" to activePresetId,
        ))
    }

    private fun getOrientation(): Map<String, Any?> {
        val wv = ctx.webView
        val isLandscape = if (wv != null) wv.width > wv.height else false
        val locked = when (activity?.requestedOrientation) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE,
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE -> "landscape"
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT,
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT -> "portrait"
            else -> null
        }
        return successResponse(mapOf(
            "orientation" to if (isLandscape) "landscape" else "portrait",
            "locked" to locked,
        ))
    }

    private fun setOrientation(body: Map<String, Any?>): Map<String, Any?> {
        val orientation = body["orientation"] as? String
            ?: return errorResponse("MISSING_PARAM", "orientation is required (portrait|landscape|auto)")
        val act = activity ?: return errorResponse("NO_ACTIVITY", "Activity reference not available")
        when (orientation.lowercase()) {
            "landscape" -> act.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            "portrait" -> act.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            "auto" -> act.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            else -> return errorResponse("INVALID_PARAM", "orientation must be portrait, landscape, or auto")
        }
        return successResponse(mapOf("orientation" to orientation))
    }

    private fun getCapabilities(): Map<String, Any?> = mapOf(
        "cdp" to true,
        "nativeAPIs" to true,
        "bridgeScripts" to true,
        "screenshot" to true,
        "fullPageScreenshot" to true,
        "cookies" to true,
        "storage" to true,
        "geolocation" to true,
        "requestInterception" to true,
        "consoleLogs" to true,
        "networkLogs" to true,
        "mutations" to true,
        "shadowDOM" to true,
        "clipboard" to true,
        "keyboard" to true,
        "tabs" to true,
        "iframes" to true,
        "dialogs" to true,
        "viewportPresets" to true,
    )
}
