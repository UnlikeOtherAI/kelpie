import WebKit

/// Handles watchMutations, getMutations, stopWatching.
/// Injects a MutationObserver bridge script and buffers mutations in JS for retrieval.
struct MutationHandler {
    let context: HandlerContext

    func register(on router: Router) {
        router.register("watch-mutations") { body in await watchMutations(body) }
        router.register("get-mutations") { body in await getMutations(body) }
        router.register("stop-watching") { body in await stopWatching(body) }
    }

    @MainActor
    private func watchMutations(_ body: [String: Any]) async -> [String: Any] {
        let selector = body["selector"] as? String ?? "body"
        let attributes = body["attributes"] as? Bool ?? true
        let childList = body["childList"] as? Bool ?? true
        let subtree = body["subtree"] as? Bool ?? true
        let characterData = body["characterData"] as? Bool ?? false
        let safeSelector = selector.replacingOccurrences(of: "'", with: "\\'")

        let js = """
        (function(){
            if (!window.__kelpieMutations) window.__kelpieMutations = {};
            var id = 'mut_' + Date.now();
            var buffer = [];
            var target = document.querySelector('\(safeSelector)');
            if (!target) return null;
            var observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(m) {
                    var entry = {
                        type: m.type,
                        target: m.target.tagName ? m.target.tagName.toLowerCase() + (m.target.className ? '.' + m.target.className.split(' ')[0] : '') : 'text',
                        timestamp: new Date().toISOString()
                    };
                    if (m.type === 'childList') {
                        entry.added = Array.from(m.addedNodes).filter(function(n){return n.nodeType===1;}).map(function(n){
                            return {tag: n.tagName.toLowerCase(), class: n.className || '', text: (n.textContent||'').trim().substring(0,50)};
                        });
                        entry.removed = Array.from(m.removedNodes).filter(function(n){return n.nodeType===1;}).map(function(n){
                            return {tag: n.tagName.toLowerCase(), class: n.className || '', text: (n.textContent||'').trim().substring(0,50)};
                        });
                    } else if (m.type === 'attributes') {
                        entry.attribute = m.attributeName;
                        entry.oldValue = m.oldValue;
                        entry.newValue = m.target.getAttribute(m.attributeName);
                    } else if (m.type === 'characterData') {
                        entry.oldValue = m.oldValue;
                        entry.newValue = m.target.textContent;
                    }
                    buffer.push(entry);
                    if (buffer.length > 1000) buffer.shift();
                });
            });
            observer.observe(target, {
                attributes: \(attributes),
                childList: \(childList),
                subtree: \(subtree),
                characterData: \(characterData),
                attributeOldValue: \(attributes),
                characterDataOldValue: \(characterData)
            });
            window.__kelpieMutations[id] = {observer: observer, buffer: buffer};
            return {watchId: id, watching: true};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "ELEMENT_NOT_FOUND", message: "Target element not found: \(selector)") }
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func getMutations(_ body: [String: Any]) async -> [String: Any] {
        guard let watchId = body["watchId"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "watchId is required")
        }
        let clear = body["clear"] as? Bool ?? true
        let safeId = watchId.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(){
            var w = (window.__kelpieMutations || {})['\(safeId)'];
            if (!w) return null;
            var mutations = w.buffer.slice();
            if (\(clear)) w.buffer.length = 0;
            return {mutations: mutations, count: mutations.length, hasMore: false};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "WATCH_NOT_FOUND", message: "Watch \(watchId) not found") }
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private func stopWatching(_ body: [String: Any]) async -> [String: Any] {
        guard let watchId = body["watchId"] as? String else {
            return errorResponse(code: "MISSING_PARAM", message: "watchId is required")
        }
        let safeId = watchId.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(){
            var w = (window.__kelpieMutations || {})['\(safeId)'];
            if (!w) return null;
            w.observer.disconnect();
            var total = w.buffer.length;
            delete window.__kelpieMutations['\(safeId)'];
            return {totalMutations: total};
        })()
        """
        do {
            let result = try await context.evaluateJSReturningJSON(js)
            if result.isEmpty { return errorResponse(code: "WATCH_NOT_FOUND", message: "Watch \(watchId) not found") }
            return successResponse(result)
        } catch {
            return errorResponse(code: "EVAL_ERROR", message: error.localizedDescription)
        }
    }
}
