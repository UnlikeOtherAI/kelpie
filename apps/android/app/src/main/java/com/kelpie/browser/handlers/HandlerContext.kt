package com.kelpie.browser.handlers

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.webkit.WebView
import com.kelpie.browser.browser.DialogState
import com.kelpie.browser.browser.KeyboardObserver
import com.kelpie.browser.browser.TabStore
import com.kelpie.browser.nativecore.AiManager
import com.kelpie.browser.network.BrowserGatewayRetirement
import kotlinx.coroutines.asContextElement
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject
import java.io.ByteArrayOutputStream
import java.util.Base64
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import kotlin.math.max
import kotlin.math.roundToInt

private val json =
    Json {
        ignoreUnknownKeys = true
        isLenient = true
    }
private val mainHandler = Handler(Looper.getMainLooper())

class HandlerContext(val browserRetirement: BrowserGatewayRetirement = BrowserGatewayRetirement()) {
    companion object {
        const val DEFAULT_OVERLAY_RGB = "59,130,246"
    }

    var remoteDocumentGuard: (() -> Boolean)? = null
    var remoteNavigationStart: (() -> Boolean)? = null
    var remoteNavigationReadGuard: (() -> Boolean)? = null
    var remoteNavigationWaitGuard: (() -> Boolean)? = null
    private var visibleWebView: WebView? = null
    private val operationWebView = ThreadLocal<WebView>()
    var webView: WebView?
        get() = operationWebView.get() ?: visibleWebView
        set(value) {
            visibleWebView = value
        }

    /** A suspended handler keeps its admitted renderer even if the visible tab changes. */
    suspend fun <T> withBrowserTarget(
        view: WebView,
        block: suspend () -> T,
    ): T = withContext(operationWebView.asContextElement(view)) { block() }

    var tabStore: TabStore? = null
    var browserDocumentChanged: ((String) -> Unit)? = null
    var browserGateway: com.kelpie.browser.network.BrowserGatewayBinding? = null
    var keyboardObserver: KeyboardObserver? = null
    var scriptPlaybackState: ScriptPlaybackState? = null
    var annotationSessionId: String? = null
    var annotationPageURL: String? = null
    var annotationElementCount: Int? = null
    var aiManager: AiManager? = null
    val consoleMessages = mutableListOf<Map<String, Any?>>()
    val dialogState = DialogState()

    /** Most recent WebView navigation error (cleared on each new navigation). */
    @Volatile
    var lastNavigationError: String? = null
    private val consoleMessagesLock = Any()

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

    fun appendConsoleMessage(message: Map<String, Any?>) {
        synchronized(consoleMessagesLock) {
            consoleMessages.add(message)
            if (consoleMessages.size > 5000) {
                consoleMessages.removeFirst()
            }
        }
    }

    fun snapshotConsoleMessages(): List<Map<String, Any?>> =
        synchronized(consoleMessagesLock) {
            consoleMessages.toList()
        }

    fun clearConsoleMessages(): Int =
        synchronized(consoleMessagesLock) {
            val cleared = consoleMessages.size
            consoleMessages.clear()
            cleared
        }

    suspend fun evaluateJS(script: String): String = evaluateGuardedJS(script, remoteDocumentGuard)

    private suspend fun evaluateGuardedJS(
        script: String,
        guard: (() -> Boolean)?,
    ): String =
        suspendCancellableCoroutine { cont ->
            val wv = webView
            if (wv == null) {
                cont.resumeWithException(IllegalStateException("No WebView"))
                return@suspendCancellableCoroutine
            }
            val ticket = browserRetirement.start(wv) { cont.cancel() }
            mainHandler.post {
                if (cont.isActive) {
                    try {
                        check(guard?.invoke() != false) { "Tab document changed or job stopped" }
                        wv.evaluateJavascript(script) { result ->
                            browserRetirement.complete(ticket)
                            if (cont.isActive) {
                                if (guard?.invoke() == false) cont.resumeWithException(IllegalStateException("Tab document changed or job stopped"))
                                else cont.resume(result ?: "null")
                            }
                        }
                    } catch (error: Exception) {
                        browserRetirement.complete(ticket)
                        if (cont.isActive) cont.resumeWithException(error)
                    }
                } else {
                    browserRetirement.complete(ticket)
                }
            }
        }

    suspend fun evaluateJSReturningJSON(script: String): Map<String, Any?> {
        val wrapped = "JSON.stringify(($script))"
        val raw = evaluateJS(wrapped)
        return parseObject(raw)
    }

    /** Fixed metadata only: callers cannot use the transferred pin for arbitrary script/mutations. */
    suspend fun navigationSnapshot(): Map<String, Any?> {
        while (remoteNavigationReadGuard?.invoke() == false) {
            check(remoteNavigationWaitGuard?.invoke() == true) { "Navigation document changed or job stopped" }
            kotlinx.coroutines.delay(25)
        }
        val raw =
            evaluateGuardedJS(
                "JSON.stringify({url:location.href,title:document.title,readyState:document.readyState})",
                remoteNavigationReadGuard ?: remoteDocumentGuard,
            )
        return parseObject(raw)
    }

    private fun parseObject(raw: String): Map<String, Any?> {
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

    suspend fun captureScreenshotPayload(
        format: String = "png",
        quality: Int = 80,
        resolution: ScreenshotResolution = ScreenshotResolution.NATIVE,
    ): Map<String, Any?>? {
        val wv = webView ?: return null
        val normalizedFormat = if (format == "jpeg") "jpeg" else "png"
        val viewport = viewportMetrics()
        val bitmap =
            suspendCoroutine<Bitmap?> { cont ->
                mainHandler.post {
                    try {
                        val bmp = Bitmap.createBitmap(wv.width, wv.height, Bitmap.Config.ARGB_8888)
                        val canvas = Canvas(bmp)
                        wv.draw(canvas)
                        cont.resume(bmp)
                    } catch (_: Exception) {
                        cont.resume(null)
                    }
                }
            } ?: return null
        val rendered =
            if (resolution == ScreenshotResolution.VIEWPORT) {
                val targetWidth = max((bitmap.width / max(viewport.devicePixelRatio, 1.0)).roundToInt(), 1)
                val targetHeight = max((bitmap.height / max(viewport.devicePixelRatio, 1.0)).roundToInt(), 1)
                if (targetWidth == bitmap.width && targetHeight == bitmap.height) {
                    bitmap
                } else {
                    Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
                }
            } else {
                bitmap
            }

        return try {
            val stream = ByteArrayOutputStream()
            val compressFormat =
                if (normalizedFormat == "jpeg") {
                    Bitmap.CompressFormat.JPEG
                } else {
                    Bitmap.CompressFormat.PNG
                }
            rendered.compress(compressFormat, quality, stream)
            mapOf("image" to Base64.getEncoder().encodeToString(stream.toByteArray())) +
                viewport.metadata(
                    imageWidth = rendered.width,
                    imageHeight = rendered.height,
                    format = normalizedFormat,
                    resolution = resolution,
                )
        } finally {
            if (rendered !== bitmap) {
                rendered.recycle()
            }
            bitmap.recycle()
        }
    }

    suspend fun viewportMetrics(): ScreenshotViewportMetrics {
        val result =
            evaluateJSReturningJSON(
                """
                (function() {
                    return {
                        viewportWidth: Math.max(window.innerWidth || 0, 1),
                        viewportHeight: Math.max(window.innerHeight || 0, 1),
                        devicePixelRatio: window.devicePixelRatio || 1
                    };
                })()
                """.trimIndent(),
            )
        return ScreenshotViewportMetrics(
            viewportWidth = (result["viewportWidth"] as? Number)?.toInt() ?: 1,
            viewportHeight = (result["viewportHeight"] as? Number)?.toInt() ?: 1,
            devicePixelRatio = (result["devicePixelRatio"] as? Number)?.toDouble() ?: 1.0,
        )
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
