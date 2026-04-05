package com.kelpie.browser.browser

import android.webkit.JavascriptInterface
import com.kelpie.browser.devtools.ConsoleHandler
import org.json.JSONObject

/**
 * Android JS bridge exposed as `window.KelpieBridge`.
 * Receives console messages and network traffic events from injected scripts.
 */
class JsBridge(
    private val handlerContext: com.kelpie.browser.handlers.HandlerContext?,
    private val consoleHandler: ConsoleHandler?,
) {
    @JavascriptInterface
    fun onConsoleMessage(jsonString: String) {
        try {
            val obj = JSONObject(jsonString)
            val message = obj.optString("message", obj.optString("text", ""))
            if (message == "__kelpie_3d_exit__") {
                handlerContext?.mark3DInspectorInactive()
                return
            }
            val map = mutableMapOf<String, Any?>()
            for (key in obj.keys()) {
                map[key] = when {
                    obj.isNull(key) -> null
                    else -> obj.get(key)
                }
            }
            consoleHandler?.addMessage(map)
        } catch (_: Exception) {}
    }

    @JavascriptInterface
    fun on3DSnapshotEvent(jsonString: String) {
        try {
            val obj = JSONObject(jsonString)
            if (obj.optString("action") == "exit") {
                handlerContext?.mark3DInspectorInactive()
            }
        } catch (_: Exception) {}
    }

    @JavascriptInterface
    fun onNetworkEvent(jsonString: String) {
        try {
            val obj = JSONObject(jsonString)
            val reqHeaders = mutableMapOf<String, String>()
            obj.optJSONObject("requestHeaders")?.let { h ->
                for (k in h.keys()) reqHeaders[k] = h.optString(k, "")
            }
            val respHeaders = mutableMapOf<String, String>()
            obj.optJSONObject("responseHeaders")?.let { h ->
                for (k in h.keys()) respHeaders[k] = h.optString(k, "")
            }
            val entry = TrafficEntry(
                method = obj.optString("method", "GET").uppercase(),
                url = obj.optString("url", ""),
                statusCode = obj.optInt("statusCode", 0),
                contentType = obj.optString("contentType", ""),
                requestHeaders = reqHeaders,
                responseHeaders = respHeaders,
                requestBody = obj.opt("requestBody")?.toString(),
                responseBody = obj.opt("responseBody")?.toString(),
                duration = obj.optInt("duration", 0),
                size = obj.optInt("size", 0),
                initiator = "js",
            )
            NetworkTrafficStore.append(entry)
        } catch (_: Exception) {}
    }

    companion object {
        /** Network traffic capture script. Intercepts XHR and fetch, posts via KelpieBridge. */
        const val NETWORK_BRIDGE_SCRIPT = """
(function() {
    if (!window.KelpieBridge) return;
    var _post = function(data) {
        try { window.KelpieBridge.onNetworkEvent(JSON.stringify(data)); } catch(e) {}
    };

    var origOpen = XMLHttpRequest.prototype.open;
    var origSend = XMLHttpRequest.prototype.send;
    var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;

    XMLHttpRequest.prototype.open = function(method, url) {
        this._mltv = { method: method, url: String(url), headers: {}, startTime: 0 };
        return origOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (this._mltv) this._mltv.headers[name] = value;
        return origSetHeader.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(body) {
        if (this._mltv) {
            this._mltv.body = typeof body === 'string' ? body.substring(0, 10000) : null;
            this._mltv.startTime = Date.now();
        }
        var self = this;
        this.addEventListener('loadend', function() {
            if (!self._mltv) return;
            var m = self._mltv;
            var rh = {};
            (self.getAllResponseHeaders() || '').split('\r\n').forEach(function(l) {
                var i = l.indexOf(': ');
                if (i > 0) rh[l.substring(0, i).toLowerCase()] = l.substring(i + 2);
            });
            _post({
                method: m.method || 'GET', url: m.url || '', statusCode: self.status,
                contentType: self.getResponseHeader('Content-Type') || '',
                requestHeaders: m.headers, responseHeaders: rh, requestBody: m.body,
                responseBody: (self.responseType === '' || self.responseType === 'text')
                    ? (self.responseText || '').substring(0, 10000) : null,
                duration: Date.now() - m.startTime,
                size: parseInt(self.getResponseHeader('Content-Length') || '0', 10)
                    || (self.responseText || '').length
            });
        });
        return origSend.apply(this, arguments);
    };

    var origFetch = window.fetch;
    window.fetch = function(input, init) {
        var startTime = Date.now();
        var method = (init && init.method) || 'GET';
        var url = typeof input === 'string' ? input : (input && input.url) || '';
        var reqHeaders = {};
        if (init && init.headers) {
            if (init.headers instanceof Headers) {
                init.headers.forEach(function(v, k) { reqHeaders[k] = v; });
            } else if (typeof init.headers === 'object') {
                Object.keys(init.headers).forEach(function(k) { reqHeaders[k] = init.headers[k]; });
            }
        }
        var reqBody = (init && typeof init.body === 'string') ? init.body.substring(0, 10000) : null;
        return origFetch.apply(this, arguments).then(function(response) {
            var duration = Date.now() - startTime;
            var respHeaders = {};
            response.headers.forEach(function(v, k) { respHeaders[k] = v; });
            var ct = response.headers.get('content-type') || '';
            var clone = response.clone();
            clone.text().then(function(text) {
                _post({
                    method: method, url: url, statusCode: response.status,
                    contentType: ct, requestHeaders: reqHeaders,
                    responseHeaders: respHeaders, requestBody: reqBody,
                    responseBody: text.substring(0, 10000), duration: duration,
                    size: parseInt(response.headers.get('content-length') || '0', 10) || text.length
                });
            }).catch(function() {
                _post({
                    method: method, url: url, statusCode: response.status,
                    contentType: ct, requestHeaders: reqHeaders,
                    responseHeaders: respHeaders, requestBody: reqBody,
                    responseBody: null, duration: duration,
                    size: parseInt(response.headers.get('content-length') || '0', 10) || 0
                });
            });
            return response;
        });
    };
})();
"""
    }
}
