package com.kelpie.browser.browser

import android.util.Base64
import android.webkit.WebView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.json.JSONTokener
import java.io.IOException
import java.io.OutputStream
import java.util.UUID
import kotlin.coroutines.resume

// No JavaScript interface is installed. Pull one bounded chunk from the originating document
// at a time. Navigation or a revoked blob invalidates this transfer.
internal suspend fun copyPageDownload(
    view: WebView,
    address: String,
    output: OutputStream,
) {
    val key = JSONObject.quote("kelpie-download-${UUID.randomUUID()}")
    val slot = "window[$key]"
    try {
        view.evaluate(
            """(() => {
                const state = $slot = {};
                fetch(${JSONObject.quote(address)}).then(r => r.blob()).then(b => state.blob = b)
                    .catch(() => state.error = true);
            })()""",
        )
        var offset = 0L
        while (true) {
            val script =
                """(() => {
                    const s = $slot;
                    if (!s || s.error) return 'failed';
                    if (!s.blob || s.reading) return 'wait';
                    if (s.data !== undefined) { const d = s.data; delete s.data; return 'bytes:' + d; }
                    if ($offset >= s.blob.size) return 'done';
                    const r = new FileReader();
                    s.reading = true;
                    r.onload = () => { s.data = r.result.split(',')[1]; s.reading = false; };
                    r.onerror = () => s.error = true;
                    r.readAsDataURL(s.blob.slice($offset, $offset + 65536));
                    return 'wait';
                })()"""
            val chunk =
                withTimeout(30000) {
                    var value = view.evaluate(script)
                    while (value == "wait") {
                        delay(20)
                        value = view.evaluate(script)
                    }
                    value
                }
            if (chunk == "done") return
            if (!chunk.startsWith("bytes:")) throw IOException("The page download is unavailable")
            val bytes = Base64.decode(chunk.removePrefix("bytes:"), Base64.NO_WRAP)
            output.write(bytes)
            offset += bytes.size
        }
    } finally {
        view.evaluate("delete $slot")
    }
}

private suspend fun WebView.evaluate(script: String): String =
    withContext(Dispatchers.Main) {
        withTimeout(10000) {
            suspendCancellableCoroutine { continuation ->
                evaluateJavascript(script) { json ->
                    if (continuation.isActive) {
                        continuation.resume(runCatching { JSONTokener(json).nextValue() as? String }.getOrNull().orEmpty())
                    }
                }
            }
        }
    }
