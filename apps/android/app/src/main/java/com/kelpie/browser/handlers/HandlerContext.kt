package com.kelpie.browser.handlers

import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import com.kelpie.browser.browser.DialogState
import com.kelpie.browser.browser.KeyboardObserver
import com.kelpie.browser.nativecore.AiManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

private val json =
    Json {
        ignoreUnknownKeys = true
        isLenient = true
    }
private val mainHandler = Handler(Looper.getMainLooper())

class HandlerContext {
    companion object {
        const val DEFAULT_OVERLAY_RGB = "59,130,246"
    }

    var webView: WebView? = null
    var keyboardObserver: KeyboardObserver? = null
    var scriptPlaybackState: ScriptPlaybackState? = null
    var aiManager: AiManager? = null
    val dialogState = DialogState()
    val chromeAuth =
        com.kelpie.browser.browser
            .ChromeAuthHelper()

    private val _activePanel = MutableStateFlow<String?>(null)
    private val _isIn3DInspector = MutableStateFlow(false)
    val activePanel: StateFlow<String?> = _activePanel
    val isIn3DInspectorFlow: StateFlow<Boolean> = _isIn3DInspector

    var isIn3DInspector: Boolean
        get() = _isIn3DInspector.value
        set(value) {
            _isIn3DInspector.value = value
        }

    fun requestPanel(panel: String) {
        _activePanel.value = panel
    }

    fun clearPanel() {
        _activePanel.value = null
    }

    fun mark3DInspectorInactive() {
        isIn3DInspector = false
    }

    suspend fun evaluateJS(script: String): String =
        suspendCoroutine { cont ->
            val wv = webView
            if (wv == null) {
                cont.resumeWithException(IllegalStateException("No WebView"))
                return@suspendCoroutine
            }
            mainHandler.post {
                wv.evaluateJavascript(script) { result ->
                    cont.resume(result ?: "null")
                }
            }
        }

    suspend fun evaluateJSReturningJSON(script: String): Map<String, Any?> {
        val wrapped = "JSON.stringify(($script))"
        val raw = evaluateJS(wrapped)
        // WebView returns a JSON-encoded string (escaped), so we need to unescape
        val unescaped =
            if (raw.startsWith("\"") && raw.endsWith("\"")) {
                json.decodeFromString<String>(raw)
            } else {
                raw
            }
        if (unescaped == "null" || unescaped.isBlank()) return emptyMap()
        return try {
            val element = json.parseToJsonElement(unescaped)
            jsonElementToMap(element)
        } catch (_: Exception) {
            emptyMap()
        }
    }

    suspend fun evaluateJSReturningArray(script: String): List<Map<String, Any?>> {
        val wrapped = "JSON.stringify(($script))"
        val raw = evaluateJS(wrapped)
        val unescaped =
            if (raw.startsWith("\"") && raw.endsWith("\"")) {
                json.decodeFromString<String>(raw)
            } else {
                raw
            }
        if (unescaped == "null" || unescaped.isBlank()) return emptyList()
        return try {
            val element = json.parseToJsonElement(unescaped)
            if (element is kotlinx.serialization.json.JsonArray) {
                element.map { jsonElementToMap(it) }
            } else {
                emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun jsonElementToMap(element: JsonElement): Map<String, Any?> {
        if (element !is kotlinx.serialization.json.JsonObject) return emptyMap()
        return element.jsonObject.entries.associate { (k, v) -> k to jsonElementToAny(v) }
    }

    suspend fun showTouchIndicator(
        x: Double,
        y: Double,
        color: String = DEFAULT_OVERLAY_RGB,
    ) {
        val js =
            """
            (function() {
                var dot = document.createElement('div');
                dot.style.cssText = 'position:fixed;left:${x}px;top:${y}px;width:36px;height:36px;' +
                    'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                    'background:rgba(${JSEscape.string(color)},0.7);pointer-events:none;z-index:2147483647;' +
                    'transition:transform 0.5s ease-out, opacity 0.5s ease-out;transform:scale(1);opacity:1;';
                document.body.appendChild(dot);
                var ripple = document.createElement('div');
                ripple.style.cssText = 'position:fixed;left:${x}px;top:${y}px;width:36px;height:36px;' +
                    'margin-left:-18px;margin-top:-18px;border-radius:50%;' +
                    'border:2px solid rgba(${JSEscape.string(color)},0.7);pointer-events:none;z-index:2147483647;' +
                    'transition:transform 0.6s ease-out, opacity 0.6s ease-out;transform:scale(1);opacity:1;';
                document.body.appendChild(ripple);
                requestAnimationFrame(function() {
                    ripple.style.transform = 'scale(3)';
                    ripple.style.opacity = '0';
                });
                setTimeout(function() {
                    dot.style.transform = 'scale(0.5)';
                    dot.style.opacity = '0';
                }, 550);
                setTimeout(function() { dot.remove(); ripple.remove(); }, 1100);
            })();
            """.trimIndent()
        try {
            evaluateJS(js)
        } catch (_: Exception) {
        }
    }

    suspend fun showTouchIndicatorForElement(
        selector: String,
        color: String = DEFAULT_OVERLAY_RGB,
    ) {
        val js =
            """
            (function() {
                var el = document.querySelector('${JSEscape.string(selector)}');
                if (!el) return JSON.stringify(null);
                var r = el.getBoundingClientRect();
                return JSON.stringify({x: r.left + r.width/2, y: r.top + r.height/2});
            })()
            """.trimIndent()
        try {
            val raw = evaluateJS(js)
            val unescaped =
                if (raw.startsWith("\"") && raw.endsWith("\"")) {
                    json.decodeFromString<String>(raw)
                } else {
                    raw
                }
            if (unescaped != "null") {
                val pos = json.parseToJsonElement(unescaped).jsonObject
                val px = pos["x"]?.toString()?.toDoubleOrNull()
                val py = pos["y"]?.toString()?.toDoubleOrNull()
                if (px != null && py != null) showTouchIndicator(px, py, color)
            }
        } catch (_: Exception) {
        }
    }

    suspend fun showToast(message: String) {
        val js =
            """
            (function() {
                var existing = document.getElementById('__kelpie_toast');
                if (existing) existing.remove();
                var toast = document.createElement('div');
                toast.id = '__kelpie_toast';
                toast.textContent = '${JSEscape.string(message)}';
                toast.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);' +
                    'max-width:390px;width:calc(100% - 32px);padding:14px 22px;border-radius:16px;' +
                    'background:rgba(0,0,0,0.5);color:#fff;font:15px/1.4 -apple-system,system-ui,sans-serif;' +
                    'text-align:center;pointer-events:none;z-index:2147483647;' +
                    'backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);' +
                    'transition:opacity 0.3s ease-out;opacity:0;';
                document.body.appendChild(toast);
                requestAnimationFrame(function() { toast.style.opacity = '1'; });
                setTimeout(function() {
                    toast.style.opacity = '0';
                    setTimeout(function() { toast.remove(); }, 300);
                }, 3000);
            })();
            """.trimIndent()
        try {
            evaluateJS(js)
        } catch (_: Exception) {
        }
    }

    private fun jsonElementToAny(element: JsonElement): Any? =
        when (element) {
            is kotlinx.serialization.json.JsonNull -> null
            is kotlinx.serialization.json.JsonPrimitive -> {
                when {
                    element.isString -> element.content
                    element.content == "true" -> true
                    element.content == "false" -> false
                    element.content.contains('.') -> element.content.toDoubleOrNull() ?: element.content
                    else -> element.content.toIntOrNull() ?: element.content.toLongOrNull() ?: element.content
                }
            }
            is kotlinx.serialization.json.JsonObject -> element.entries.associate { (k, v) -> k to jsonElementToAny(v) }
            is kotlinx.serialization.json.JsonArray -> element.map { jsonElementToAny(it) }
        }

    fun overlayColor(body: Map<String, Any?>): String = JSEscape.hexToRGB(body["color"] as? String)
}
