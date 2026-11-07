#include "kelpie/desktop_bridge.h"

namespace kelpie {

std::string ConsoleBridgeScript() {
  return R"JS(
(function() {
  if (!window.kelpieDesktopBridge || typeof window.kelpieDesktopBridge.postMessage !== 'function') {
    return;
  }
  const bridge = window.kelpieDesktopBridge;
  const levels = ['log', 'warn', 'error', 'info', 'debug'];
  for (const level of levels) {
    const original = console[level];
    console[level] = function(...args) {
      try {
        bridge.postMessage(JSON.stringify({
          channel: 'console',
          level,
          text: args.map(arg => {
            try { return typeof arg === 'string' ? arg : JSON.stringify(arg); }
            catch (_) { return String(arg); }
          }).join(' '),
          timestamp: new Date().toISOString()
        }));
      } catch (_) {}
      return original.apply(console, args);
    };
  }
})();
)JS";
}

std::string NetworkBridgeScript() {
  return R"JS(
(function() {
  if (!window.kelpieDesktopBridge || typeof window.kelpieDesktopBridge.postMessage !== 'function') {
    return;
  }
  const bridge = window.kelpieDesktopBridge;
  const send = payload => {
    try {
      bridge.postMessage(JSON.stringify(payload));
    } catch (_) {}
  };

  const originalFetch = window.fetch;
  window.fetch = async function(...args) {
    const started = Date.now();
    const response = await originalFetch.apply(this, args);
    send({
      channel: 'network',
      method: (args[1] && args[1].method) || 'GET',
      url: String(args[0]),
      status: response.status,
      contentType: response.headers.get('content-type') || '',
      duration: Date.now() - started,
      initiator: 'js'
    });
    return response;
  };

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url, ...rest) {
    this.__kelpieMeta = {method, url, started: 0};
    return originalOpen.call(this, method, url, ...rest);
  };
  XMLHttpRequest.prototype.send = function(body) {
    if (this.__kelpieMeta) {
      this.__kelpieMeta.started = Date.now();
    }
    this.addEventListener('loadend', () => {
      if (!this.__kelpieMeta) {
        return;
      }
      send({
        channel: 'network',
        method: this.__kelpieMeta.method,
        url: this.__kelpieMeta.url,
        status: this.status,
        contentType: this.getResponseHeader('content-type') || '',
        duration: Date.now() - this.__kelpieMeta.started,
        initiator: 'js'
      });
    });
    return originalSend.call(this, body);
  };
})();
)JS";
}

std::string CombinedBridgeScript() {
  return ConsoleBridgeScript() + "\n" + NetworkBridgeScript();
}

}  // namespace kelpie
