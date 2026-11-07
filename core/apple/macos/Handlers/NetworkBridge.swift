import WebKit

/// JavaScript bridge that intercepts XMLHttpRequest and fetch to capture network traffic.
/// Must be injected BEFORE ConsoleHandler.bridgeScript (which masks messageHandlers).
enum NetworkBridge {
    static var bridgeScript: WKUserScript {
        let js = """
        (function() {
            var _post = window.webkit.messageHandlers.kelpieNetwork.postMessage.bind(
                window.webkit.messageHandlers.kelpieNetwork
            );

            // --- XMLHttpRequest interception ---
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
                    var duration = Date.now() - m.startTime;
                    var rh = {};
                    (self.getAllResponseHeaders() || '').split('\\r\\n').forEach(function(l) {
                        var i = l.indexOf(': ');
                        if (i > 0) rh[l.substring(0, i).toLowerCase()] = l.substring(i + 2);
                    });
                    try {
                        _post({
                            method: m.method || 'GET',
                            url: m.url || '',
                            statusCode: self.status,
                            contentType: self.getResponseHeader('Content-Type') || '',
                            requestHeaders: m.headers,
                            responseHeaders: rh,
                            requestBody: m.body,
                            responseBody: (self.responseType === '' || self.responseType === 'text')
                                ? (self.responseText || '').substring(0, 10000) : null,
                            duration: duration,
                            size: parseInt(self.getResponseHeader('Content-Length') || '0', 10)
                                || (self.responseText || '').length
                        });
                    } catch(e) {}
                });
                return origSend.apply(this, arguments);
            };

            // --- fetch interception ---
            var origFetch = window.fetch;
            var _pendingFetches = 0;
            var _maxPendingFetches = 100;
            window.fetch = function(input, init) {
                var signal = init && init.signal;
                if (signal && signal.aborted) return origFetch.apply(this, arguments);
                if (_pendingFetches >= _maxPendingFetches) return origFetch.apply(this, arguments);
                _pendingFetches++;
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
                var reqBody = (init && typeof init.body === 'string')
                    ? init.body.substring(0, 10000) : null;

                return origFetch.apply(this, arguments).then(function(response) {
                    _pendingFetches--;
                    var duration = Date.now() - startTime;
                    var respHeaders = {};
                    response.headers.forEach(function(v, k) { respHeaders[k] = v; });
                    var ct = response.headers.get('content-type') || '';
                    var clone = response.clone();
                    clone.text().then(function(text) {
                        try {
                            _post({
                                method: method, url: url, statusCode: response.status,
                                contentType: ct, requestHeaders: reqHeaders,
                                responseHeaders: respHeaders, requestBody: reqBody,
                                responseBody: text.substring(0, 10000),
                                duration: duration,
                                size: parseInt(response.headers.get('content-length') || '0', 10)
                                    || text.length
                            });
                        } catch(e) {}
                    }).catch(function() {
                        try {
                            _post({
                                method: method, url: url, statusCode: response.status,
                                contentType: ct, requestHeaders: reqHeaders,
                                responseHeaders: respHeaders, requestBody: reqBody,
                                responseBody: null, duration: duration,
                                size: parseInt(response.headers.get('content-length') || '0', 10) || 0
                            });
                        } catch(e) {}
                    });
                    return response;
                }).catch(function(err) {
                    _pendingFetches--;
                    throw err;
                });
            };
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
