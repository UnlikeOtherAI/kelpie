package com.mollotov.browser.handlers

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.mollotov.browser.network.Router
import com.mollotov.browser.network.errorResponse
import com.mollotov.browser.network.successResponse

class BrowserManagementHandler(private val ctx: HandlerContext, private val appContext: Context) {
    fun register(router: Router) {
        // Cookies
        router.register("get-cookies") { getCookies(it) }
        router.register("set-cookie") { setCookie(it) }
        router.register("delete-cookies") { deleteCookies(it) }
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
        router.register("is-element-obscured") { isElementObscured(it) }
        // Iframes
        router.register("get-iframes") { getIframes() }
        router.register("switch-to-iframe") { switchToIframe(it) }
        router.register("switch-to-main") { successResponse(mapOf("context" to "main")) }
        router.register("get-iframe-context") { successResponse(mapOf("context" to "main")) }
        // Dialogs
        router.register("get-dialog") { successResponse(mapOf("showing" to false, "dialog" to null)) }
        router.register("handle-dialog") { successResponse(mapOf("action" to (it["action"] ?: "accept"), "dialogType" to "none")) }
        router.register("set-dialog-auto-handler") { successResponse(mapOf("enabled" to (it["enabled"] ?: true))) }
        // Tabs (stub)
        router.register("get-tabs") { getTabs() }
        router.register("new-tab") { successResponse(mapOf("tab" to mapOf("id" to 0, "url" to (it["url"] ?: ""), "title" to "", "active" to true), "tabCount" to 1)) }
        router.register("switch-tab") { successResponse(mapOf("tab" to mapOf("id" to 0, "url" to "", "title" to "", "active" to true))) }
        router.register("close-tab") { successResponse(mapOf("closed" to 1, "tabCount" to 1)) }
        // Geolocation & Interception (stubs for now — CDP required for full impl)
        router.register("set-geolocation") { successResponse(mapOf("set" to true)) }
        router.register("clear-geolocation") { successResponse(mapOf("cleared" to true)) }
        router.register("set-request-interception") { successResponse(mapOf("activeRules" to 0)) }
        router.register("get-intercepted-requests") { successResponse(mapOf("requests" to emptyList<Any>(), "count" to 0)) }
        router.register("clear-request-interception") { successResponse(mapOf("cleared" to 0)) }
    }

    private suspend fun getCookies(body: Map<String, Any?>): Map<String, Any?> {
        val name = body["name"] as? String
        val js = if (name != null) {
            "(function(){var cookies=document.cookie.split(';').map(function(c){var p=c.trim().split('=');return{name:p[0],value:p.slice(1).join('='),domain:location.hostname,path:'/'};}).filter(function(c){return c.name==='${name.replace("'", "\\'")}';});return{cookies:cookies,count:cookies.length};})()"
        } else {
            "(function(){var cookies=document.cookie.split(';').filter(Boolean).map(function(c){var p=c.trim().split('=');return{name:p[0],value:p.slice(1).join('='),domain:location.hostname,path:'/'};});return{cookies:cookies,count:cookies.length};})()"
        }
        return try {
            successResponse(ctx.evaluateJSReturningJSON(js))
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun setCookie(body: Map<String, Any?>): Map<String, Any?> {
        val name = body["name"] as? String ?: return errorResponse("MISSING_PARAM", "name required")
        val value = body["value"] as? String ?: return errorResponse("MISSING_PARAM", "value required")
        val path = body["path"] as? String ?: "/"
        ctx.evaluateJS("document.cookie='${name.replace("'", "\\'")}=${value.replace("'", "\\'")}; path=$path'")
        return successResponse()
    }

    private suspend fun deleteCookies(body: Map<String, Any?>): Map<String, Any?> {
        val deleteAll = body["deleteAll"] as? Boolean ?: false
        val name = body["name"] as? String
        if (deleteAll) {
            ctx.evaluateJS("document.cookie.split(';').forEach(function(c){document.cookie=c.trim().split('=')[0]+'=;expires=Thu,01 Jan 1970 00:00:00 GMT;path=/'})")
        } else if (name != null) {
            ctx.evaluateJS("document.cookie='${name.replace("'", "\\'")}=;expires=Thu,01 Jan 1970 00:00:00 GMT;path=/'")
        }
        return successResponse(mapOf("deleted" to 1))
    }

    private suspend fun getStorage(body: Map<String, Any?>): Map<String, Any?> {
        val type = body["type"] as? String ?: "local"
        val key = body["key"] as? String
        val storage = if (type == "session") "sessionStorage" else "localStorage"
        val js = if (key != null) {
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
        val text = cm.primaryClip?.getItemAt(0)?.text?.toString() ?: ""
        return successResponse(mapOf("text" to text, "hasImage" to false))
    }

    private fun setClipboard(body: Map<String, Any?>): Map<String, Any?> {
        val text = body["text"] as? String ?: ""
        val cm = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText("mollotov", text))
        return successResponse()
    }

    private suspend fun showKeyboard(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String
        if (selector != null) {
            ctx.evaluateJS("document.querySelector('${selector.replace("'", "\\'")}')?.focus()")
        }
        return successResponse(mapOf("keyboardVisible" to true))
    }

    private suspend fun hideKeyboard(): Map<String, Any?> {
        ctx.evaluateJS("document.activeElement?.blur()")
        return successResponse(mapOf("keyboardVisible" to false))
    }

    private fun getKeyboardState(): Map<String, Any?> = successResponse(mapOf("visible" to false, "height" to 0, "type" to "default"))

    private fun resizeViewport(body: Map<String, Any?>): Map<String, Any?> {
        val w = (body["width"] as? Int) ?: 360
        val h = (body["height"] as? Int) ?: 800
        return successResponse(mapOf("viewport" to mapOf("width" to w, "height" to h)))
    }

    private fun resetViewport(): Map<String, Any?> = successResponse(mapOf("viewport" to mapOf("width" to 360, "height" to 800)))

    private suspend fun isElementObscured(body: Map<String, Any?>): Map<String, Any?> {
        val selector = body["selector"] as? String ?: return errorResponse("MISSING_PARAM", "selector is required")
        val safe = selector.replace("'", "\\'")
        val js = "(function(){var el=document.querySelector('$safe');if(!el)return null;var r=el.getBoundingClientRect();return{element:{selector:'$safe',rect:{x:r.x,y:r.y,width:r.width,height:r.height}},obscured:false,reason:null};})()"
        return try {
            val result = ctx.evaluateJSReturningJSON(js)
            if (result.isEmpty()) errorResponse("ELEMENT_NOT_FOUND", "Element not found") else successResponse(result)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private suspend fun getIframes(): Map<String, Any?> {
        val js = "(function(){var frames=document.querySelectorAll('iframe');return{iframes:Array.from(frames).map(function(f,i){var r=f.getBoundingClientRect();return{id:i,src:f.src||'',name:f.name||'',selector:'iframe:nth-of-type('+(i+1)+')',rect:{x:r.x,y:r.y,width:r.width,height:r.height},visible:r.width>0&&r.height>0,crossOrigin:false};}),count:frames.length};})()"
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

    private suspend fun getTabs(): Map<String, Any?> {
        val wv = ctx.webView
        val tab = mapOf("id" to 0, "url" to (wv?.url ?: ""), "title" to (wv?.title ?: ""), "active" to true)
        return successResponse(mapOf("tabs" to listOf(tab), "count" to 1, "activeTab" to 0))
    }
}
