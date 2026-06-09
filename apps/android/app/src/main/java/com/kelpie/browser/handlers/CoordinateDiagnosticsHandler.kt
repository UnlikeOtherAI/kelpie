package com.kelpie.browser.handlers

import com.kelpie.browser.network.Router
import com.kelpie.browser.network.errorResponse
import com.kelpie.browser.network.successResponse
import org.json.JSONObject

class CoordinateDiagnosticsHandler(
    private val ctx: HandlerContext,
) {
    fun register(router: Router) {
        router.register("coordinate-diagnostics") { coordinateDiagnostics(it) }
    }

    private suspend fun coordinateDiagnostics(body: Map<String, Any?>): Map<String, Any?> {
        val format =
            validScreenshotFormat(body["screenshotFormat"])
                ?: return errorResponse("INVALID_PARAMS", "screenshotFormat must be 'png' or 'jpeg'")
        val resolution =
            ScreenshotResolution.parse(body["screenshotResolution"] ?: "viewport")
                ?: return errorResponse("INVALID_PARAMS", "screenshotResolution must be 'native' or 'viewport'")

        return try {
            val result =
                ctx.evaluateJSReturningJSON(
                    coordinateDiagnosticsScript(JSONObject(body).toString()),
                )
            val payload = result.toMutableMap()
            val error = payload["error"] as? Map<*, *>
            if (error != null) {
                return errorResponse(
                    error["code"] as? String ?: "EVAL_ERROR",
                    error["message"] as? String ?: "Coordinate diagnostics failed",
                )
            }
            if (body["captureScreenshot"] as? Boolean == true) {
                val screenshot =
                    ctx.captureScreenshotPayload(format, 80, resolution)
                        ?: return errorResponse("SCREENSHOT_FAILED", "Failed to capture screenshot")
                payload["screenshot"] = screenshot
            }
            successResponse(payload)
        } catch (e: Exception) {
            errorResponse("EVAL_ERROR", e.message ?: "Unknown error")
        }
    }

    private fun validScreenshotFormat(raw: Any?): String? {
        if (raw == null) return "png"
        val value = raw as? String ?: return null
        return if (value == "png" || value == "jpeg") value else null
    }
}

fun coordinateDiagnosticsScript(configJSON: String): String =
    """
    (function() {
        var config = $configJSON;
        var allEvents = [];
        var listeners = [];
        var maxEvents = 200;

        function fail(code, message) {
            return {error: {code: code, message: message}};
        }

        function rectJSON(rect) {
            return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
        }

        function elementInfo(node) {
            if (!node || node.nodeType !== 1) return null;
            var rect = typeof node.getBoundingClientRect === 'function'
                ? node.getBoundingClientRect()
                : {x: 0, y: 0, width: 0, height: 0};
            return {
                tag: node.tagName ? node.tagName.toLowerCase() : '',
                id: node.id || undefined,
                text: ((node.innerText || node.textContent || node.value || node.placeholder || '') + '').trim().substring(0, 100),
                classes: node.classList ? Array.from(node.classList).slice(0, 12) : [],
                rect: rectJSON(rect),
                visible: rect.width > 0 && rect.height > 0
            };
        }

        function viewport() {
            var visual = window.visualViewport ? {
                offsetLeft: window.visualViewport.offsetLeft || 0,
                offsetTop: window.visualViewport.offsetTop || 0,
                pageLeft: window.visualViewport.pageLeft || window.scrollX || 0,
                pageTop: window.visualViewport.pageTop || window.scrollY || 0,
                width: window.visualViewport.width || window.innerWidth || 0,
                height: window.visualViewport.height || window.innerHeight || 0,
                scale: window.visualViewport.scale || 1
            } : null;
            return {
                width: window.innerWidth || 0,
                height: window.innerHeight || 0,
                scrollX: window.scrollX || 0,
                scrollY: window.scrollY || 0,
                devicePixelRatio: window.devicePixelRatio || 1,
                visualViewport: visual
            };
        }

        function pageCoordinates(x, y) {
            var visual = window.visualViewport;
            return {
                pageX: x + (visual ? visual.pageLeft : window.scrollX || 0),
                pageY: y + (visual ? visual.pageTop : window.scrollY || 0)
            };
        }

        function matchesExpected(target, selector) {
            if (!selector) return undefined;
            try {
                var expected = document.querySelector(selector);
                if (!target || !expected) return false;
                return target.matches(selector) || expected.contains(target) || target.contains(expected);
            } catch (error) {
                var invalid = new Error('Invalid expectedSelector: ' + selector);
                invalid.code = 'INVALID_PARAMS';
                throw invalid;
            }
        }

        function samplePoint(point) {
            var x = Number(point.x);
            var y = Number(point.y);
            if (!Number.isFinite(x) || !Number.isFinite(y)) {
                var bad = new Error('Point coordinates must be finite numbers');
                bad.code = 'INVALID_PARAMS';
                throw bad;
            }
            var target = document.elementFromPoint(x, y);
            var page = pageCoordinates(x, y);
            var sample = {
                label: point.label || undefined,
                x: x,
                y: y,
                pageX: page.pageX,
                pageY: page.pageY,
                elementFromPoint: elementInfo(target),
                elementsFromPoint: (document.elementsFromPoint ? document.elementsFromPoint(x, y) : [])
                    .slice(0, 8)
                    .map(elementInfo)
                    .filter(Boolean)
            };
            if (point.expectedSelector) {
                sample.expectedSelector = point.expectedSelector;
                sample.matchesExpected = matchesExpected(target, point.expectedSelector);
            }
            return sample;
        }

        function safeValue(value) {
            if (value === undefined) return null;
            if (value === null) return null;
            if (value && value.nodeType === 1) return elementInfo(value);
            if (typeof value !== 'object') return value;
            try { return JSON.parse(JSON.stringify(value)); } catch (error) { return String(value); }
        }

        function evaluateExpression(source) {
            if (!source) return null;
            return safeValue((0, eval)(source));
        }

        function recordEvent(event) {
            if (allEvents.length >= maxEvents) return;
            var record = {
                type: event.type,
                target: elementInfo(event.target),
                timeStamp: event.timeStamp
            };
            if (typeof event.clientX === 'number') record.clientX = event.clientX;
            if (typeof event.clientY === 'number') record.clientY = event.clientY;
            if (typeof event.pageX === 'number') record.pageX = event.pageX;
            if (typeof event.pageY === 'number') record.pageY = event.pageY;
            allEvents.push(record);
        }

        function installListeners() {
            ['pointerdown', 'pointermove', 'pointerup', 'mousedown', 'mousemove', 'mouseup', 'click', 'touchstart', 'touchmove', 'touchend', 'wheel'].forEach(function(type) {
                document.addEventListener(type, recordEvent, true);
                listeners.push([document, type, recordEvent]);
            });
            window.addEventListener('scroll', recordEvent, true);
            listeners.push([window, 'scroll', recordEvent]);
        }

        function removeListeners() {
            listeners.forEach(function(item) {
                item[0].removeEventListener(item[1], item[2], true);
            });
            listeners = [];
        }

        function addMarker(point, label) {
            if (!config.captureScreenshot) return;
            var root = document.getElementById('__kelpie_coordinate_diagnostics');
            if (!root) {
                root = document.createElement('div');
                root.id = '__kelpie_coordinate_diagnostics';
                root.style.cssText = 'position:fixed;left:0;top:0;width:100%;height:100%;pointer-events:none;z-index:2147483647;';
                document.body.appendChild(root);
                setTimeout(function() { root.remove(); }, 5000);
            }
            var marker = document.createElement('div');
            marker.style.cssText = 'position:fixed;left:' + point.x + 'px;top:' + point.y + 'px;width:28px;height:28px;margin-left:-14px;margin-top:-14px;border:2px solid #ef4444;border-radius:50%;box-shadow:0 0 0 2px rgba(255,255,255,0.8);';
            var text = document.createElement('div');
            text.textContent = label || '';
            text.style.cssText = 'position:fixed;left:' + (point.x + 16) + 'px;top:' + (point.y - 14) + 'px;background:rgba(0,0,0,0.72);color:white;padding:2px 5px;border-radius:4px;font:11px -apple-system,system-ui,sans-serif;white-space:nowrap;';
            root.appendChild(marker);
            if (label) root.appendChild(text);
        }

        function dispatchPointer(target, type, x, y, button, buttons) {
            if (typeof window.PointerEvent !== 'function') return;
            target.dispatchEvent(new PointerEvent(type, {
                bubbles: true, cancelable: true, composed: true,
                clientX: x, clientY: y, screenX: x, screenY: y,
                pointerId: 1, pointerType: 'touch', isPrimary: true,
                button: button, buttons: buttons
            }));
        }

        function dispatchMouse(target, type, x, y, button, buttons) {
            target.dispatchEvent(new MouseEvent(type, {
                bubbles: true, cancelable: true, composed: true,
                clientX: x, clientY: y, screenX: x, screenY: y,
                detail: type === 'click' ? 1 : 0,
                button: button, buttons: buttons
            }));
        }

        function dispatchTap(action) {
            var x = Number(action.x);
            var y = Number(action.y);
            var target = document.elementFromPoint(x, y) || document.body || document.documentElement;
            addMarker({x: x, y: y}, action.label || 'tap');
            if (target && typeof target.focus === 'function') {
                try { target.focus({preventScroll: true}); } catch (error) { try { target.focus(); } catch (_) {} }
            }
            dispatchPointer(target, 'pointerdown', x, y, 0, 1);
            dispatchMouse(target, 'mousedown', x, y, 0, 1);
            dispatchPointer(target, 'pointerup', x, y, 0, 0);
            dispatchMouse(target, 'mouseup', x, y, 0, 0);
            if (target && typeof target.click === 'function') {
                target.click();
            } else {
                dispatchMouse(target, 'click', x, y, 0, 0);
            }
            return target;
        }

        function dispatchSwipe(action) {
            var from = action.from || {};
            var to = action.to || {};
            var steps = Math.max(Number(action.steps || 12), 2);
            var lastTarget = null;
            addMarker({x: Number(from.x), y: Number(from.y)}, action.label || 'swipe-from');
            addMarker({x: Number(to.x), y: Number(to.y)}, action.label ? action.label + '-to' : 'swipe-to');
            for (var step = 0; step <= steps; step += 1) {
                var progress = step / steps;
                var x = Number(from.x) + (Number(to.x) - Number(from.x)) * progress;
                var y = Number(from.y) + (Number(to.y) - Number(from.y)) * progress;
                var type = step === 0 ? 'pointerdown' : (step === steps ? 'pointerup' : 'pointermove');
                lastTarget = document.elementFromPoint(x, y) || document.body || document.documentElement;
                dispatchPointer(lastTarget, type, x, y, 0, step === steps ? 0 : 1);
                if (typeof window.PointerEvent !== 'function') {
                    dispatchMouse(lastTarget, type === 'pointerdown' ? 'mousedown' : (type === 'pointerup' ? 'mouseup' : 'mousemove'), x, y, 0, step === steps ? 0 : 1);
                }
            }
            return lastTarget;
        }

        function runAction(action) {
            var start = allEvents.length;
            var before = null;
            var after = null;
            var input = {};
            if (action.type === 'tap') {
                before = samplePoint(action);
                dispatchTap(action);
                after = samplePoint(action);
                input = {x: after.x, y: after.y, pageX: after.pageX, pageY: after.pageY};
            } else if (action.type === 'swipe') {
                before = samplePoint(Object.assign({}, action.from || {}, {label: action.label ? action.label + '-from' : 'swipe-from'}));
                dispatchSwipe(action);
                after = samplePoint(Object.assign({}, action.to || {}, {label: action.label ? action.label + '-to' : 'swipe-to', expectedSelector: action.expectedSelector}));
                input = {from: action.from || null, to: action.to || null, durationMs: action.durationMs || 0, steps: action.steps || 12};
            } else if (action.type === 'scroll') {
                input = {deltaX: Number(action.deltaX || 0), deltaY: Number(action.deltaY || 0)};
                var center = {x: Math.max((window.innerWidth || 0) / 2, 0), y: Math.max((window.innerHeight || 0) / 2, 0), expectedSelector: action.expectedSelector};
                before = samplePoint(center);
                window.scrollBy(input.deltaX, input.deltaY);
                after = samplePoint(center);
            } else {
                var unknown = new Error('Unsupported coordinate action type: ' + action.type);
                unknown.code = 'INVALID_PARAMS';
                throw unknown;
            }
            var events = allEvents.slice(start);
            var eventMatches = action.expectedSelector
                ? events.some(function(event) { return matchesExpected(event.target && document.elementFromPoint(event.clientX || 0, event.clientY || 0), action.expectedSelector); })
                : undefined;
            var matches = action.expectedSelector ? !!((after && after.matchesExpected) || eventMatches) : undefined;
            return {
                type: action.type,
                label: action.label || undefined,
                accepted: true,
                input: input,
                before: before,
                after: after,
                events: events,
                expectedSelector: action.expectedSelector || undefined,
                matchesExpected: matches
            };
        }

        function classify(points, actions) {
            var checks = [];
            points.forEach(function(point) {
                if (point.matchesExpected !== undefined) checks.push(point.matchesExpected);
            });
            actions.forEach(function(action) {
                if (action.matchesExpected !== undefined) checks.push(action.matchesExpected);
            });
            if (!checks.length) return {status: 'needs-review', reason: 'No expectedSelector was supplied'};
            if (checks.every(Boolean)) return {status: 'pass', reason: 'All expected selectors matched'};
            return {status: 'fail', reason: 'At least one expected selector did not match'};
        }

        try {
            var setupResult = evaluateExpression(config.setupExpression);
            installListeners();
            var points = (Array.isArray(config.points) ? config.points : []).map(function(point) {
                addMarker(point, point.label || 'sample');
                return samplePoint(point);
            });
            var actions = (Array.isArray(config.actions) ? config.actions : []).map(runAction);
            var exportResult = evaluateExpression(config.exportExpression);
            return {
                coordinateSpace: 'viewport-css-pixels',
                inputSource: 'page-synthesized',
                inputCapabilities: {trustedNativeInput: false, availableInputSources: ['page-synthesized']},
                viewport: viewport(),
                setupResult: setupResult,
                points: points,
                actions: actions,
                eventLog: allEvents,
                exportResult: exportResult,
                classification: classify(points, actions)
            };
        } catch (error) {
            return fail(error.code || 'EVAL_ERROR', error.message || String(error));
        } finally {
            removeListeners();
        }
    })()
    """.trimIndent()
