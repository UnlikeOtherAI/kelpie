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

            function requestUrl(input) {
                try {
                    var url = new URL(input instanceof Request ? input.url : input, document.baseURI);
                    url.hash = '';
                    return url.href;
                } catch(e) { return ''; }
            }

            function requestMethod(method) {
                var upper = String(method).toUpperCase();
                return ['DELETE', 'GET', 'HEAD', 'OPTIONS', 'POST', 'PUT'].includes(upper) ? upper : String(method);
            }

            // Sign-in payloads can contain passwords or session tokens. Keep them out
            // of the inspector, including when a page removes its form before sending.
            var handledPassword = false;
            document.addEventListener('focusin', function(event) {
                if (event.target instanceof HTMLInputElement && event.target.type === 'password') handledPassword = true;
            }, true);
            function isLoginDocument() {
                handledPassword = handledPassword || !!document.querySelector('input[type="password" i]');
                return handledPassword;
            }

            function recordLoginRequest(method, url, type, started, status) {
                try {
                    _post({ method: method, url: new URL(url).origin, type: type, started: started,
                        statusCode: status, duration: Math.round(performance.timeOrigin + performance.now() - started) });
                } catch(e) {}
            }

            // --- XMLHttpRequest interception ---
            var origOpen = XMLHttpRequest.prototype.open;
            var origSend = XMLHttpRequest.prototype.send;
            var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;

            XMLHttpRequest.prototype.open = function(method, url) {
                this._mltv = { method: requestMethod(method), url: requestUrl(url), headers: {}, startTime: 0 };
                return origOpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
                if (this._mltv) this._mltv.headers[name] = value;
                return origSetHeader.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function(body) {
                if (isLoginDocument()) {
                    var meta = this._mltv;
                    var started = performance.timeOrigin + performance.now();
                    if (meta) this.addEventListener('loadend', function() {
                        recordLoginRequest(meta.method, meta.url, 'xhr', started, this.status);
                    }, {once: true});
                    return origSend.apply(this, arguments);
                }
                if (this._mltv) {
                    this._mltv.body = typeof body === 'string' ? body.substring(0, 10000) : null;
                    this._mltv.startTime = performance.timeOrigin + performance.now();
                }
                var self = this;
                var m = this._mltv;
                this.addEventListener('loadend', function() {
                    if (!m) return;
                    var duration = Math.round(performance.timeOrigin + performance.now() - m.startTime);
                    var rh = {};
                    (self.getAllResponseHeaders() || '').split('\\r\\n').forEach(function(l) {
                        var i = l.indexOf(': ');
                        if (i > 0) rh[l.substring(0, i).toLowerCase()] = l.substring(i + 2);
                    });
                    try {
                        _post({
                            method: m.method,
                            url: m.url,
                            type: 'xhr',
                            started: m.startTime,
                            statusCode: self.status,
                            statusText: self.statusText,
                            failure: self.status === 0 ? 'XHR failed or was aborted' : null,
                            contentType: self.getResponseHeader('Content-Type') || '',
                            requestHeaders: m.headers,
                            responseHeaders: rh,
                            requestBody: m.body,
                            responseBody: (self.responseType === '' || self.responseType === 'text')
                                ? (self.responseText || '').substring(0, 10000) : null,
                            duration: duration,
                            size: parseInt(self.getResponseHeader('Content-Length') || '0', 10)
                                || ((self.responseType === '' || self.responseType === 'text')
                                    ? (self.responseText || '').length : 0)
                        });
                    } catch(e) {}
                }, {once: true});
                return origSend.apply(this, arguments);
            };

            // --- fetch interception ---
            var origFetch = window.fetch;
            var _pendingFetches = 0;
            var _maxPendingFetches = 100;
            window.fetch = function(input, init) {
                if (_pendingFetches >= _maxPendingFetches) return origFetch.apply(this, arguments);
                _pendingFetches++;
                var startTime = performance.timeOrigin + performance.now();
                var method = requestMethod((init && init.method) || (input instanceof Request && input.method) || 'GET');
                var url = requestUrl(input);
                if (isLoginDocument()) {
                    return origFetch.apply(this, arguments).then(function(response) {
                        _pendingFetches--;
                        recordLoginRequest(method, url, 'fetch', startTime, response.status);
                        return response;
                    }, function(error) {
                        _pendingFetches--;
                        recordLoginRequest(method, url, 'fetch', startTime, 0);
                        throw error;
                    });
                }
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
                    var duration = Math.round(performance.timeOrigin + performance.now() - startTime);
                    var respHeaders = {};
                    response.headers.forEach(function(v, k) { respHeaders[k] = v; });
                    var ct = response.headers.get('content-type') || '';
                    var clone = response.clone();
                    clone.text().then(function(text) {
                        try {
                            _post({
                                method: method, url: url, statusCode: response.status,
                                type: 'fetch', started: startTime, statusText: response.statusText,
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
                                type: 'fetch', started: startTime, statusText: response.statusText,
                                contentType: ct, requestHeaders: reqHeaders,
                                responseHeaders: respHeaders, requestBody: reqBody,
                                responseBody: null, duration: duration,
                                size: parseInt(response.headers.get('content-length') || '0', 10) || 0
                            });
                        } catch(e) {}
                    });
                    return response;
                }, function(err) {
                    _pendingFetches--;
                    try {
                        _post({
                            method: method, url: url, type: 'fetch', started: startTime, statusCode: 0,
                            failure: err && err.message || 'Fetch failed',
                            duration: Math.round(performance.timeOrigin + performance.now() - startTime)
                        });
                    } catch(e) {}
                    throw err;
                });
            };
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
