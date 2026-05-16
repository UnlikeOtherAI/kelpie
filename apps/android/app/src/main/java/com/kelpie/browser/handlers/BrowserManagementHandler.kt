package com.kelpie.browser.handlers

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.unit.dp
import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import com.kelpie.browser.ui.TabletViewportPresetStore
import com.kelpie.browser.ui.tabletMobileStageSize
import com.kelpie.browser.ui.tabletViewportPreset

class BrowserManagementHandler(
    private val ctx: HandlerContext,
    private val appContext: Context,
) {
    private val cookieHandlers = CookieHandlers(ctx)

    fun register(router: Router) {
        // Cookies (use CookieManager so HttpOnly/Secure cookies are visible)
        router.register("get-cookies") { cookieHandlers.getCookies(it) }
        router.register("set-cookie") { cookieHandlers.setCookie(it) }
        router.register("delete-cookies") { cookieHandlers.deleteCookies(it) }
        // Storage
        router.register("get-storage") { getStorage(it) }
        router.register("set-storage") { setStorage(it) }
        router.register("clear-storage") { clearStorage(it) }
        // Clipboard
        router.register("get-clipboard") { getClipboard() }
        router.register("set-clipboard") { setClipboard(it) }
        // Keyboard
        router.register("show-keyboard") { showKeyboard(it) }
        router.register("hide-keyboard") { hideKeyboard() }
        router.register("get-keyboard-state") { getKeyboardState() }
        // Viewport
        router.register("resize-viewport") { resizeViewport(it) }
        router.register("reset-viewport") { resetViewport() }
        router.register("set-viewport-preset") { setViewportPreset(it) }
        router.register("is-element-obscured") { isElementObscured(it) }
        // Iframes
        router.register("get-iframes") { getIframes() }
        router.register("switch-to-iframe") { switchToIframe(it) }
        router.register("switch-to-main") { successResponse(mapOf("context" to "main")) }
        router.register("get-iframe-context") { successResponse(mapOf("context" to "main")) }
        // Dialogs
        router.register("get-dialog") { getDialog() }
        router.register("handle-dialog") { handleDialog(it) }
        router.register("set-dialog-auto-handler") { setDialogAutoHandler(it) }
        // Tabs
        router.register("get-tabs") { getTabs() }
        router.register("new-tab") { newTab(it) }
        router.register("switch-tab") { switchTab(it) }
        router.register("close-tab") { closeTab(it) }
        // Geolocation & interception are not implemented on Android yet.
        router.register("set-geolocation") { unsupported("set-geolocation") }
        router.register("clear-geolocation") { unsupported("clear-geolocation") }
        router.register("set-request-interception") { unsupported("set-request-interception") }
        router.register("get-intercepted-requests") { unsupported("get-intercepted-requests") }
        router.register("clear-request-interception") { unsupported("clear-request-interception") }
    }

    private suspend fun getStorage(body: Map<String, Any?>): Map<String, Any?> {
        val type = body["type"] as? String ?: "local"
        val key = body["key"] as? String
        val storage = if (type == "session") "sessionStorage" else "localStorage"
        val js =
            if (key != null) {
                "({entries:{'${key.replace("'", "\\'")}':$storage.getItem('${key.replace("'", "\\'")}')},count:1,type:'$type'})"
            } else {
                "(function(){var e={};for(var i=0;i<$storage.length;i++){var k=$storage.key(i);e[k]=$storage.getItem(k);}return{entries:e,count:$storage.length,type:'$type'};})()"
            }
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun setStorage(body: Map<String, Any?>): Map<String, Any?> {
        val key = body["key"] as? String ?: return errorResponse("MISSING_PARAM", "key required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value required")
        val type = body["type"] as? String ?: "local"
        val storage = if (type == "session") "sessionStorage" else "localStorage"
        ctx.evaluateJS("$storage.setItem('${key.replace("'", "\\'")}','${value.replace("'", "\\'")}')")
        return successResponse()
    }

    private suspend fun clearStorage(body: Map<String, Any?>): Map<String, Any?> {
        val type = body["type"] as? String ?: "both"
        if (type == "local" || type == "both") ctx.evaluateJS("localStorage.clear()")
        if (type == "session" || type == "both") ctx.evaluateJS("sessionStorage.clear()")
        return successResponse(mapOf("cleared" to type))
    }

    private fun getClipboard(): Map<String, Any?> {
        val cm = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text =
            cm.primaryClip
                ?.getItemAt(0)
                ?.text
                ?.toString() ?: ""
        return successResponse(mapOf("text" to text, "hasImage" to false))
    }

    private fun setClipboard(body: Map<String, Any?>): Map<String, Any?> {
        val text = body["text"] as? String ?: ""
        val cm = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("kelpie", text))
        return successResponse()
    }

    private suspend fun showKeyboard(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String
        if (selector != null) {
            ctx.evaluateJS("document.querySelector('${selector.replace("'", "\\'")}')?.focus()")
        }
        toggleSoftKeyboard(show = true)
        val state = keyboardStatePayload()
        return successResponse(
            mapOf(
                "keyboardVisible" to state["visible"],
                "keyboardHeight" to state["height"],
                "visibleViewport" to state["visibleViewport"],
            ),
        )
    }

    private suspend fun hideKeyboard(): Map<String, Any?> {
        ctx.evaluateJS("document.activeElement?.blur()")
        toggleSoftKeyboard(show = false)
        val state = keyboardStatePayload()
        return successResponse(
            mapOf(
                "keyboardVisible" to state["visible"],
                "keyboardHeight" to state["height"],
                "visibleViewport" to state["visibleViewport"],
            ),
        )
    }

    private fun toggleSoftKeyboard(show: Boolean) {
        val wv = ctx.webView ?: return
        val imm = appContext.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager ?: return
        Handler(Looper.getMainLooper()).post {
            if (show) {
                wv.requestFocus()
                imm.showSoftInput(wv, InputMethodManager.SHOW_IMPLICIT)
            } else {
                val token = wv.windowToken
                if (token != null) {
                    imm.hideSoftInputFromWindow(token, 0)
                }
            }
        }
    }

    private fun getKeyboardState(): Map<String, Any?> = successResponse(keyboardStatePayload())

    private fun keyboardStatePayload(): Map<String, Any?> {
        val keyboardObserver = ctx.keyboardObserver
        val displayMetrics = appContext.resources.displayMetrics
        val density = displayMetrics.density
        val keyboardHeightPx = keyboardObserver?.height ?: 0
        val viewportWidthDp = (displayMetrics.widthPixels / density).toInt()
        val viewportHeightDp = ((displayMetrics.heightPixels - keyboardHeightPx).coerceAtLeast(0) / density).toInt()

        return mapOf(
            "visible" to (keyboardObserver?.isVisible ?: false),
            "height" to (keyboardHeightPx / density).toInt(),
            "type" to "default",
            "visibleViewport" to
                mapOf(
                    "width" to viewportWidthDp,
                    "height" to viewportHeightDp,
                ),
        )
    }

    private fun resizeViewport(body: Map<String, Any?>): Map<String, Any?> {
        val w = (body["width"] as? Int) ?: 360
        val h = (body["height"] as? Int) ?: 800
        TabletViewportPresetStore.setSelectedPresetId(null)
        return successResponse(
            mapOf(
                "viewport" to mapOf("width" to w, "height" to h),
                "activePresetId" to null,
            ),
        )
    }

    private fun resetViewport(): Map<String, Any?> {
        TabletViewportPresetStore.setSelectedPresetId(null)
        return successResponse(
            mapOf(
                "viewport" to mapOf("width" to 360, "height" to 800),
                "activePresetId" to null,
            ),
        )
    }

    private fun setViewportPreset(body: Map<String, Any?>): Map<String, Any?> {
        val presetId =
            body["presetId"] as? String
                ?: return errorResponse("MISSING_PARAM", "presetId is required")
        val preset =
            tabletViewportPreset(presetId)
                ?: return errorResponse("INVALID_PARAM", "Unknown viewport preset id: $presetId")
        val availablePresetIds = TabletViewportPresetStore.availablePresetIds.value
        if (preset.id !in availablePresetIds) {
            return mapOf(
                "success" to false,
                "error" to
                    mapOf(
                        "code" to "INVALID_PARAM",
                        "message" to "Viewport preset $presetId is not available for the current device geometry",
                        "reason" to "unavailable",
                    ),
            )
        }

        val stageMetrics = TabletViewportPresetStore.stageMetrics.value
        if (stageMetrics.widthDp <= 0f || stageMetrics.heightDp <= 0f) {
            return errorResponse("INVALID_PARAM", "Viewport preset geometry is not ready yet")
        }

        TabletViewportPresetStore.setSelectedPresetId(preset.id)
        val viewportSize =
            tabletMobileStageSize(
                preset = preset,
                maxWidth = stageMetrics.widthDp.dp,
                maxHeight = stageMetrics.heightDp.dp,
            )
        val density = appContext.resources.displayMetrics.density

        return successResponse(
            mapOf(
                "activePresetId" to preset.id,
                "preset" to
                    mapOf(
                        "id" to preset.id,
                        "name" to preset.name,
                        "inches" to preset.displaySizeLabel,
                        "pixels" to preset.pixelResolutionLabel,
                    ),
                "viewport" to
                    mapOf(
                        "width" to (viewportSize.first.value * density).toInt(),
                        "height" to (viewportSize.second.value * density).toInt(),
                    ),
            ),
        )
    }

    private fun unsupported(method: String): Map<String, Any?> =
        errorResponse(
            "PLATFORM_NOT_SUPPORTED",
            "$method is not implemented on Android yet",
        )

    private suspend fun isElementObscured(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        val js =
            "(function(){var el=document.querySelector('$safe');if(!el)return null;" +
                "var r=el.getBoundingClientRect();" +
                "return{x:r.x,y:r.y,width:r.width,height:r.height,bottom:r.bottom};})()"
        return try {
            val rect = ctx.evaluateJSReturningJSON(js)
            if (rect.isEmpty()) return errorResponse("ELEMENT_NOT_FOUND", "Element not found")

            val elementBottomCss = (rect["bottom"] as? Number)?.toDouble() ?: 0.0
            val elementRect =
                mapOf(
                    "x" to rect["x"],
                    "y" to rect["y"],
                    "width" to rect["width"],
                    "height" to rect["height"],
                )

            val keyboardObserver = ctx.keyboardObserver
            val displayMetrics = appContext.resources.displayMetrics
            val density = displayMetrics.density
            val screenHeightDp = displayMetrics.heightPixels / density
            val keyboardHeightPx = keyboardObserver?.height ?: 0
            val keyboardHeightDp = keyboardHeightPx / density
            val visibleHeightDp = screenHeightDp - keyboardHeightDp

            val keyboardVisible = keyboardObserver?.isVisible ?: false
            val obscured = keyboardVisible && elementBottomCss > visibleHeightDp
            val overlapDp = if (obscured) (elementBottomCss - visibleHeightDp).toInt() else null

            successResponse(
                mapOf(
                    "element" to mapOf("selector" to safe, "rect" to elementRect),
                    "obscured" to obscured,
                    "reason" to if (obscured) "keyboard" else null,
                    "keyboardOverlap" to overlapDp,
                    "suggestion" to if (obscured) "scroll-into-view" else null,
                ),
            )
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getIframes(): Map<String, Any?> {
        val js =
            "(function(){var frames=document.querySelectorAll('iframe');" +
                "return{iframes:Array.from(frames).map(function(f,i){var r=f.getBoundingClientRect();" +
                "return{id:i,src:f.src||'',name:f.name||'',selector:'iframe:nth-of-type('+(i+1)+')'," +
                "rect:{x:r.x,y:r.y,width:r.width,height:r.height}," +
                "visible:r.width>0&&r.height>0,crossOrigin:false};}),count:frames.length};})()"
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private fun switchToIframe(body: Map<String, Any?>): Map<String, Any?> {
        val id = (body["iframeId"] as? Int) ?: 0
        return successResponse(mapOf("iframe" to mapOf("id" to id, "src" to ""), "context" to "iframe"))
    }

    private fun getDialog(): Map<String, Any?> {
        val dialog = ctx.dialogState.current ?: return successResponse(mapOf("showing" to false, "dialog" to null))
        return successResponse(
            mapOf(
                "showing" to true,
                "dialog" to
                    mapOf(
                        "type" to dialog.type,
                        "message" to dialog.message,
                        "defaultValue" to dialog.defaultText,
                    ),
            ),
        )
    }

    private fun handleDialog(body: Map<String, Any?>): Map<String, Any?> {
        val action = body["action"] as? String ?: "accept"
        val text = body["promptText"] as? String ?: body["text"] as? String
        val handled = ctx.dialogState.handle(action, text) ?: return errorResponse("NO_DIALOG", "No dialog is currently showing")
        return successResponse(
            mapOf(
                "action" to action,
                "dialogType" to handled.type,
            ),
        )
    }

    private fun setDialogAutoHandler(body: Map<String, Any?>): Map<String, Any?> {
        val enabled = body["enabled"] as? Boolean ?: true
        val defaultAction = body["defaultAction"] as? String ?: "accept"
        ctx.dialogState.autoHandler =
            if (enabled && defaultAction != "queue") {
                defaultAction
            } else {
                null
            }
        ctx.dialogState.autoPromptText = body["promptText"] as? String ?: ""
        return successResponse(mapOf("enabled" to enabled))
    }

    private suspend fun getTabs(): Map<String, Any?> {
        val tabStore = ctx.tabStore
        if (tabStore == null) {
            val wv = ctx.webView
            val tab =
                mapOf(
                    "id" to "0",
                    "url" to (wv?.url ?: ""),
                    "title" to (wv?.title ?: ""),
                    "active" to true,
                    "isLoading" to false,
                )
            return successResponse(mapOf("tabs" to listOf(tab), "count" to 1, "activeTab" to "0"))
        }

        val tabs =
            tabStore.tabs.value.map { tab ->
                tabInfo(tab = tab, activeTabId = tabStore.activeTabId.value)
            }
        return successResponse(
            mapOf(
                "tabs" to tabs,
                "count" to tabs.size,
                "activeTab" to (tabStore.activeTabId.value ?: ""),
            ),
        )
    }

    private fun newTab(body: Map<String, Any?>): Map<String, Any?> {
        val tabStore = ctx.tabStore ?: return errorResponse("NO_TAB_STORE", "Tab store not available")
        val url = body["url"] as? String
        val tab = tabStore.addTab(url)
        return successResponse(
            mapOf(
                "tab" to tabInfo(tab = tab, activeTabId = tabStore.activeTabId.value),
                "tabCount" to tabStore.tabs.value.size,
            ),
        )
    }

    private fun switchTab(body: Map<String, Any?>): Map<String, Any?> {
        val tabStore = ctx.tabStore ?: return errorResponse("NO_TAB_STORE", "Tab store not available")
        val tabId =
            parseTabId(body)
                ?: return errorResponse("MISSING_PARAM", "tabId (UUID string) is required")
        val tab =
            tabStore.tabs.value.firstOrNull { it.id == tabId }
                ?: return errorResponse("TAB_NOT_FOUND", "No tab with id $tabId")
        tabStore.selectTab(tabId)
        return successResponse(
            mapOf(
                "tab" to tabInfo(tab = tab, activeTabId = tabStore.activeTabId.value),
            ),
        )
    }

    private fun closeTab(body: Map<String, Any?>): Map<String, Any?> {
        val tabStore = ctx.tabStore ?: return errorResponse("NO_TAB_STORE", "Tab store not available")
        val tabId =
            parseTabId(body)
                ?: return errorResponse("MISSING_PARAM", "tabId (UUID string) is required")
        val exists = tabStore.tabs.value.any { it.id == tabId }
        if (!exists) {
            return errorResponse("TAB_NOT_FOUND", "No tab with id $tabId")
        }
        tabStore.closeTab(tabId)
        return successResponse(
            mapOf(
                "closed" to tabId,
                "tabCount" to tabStore.tabs.value.size,
            ),
        )
    }

    private fun parseTabId(body: Map<String, Any?>): String? = body["tabId"] as? String ?: body["id"] as? String

    private fun tabInfo(
        tab: com.kelpie.browser.browser.BrowserTab,
        activeTabId: String?,
    ): Map<String, Any?> =
        mapOf(
            "id" to tab.id,
            "url" to tab.currentUrl,
            "title" to tab.pageTitle,
            "active" to (tab.id == activeTabId),
            "isLoading" to tab.isLoading,
        )
}
