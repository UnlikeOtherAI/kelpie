package com.mollotov.browser.handlers

import com.mollotov.browser.device.DeviceInfo
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse

class DeviceHandler(private val ctx: HandlerContext, private val deviceInfo: DeviceInfo) {
    fun register(router: Router) {
        router.register("get-viewport") { getViewport() }
        router.register("get-device-info") { getDeviceInfo() }
        router.register("get-capabilities") { getCapabilities() }
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
    )
}
