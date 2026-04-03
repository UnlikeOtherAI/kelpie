package com.mollotov.browser.handlers

object Snapshot3DBridge {
    const val ENTER_SCRIPT = """
    (function() {
        'use strict';
        if (window.__m3d) {
            var staleState = window.__m3d;
            for (var i = 0; i < staleState.listeners.length; i++) {
                var listener = staleState.listeners[i];
                try { listener[0].removeEventListener(listener[1], listener[2], listener[3]); } catch(e) {}
            }
            var staleOverlay = document.getElementById('__m3d_overlay');
            if (staleOverlay) staleOverlay.remove();
            var staleSuppress = document.getElementById('__m3d_suppress');
            if (staleSuppress) staleSuppress.remove();

            for (var j = 0; j < staleState.modifiedElements.length; j++) {
                var staleEl = staleState.modifiedElements[j];
                var staleOrig = staleState.origStyles.get(staleEl);
                if (staleOrig) {
                    var staleProps = Object.keys(staleOrig);
                    for (var k = 0; k < staleProps.length; k++) {
                        try { staleEl.style[staleProps[k]] = staleOrig[staleProps[k]]; } catch(e) {}
                    }
                }
                staleEl.removeAttribute('data-m3d-depth');
            }

            var staleHtml = document.documentElement;
            staleHtml.style.perspective = staleState.origHtmlStyles.perspective;
            staleHtml.style.perspectiveOrigin = staleState.origHtmlStyles.perspectiveOrigin;
            staleHtml.style.overflow = staleState.origHtmlStyles.overflow;

            var staleBody = document.body;
            staleBody.style.transformStyle = staleState.origBodyStyles.transformStyle;
            staleBody.style.transform = staleState.origBodyStyles.transform;
            staleBody.style.overflow = staleState.origBodyStyles.overflow;

            window.scrollTo(staleState.scrollX, staleState.scrollY);
            for (var s = 0; s < staleState.scrollPositions.length; s++) {
                var staleScroll = staleState.scrollPositions[s];
                try {
                    staleScroll.el.scrollTop = staleScroll.top;
                    staleScroll.el.scrollLeft = staleScroll.left;
                } catch(e) {}
            }

            for (var m = 0; m < staleState.pausedMedia.length; m++) {
                try { staleState.pausedMedia[m].play(); } catch(e) {}
            }

            delete window.__m3d;
        }

        var LAYER_SPACING = 30;
        var MAX_ELEMENTS = 5000;
        var MIN_SIZE = 4;
        var SKIP_TAGS = {SCRIPT:1, STYLE:1, META:1, LINK:1, HEAD:1, BR:1, WBR:1, NOSCRIPT:1};

        var state = {
            origStyles: new WeakMap(),
            origHtmlStyles: {},
            origBodyStyles: {},
            modifiedElements: [],
            scrollPositions: [],
            pausedMedia: [],
            listeners: [],
            mode: 'rotate',
            spacing: LAYER_SPACING,
            scrollX: window.scrollX,
            scrollY: window.scrollY
        };
        window.__m3d = state;

        var allEls = document.body.querySelectorAll('*');
        for (var s = 0; s < allEls.length; s++) {
            var se = allEls[s];
            if (se.scrollTop > 0 || se.scrollLeft > 0) {
                state.scrollPositions.push({
                    el: se,
                    top: se.scrollTop,
                    left: se.scrollLeft
                });
            }
        }

        var media = document.querySelectorAll('video, audio');
        for (var m = 0; m < media.length; m++) {
            if (!media[m].paused) {
                media[m].pause();
                state.pausedMedia.push(media[m]);
            }
        }

        var suppressStyle = document.createElement('style');
        suppressStyle.id = '__m3d_suppress';
        suppressStyle.textContent = [
            '*, *::before, *::after {',
            '  animation-play-state: paused !important;',
            '  transition-duration: 0s !important;',
            '  transition-delay: 0s !important;',
            '}'
        ].join('\n');
        document.head.appendChild(suppressStyle);

        var OVERRIDE_PROPS = [
            'transform', 'transformStyle', 'overflow', 'outline',
            'outlineOffset', 'opacity', 'filter', 'clipPath',
            'mask', 'webkitMask', 'mixBlendMode', 'isolation',
            'contain', 'contentVisibility', 'backdropFilter',
            'webkitBackdropFilter', 'position', 'background'
        ];

        function getDepth(el) {
            var d = 0;
            var p = el.parentElement;
            while (p && p !== document.documentElement) {
                d++;
                p = p.parentElement;
            }
            return d;
        }

        function shouldProcess(el) {
            if (!el || !el.tagName) return false;
            if (SKIP_TAGS[el.tagName]) return false;
            var rect = el.getBoundingClientRect();
            if (rect.width < MIN_SIZE && rect.height < MIN_SIZE) return false;
            var cs = window.getComputedStyle(el);
            if (cs.display === 'none' || cs.visibility === 'hidden') return false;
            return true;
        }

        function isInsideSVG(el) {
            var p = el.parentElement;
            while (p) {
                if (p.tagName === 'svg' || p.tagName === 'SVG') return true;
                p = p.parentElement;
            }
            return false;
        }

        function isLeafPlane(el) {
            var tag = el.tagName;
            if (tag === 'CANVAS' || tag === 'VIDEO' || tag === 'AUDIO') return true;
            if (tag === 'svg' || tag === 'SVG') return true;
            if (tag === 'IFRAME') return true;
            return false;
        }

        var collected = [];

        function collectElements(root, baseDepth) {
            var els = root.querySelectorAll('*');
            for (var i = 0; i < els.length && collected.length < MAX_ELEMENTS; i++) {
                var el = els[i];
                if (!shouldProcess(el)) continue;
                if (isInsideSVG(el) && el.tagName !== 'svg' && el.tagName !== 'SVG') continue;

                var depth = getDepth(el) + baseDepth;
                var cs = window.getComputedStyle(el);
                var pos = cs.position;
                var isCrossOriginIframe = false;
                if (el.tagName === 'IFRAME') {
                    try { var _d = el.contentDocument; } catch(e) { isCrossOriginIframe = true; }
                }
                collected.push({ el: el, depth: depth, isLeaf: isLeafPlane(el), position: pos, isCrossOriginIframe: isCrossOriginIframe, hasProcessedChild: false });

                if (el.shadowRoot && collected.length < MAX_ELEMENTS) {
                    collectElements(el.shadowRoot, depth);
                }

                if (el.tagName === 'IFRAME') {
                    try {
                        var idoc = el.contentDocument;
                        if (idoc && idoc.body && collected.length < MAX_ELEMENTS) {
                            collectElements(idoc.body, depth);
                        }
                    } catch(e) {}
                }
            }
        }

        collectElements(document.body, 0);

        if (collected.length >= MAX_ELEMENTS) {
            var toast = document.createElement('div');
            toast.id = '__m3d_toast';
            toast.textContent = 'Page has too many elements for 3D inspection. Showing top ' + MAX_ELEMENTS + '.';
            toast.style.cssText = [
                'position: fixed', 'top: 16px', 'left: 50%', 'transform: translateX(-50%)',
                'padding: 10px 20px', 'border-radius: 10px',
                'background: rgba(200, 80, 0, 0.9)', 'color: #fff',
                'font: 600 13px/1.4 -apple-system, system-ui, sans-serif',
                'pointer-events: none', 'z-index: 2147483647',
                'backdrop-filter: blur(8px)', '-webkit-backdrop-filter: blur(8px)',
                'transition: opacity 0.3s'
            ].join(';');
            document.documentElement.appendChild(toast);
            setTimeout(function() { toast.style.opacity = '0'; setTimeout(function() { toast.remove(); }, 300); }, 5000);
        }

        for (var a = 0; a < collected.length; a++) {
            var ancestor = collected[a].el.parentElement;
            while (ancestor && ancestor !== document.documentElement) {
                var found = false;
                for (var b = 0; b < collected.length; b++) {
                    if (collected[b].el === ancestor) { collected[b].hasProcessedChild = true; found = true; break; }
                }
                if (found) break;
                ancestor = ancestor.parentElement;
            }
        }

        for (var r = 0; r < collected.length; r++) {
            var entry = collected[r];
            var orig = {};
            for (var p = 0; p < OVERRIDE_PROPS.length; p++) {
                orig[OVERRIDE_PROPS[p]] = entry.el.style[OVERRIDE_PROPS[p]] || '';
            }
            state.origStyles.set(entry.el, orig);
        }

        var htmlEl = document.documentElement;
        var bodyEl = document.body;
        state.origHtmlStyles = {
            perspective: htmlEl.style.perspective || '',
            perspectiveOrigin: htmlEl.style.perspectiveOrigin || '',
            overflow: htmlEl.style.overflow || ''
        };
        state.origBodyStyles = {
            transformStyle: bodyEl.style.transformStyle || '',
            transform: bodyEl.style.transform || '',
            overflow: bodyEl.style.overflow || ''
        };

        htmlEl.style.perspective = '3000px';
        htmlEl.style.perspectiveOrigin = '50% 30%';
        htmlEl.style.overflow = 'visible';

        bodyEl.style.transformStyle = 'preserve-3d';
        bodyEl.style.overflow = 'visible';

        for (var w = 0; w < collected.length; w++) {
            var item = collected[w];
            var el = item.el;
            var depth = item.depth;

            el.style.transformStyle = item.isLeaf ? 'flat' : 'preserve-3d';
            el.style.transform = 'translateZ(' + (depth * LAYER_SPACING) + 'px)';
            el.style.outline = '1px solid rgba(0, 150, 255, 0.25)';
            el.style.outlineOffset = '-1px';
            el.style.opacity = '1';
            el.style.filter = 'none';
            el.style.clipPath = 'none';
            el.style.mixBlendMode = 'normal';
            el.style.isolation = 'auto';
            el.style.contain = 'none';
            el.style.backdropFilter = 'none';
            try { el.style.webkitBackdropFilter = 'none'; } catch(e) {}
            try { el.style.contentVisibility = 'visible'; } catch(e) {}
            try { el.style.webkitMask = 'none'; } catch(e) {}
            try { el.style.mask = 'none'; } catch(e) {}

            if (item.hasProcessedChild) {
                el.style.overflow = 'visible';
            }

            if (item.position === 'fixed' || item.position === 'sticky') {
                el.style.position = 'absolute';
            }

            if (!item.isLeaf && el.children.length > 0) {
                var bg = window.getComputedStyle(el).backgroundColor;
                if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') {
                    el.style.background = 'rgba(200, 210, 220, 0.04)';
                }
            }

            if (item.isCrossOriginIframe) {
                var iframeSrc = el.getAttribute('src') || '';
                var domain = '';
                try { domain = new URL(iframeSrc, window.location.href).hostname; } catch(e) { domain = iframeSrc; }
                var label = document.createElement('div');
                label.className = '__m3d_iframe_label';
                label.textContent = 'iframe: ' + (domain || 'cross-origin');
                label.style.cssText = 'position:absolute;top:0;left:0;padding:2px 6px;background:rgba(0,0,0,0.7);color:#fff;font:10px/1.2 -apple-system,system-ui,sans-serif;pointer-events:none;z-index:2147483647;border-radius:0 0 4px 0;';
                el.parentElement.insertBefore(label, el.nextSibling);
                state.modifiedElements.push(label);
            }

            el.setAttribute('data-m3d-depth', String(depth));
            state.modifiedElements.push(el);
        }

        var overlay = document.createElement('div');
        overlay.id = '__m3d_overlay';
        overlay.style.cssText = [
            'position: fixed', 'top: 0', 'left: 0',
            'width: 100vw', 'height: 100vh',
            'z-index: 2147483647',
            'pointer-events: none',
            'transform: none'
        ].join(';');
        document.documentElement.appendChild(overlay);

        var inputCapture = document.createElement('div');
        inputCapture.id = '__m3d_input';
        inputCapture.style.cssText = [
            'position: absolute', 'top: 0', 'left: 0',
            'width: 100%', 'height: 100%',
            'pointer-events: auto', 'cursor: grab'
        ].join(';');
        overlay.appendChild(inputCapture);

        var infoPanel = document.createElement('div');
        infoPanel.id = '__m3d_info';
        infoPanel.style.cssText = [
            'position: absolute', 'bottom: 16px', 'left: 16px',
            'padding: 8px 14px', 'border-radius: 10px',
            'background: rgba(0,0,0,0.85)', 'color: #fff',
            'font: 12px/1.4 SF Mono, ui-monospace, monospace',
            'pointer-events: none', 'opacity: 0',
            'border: 1px solid rgba(255,255,255,0.2)',
            'backdrop-filter: blur(8px)', '-webkit-backdrop-filter: blur(8px)',
            'transition: opacity 0.15s',
            'max-width: 400px', 'white-space: nowrap',
            'overflow: hidden', 'text-overflow: ellipsis'
        ].join(';');
        overlay.appendChild(infoPanel);

        var rotX = 15, rotY = -25, scale = 0.85;
        var isDragging = false, lastX = 0, lastY = 0;
        var activeTouchId = null;
        var multiTouchActive = false;
        var lastPinchDistance = 0;
        var lastMultiCenterY = 0;
        var multiTouchMoved = false;
        var multiTouchStartTime = 0;
        var multiTouchStartDistance = 0;
        var multiTouchStartCenterY = 0;
        var hoveredEl = null;

        function applyTransform() {
            bodyEl.style.transform = 'scale(' + scale + ') rotateX(' + rotX + 'deg) rotateY(' + rotY + 'deg)';
        }
        applyTransform();

        function clampScale(nextScale) {
            return Math.max(0.15, Math.min(2.5, nextScale));
        }

        function resetView() {
            rotX = 15;
            rotY = -25;
            scale = 0.85;
            applyTransform();
        }

        function updateCursor() {
            inputCapture.style.cursor = isDragging ? 'grabbing' : (state.mode === 'scroll' ? 'ns-resize' : 'grab');
        }

        function touchDistance(a, b) {
            var dx = a.clientX - b.clientX;
            var dy = a.clientY - b.clientY;
            return Math.sqrt(dx * dx + dy * dy);
        }

        function touchCenterY(a, b) {
            return (a.clientY + b.clientY) / 2;
        }

        function scrollScene(deltaY) {
            if (!deltaY) return;
            window.scrollBy(0, -deltaY);
            state.scrollX = window.scrollX;
            state.scrollY = window.scrollY;
        }

        function zoomBy(delta) {
            if (!delta) return scale;
            scale = clampScale(scale + delta);
            applyTransform();
            return scale;
        }

        function beginSingleTouchDrag(touch) {
            if (!touch) return;
            multiTouchActive = false;
            activeTouchId = touch.identifier;
            isDragging = true;
            lastX = touch.clientX;
            lastY = touch.clientY;
            updateCursor();
        }

        function clearTouchState() {
            isDragging = false;
            activeTouchId = null;
            multiTouchActive = false;
            lastPinchDistance = 0;
            lastMultiCenterY = 0;
            updateCursor();
        }

        function addListener(target, type, fn, opts) {
            target.addEventListener(type, fn, opts);
            state.listeners.push([target, type, fn, opts]);
        }

        function exitViaMessage() {
            if (window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.mollotov3DSnapshot) {
                window.webkit.messageHandlers.mollotov3DSnapshot.postMessage({action: 'exit'});
            } else if (window.MollotovBridge && typeof window.MollotovBridge.on3DSnapshotEvent === 'function') {
                window.MollotovBridge.on3DSnapshotEvent(JSON.stringify({action: 'exit'}));
            } else {
                console.log('__mollotov_3d_exit__');
            }
        }

        function reapplyDepths() {
            for (var i = 0; i < state.modifiedElements.length; i++) {
                var el = state.modifiedElements[i];
                var d = parseInt(el.getAttribute('data-m3d-depth')) || 0;
                el.style.transform = 'translateZ(' + (d * state.spacing) + 'px)';
            }
            applyTransform();
        }

        state.setMode = function(nextMode) {
            state.mode = nextMode === 'scroll' ? 'scroll' : 'rotate';
            updateCursor();
            return state.mode;
        };
        state.getMode = function() {
            return state.mode;
        };
        state.zoomBy = function(delta) {
            return zoomBy(delta);
        };
        state.resetView = function() {
            resetView();
            return true;
        };
        state.exit = function() {
            exitViaMessage();
            return true;
        };
        state.reapplyDepths = function() {
            reapplyDepths();
            return state.spacing;
        };

        addListener(inputCapture, 'mousedown', function(e) {
            isDragging = true;
            lastX = e.clientX;
            lastY = e.clientY;
            updateCursor();
            e.preventDefault();
        }, false);

        addListener(inputCapture, 'touchstart', function(e) {
            if (e.touches.length === 1) {
                beginSingleTouchDrag(e.touches[0]);
            } else if (e.touches.length === 2) {
                var firstTouch = e.touches[0];
                var secondTouch = e.touches[1];
                isDragging = false;
                activeTouchId = null;
                multiTouchActive = true;
                multiTouchMoved = false;
                multiTouchStartTime = Date.now();
                multiTouchStartDistance = touchDistance(firstTouch, secondTouch);
                lastPinchDistance = multiTouchStartDistance;
                multiTouchStartCenterY = touchCenterY(firstTouch, secondTouch);
                lastMultiCenterY = multiTouchStartCenterY;
            } else {
                isDragging = false;
                activeTouchId = null;
                multiTouchActive = false;
                return;
            }
            e.preventDefault();
        }, { passive: false });

        addListener(document, 'mousemove', function(e) {
            if (isDragging) {
                if (state.mode === 'scroll') {
                    scrollScene(e.clientY - lastY);
                } else {
                    rotY += (e.clientX - lastX) * 0.4;
                    rotX -= (e.clientY - lastY) * 0.4;
                    rotX = Math.max(-90, Math.min(90, rotX));
                }
                lastX = e.clientX;
                lastY = e.clientY;
                applyTransform();
                return;
            }

            overlay.style.display = 'none';
            var target = document.elementFromPoint(e.clientX, e.clientY);
            overlay.style.display = '';

            if (target === hoveredEl) return;

            if (hoveredEl && state.origStyles.has(hoveredEl)) {
                hoveredEl.style.outline = '1px solid rgba(0, 150, 255, 0.25)';
            }
            hoveredEl = target;

            if (hoveredEl && state.origStyles.has(hoveredEl)) {
                hoveredEl.style.outline = '2px solid rgba(0, 150, 255, 0.8)';

                var tag = hoveredEl.tagName.toLowerCase();
                var id = hoveredEl.id ? '#' + hoveredEl.id : '';
                var cls = hoveredEl.classList && hoveredEl.classList.length
                    ? '.' + Array.from(hoveredEl.classList).join('.') : '';
                var depthAttr = hoveredEl.getAttribute('data-m3d-depth') || '?';

                var rect = hoveredEl.getBoundingClientRect();
                var dim = Math.round(rect.width) + '\u00D7' + Math.round(rect.height);
                var cs = window.getComputedStyle(hoveredEl);
                var pos = cs.position;
                var zIdx = cs.zIndex;
                var meta = pos !== 'static' ? ' pos:' + pos : '';
                meta += zIdx !== 'auto' ? ' z:' + zIdx : '';

                var createsCtx = false;
                if (pos !== 'static' && zIdx !== 'auto') createsCtx = true;
                else if (cs.opacity !== '1') createsCtx = true;
                else if (cs.transform && cs.transform !== 'none') createsCtx = true;
                else if (cs.filter && cs.filter !== 'none') createsCtx = true;
                else if (cs.isolation === 'isolate') createsCtx = true;
                else if (cs.mixBlendMode && cs.mixBlendMode !== 'normal') createsCtx = true;
                else if (cs.contain === 'layout' || cs.contain === 'paint' || cs.contain === 'strict' || cs.contain === 'content') createsCtx = true;
                if (createsCtx) meta += ' [stacking-ctx]';

                infoPanel.textContent = '<' + tag + id + cls + '> ' + dim + ' depth:' + depthAttr + meta;
                infoPanel.style.opacity = '1';
            } else {
                infoPanel.style.opacity = '0';
            }
        }, false);

        addListener(document, 'touchmove', function(e) {
            if (multiTouchActive && e.touches.length === 2) {
                var firstTouch = e.touches[0];
                var secondTouch = e.touches[1];
                var distance = touchDistance(firstTouch, secondTouch);
                var centerY = touchCenterY(firstTouch, secondTouch);
                var distanceDelta = distance - lastPinchDistance;
                var centerDeltaY = centerY - lastMultiCenterY;

                if (Math.abs(distance - multiTouchStartDistance) > 4 ||
                    Math.abs(centerY - multiTouchStartCenterY) > 4) {
                    multiTouchMoved = true;
                }

                if (Math.abs(distanceDelta) > 2) {
                    scale = clampScale(scale + distanceDelta * 0.004);
                }

                if (Math.abs(centerDeltaY) > 1) {
                    scrollScene(centerDeltaY);
                }

                lastPinchDistance = distance;
                lastMultiCenterY = centerY;
                applyTransform();
                e.preventDefault();
                return;
            }

            if (multiTouchActive && e.touches.length === 1) {
                beginSingleTouchDrag(e.touches[0]);
            }

            if (!isDragging || activeTouchId === null) return;
            var touch = null;
            for (var i = 0; i < e.touches.length; i++) {
                if (e.touches[i].identifier === activeTouchId) {
                    touch = e.touches[i];
                    break;
                }
            }
            if (!touch) return;

            if (state.mode === 'scroll') {
                scrollScene(touch.clientY - lastY);
            } else {
                rotY += (touch.clientX - lastX) * 0.4;
                rotX -= (touch.clientY - lastY) * 0.4;
                rotX = Math.max(-90, Math.min(90, rotX));
            }
            lastX = touch.clientX;
            lastY = touch.clientY;
            applyTransform();
            e.preventDefault();
        }, { passive: false });

        addListener(document, 'mouseup', function() {
            if (isDragging) {
                isDragging = false;
                updateCursor();
            }
        }, false);

        addListener(document, 'touchend', function(e) {
            if (multiTouchActive) {
                if (e.touches.length === 1) {
                    var shouldReset = !multiTouchMoved && (Date.now() - multiTouchStartTime) < 250;
                    beginSingleTouchDrag(e.touches[0]);
                    if (shouldReset) {
                        resetView();
                    }
                } else if (e.touches.length === 0) {
                    clearTouchState();
                }
                return;
            }

            if (!isDragging || activeTouchId === null) return;
            for (var i = 0; i < e.changedTouches.length; i++) {
                if (e.changedTouches[i].identifier === activeTouchId) {
                    isDragging = false;
                    activeTouchId = null;
                    break;
                }
            }
        }, false);

        addListener(document, 'touchcancel', function() {
            clearTouchState();
        }, false);

        addListener(inputCapture, 'wheel', function(e) {
            e.preventDefault();
            if (state.mode === 'scroll') {
                scrollScene(-e.deltaY);
            } else {
                zoomBy(e.deltaY * -0.002);
            }
        }, { passive: false });

        addListener(document, 'keydown', function(e) {
            if (e.key === 'Escape') {
                exitViaMessage();
            } else if (e.key === '=' || e.key === '+') {
                state.spacing = Math.min(80, state.spacing + 5);
                reapplyDepths();
            } else if (e.key === '-') {
                state.spacing = Math.max(5, state.spacing - 5);
                reapplyDepths();
            } else if (e.key === 'r' || e.key === 'R') {
                resetView();
            }
            e.preventDefault();
            e.stopPropagation();
        }, true);
    })();
    """

    const val EXIT_SCRIPT = """
    (function() {
        'use strict';
        var state = window.__m3d;
        if (!state) return;

        for (var i = 0; i < state.listeners.length; i++) {
            var entry = state.listeners[i];
            try { entry[0].removeEventListener(entry[1], entry[2], entry[3]); } catch(e) {}
        }

        var overlay = document.getElementById('__m3d_overlay');
        if (overlay) overlay.remove();
        var suppress = document.getElementById('__m3d_suppress');
        if (suppress) suppress.remove();
        var toast = document.getElementById('__m3d_toast');
        if (toast) toast.remove();

        var labels = document.querySelectorAll('.__m3d_iframe_label');
        for (var l = 0; l < labels.length; l++) labels[l].remove();

        for (var j = 0; j < state.modifiedElements.length; j++) {
            var el = state.modifiedElements[j];
            var orig = state.origStyles.get(el);
            if (orig) {
                var props = Object.keys(orig);
                for (var k = 0; k < props.length; k++) {
                    try { el.style[props[k]] = orig[props[k]]; } catch(e) {}
                }
            }
            el.removeAttribute('data-m3d-depth');
        }

        var htmlEl = document.documentElement;
        htmlEl.style.perspective = state.origHtmlStyles.perspective;
        htmlEl.style.perspectiveOrigin = state.origHtmlStyles.perspectiveOrigin;
        htmlEl.style.overflow = state.origHtmlStyles.overflow;

        var bodyEl = document.body;
        bodyEl.style.transformStyle = state.origBodyStyles.transformStyle;
        bodyEl.style.transform = state.origBodyStyles.transform;
        bodyEl.style.overflow = state.origBodyStyles.overflow;

        window.scrollTo(state.scrollX, state.scrollY);
        for (var s = 0; s < state.scrollPositions.length; s++) {
            var sp = state.scrollPositions[s];
            try {
                sp.el.scrollTop = sp.top;
                sp.el.scrollLeft = sp.left;
            } catch(e) {}
        }

        for (var m = 0; m < state.pausedMedia.length; m++) {
            try { state.pausedMedia[m].play(); } catch(e) {}
        }

        delete window.__m3d;
    })();
    """

    fun setModeScript(mode: String): String = """
    (function() {
        if (!window.__m3d || typeof window.__m3d.setMode !== 'function') return null;
        return window.__m3d.setMode('${mode}');
    })();
    """

    const val RESET_VIEW_SCRIPT = """
    (function() {
        if (!window.__m3d || typeof window.__m3d.resetView !== 'function') return false;
        return window.__m3d.resetView();
    })();
    """

    fun zoomByScript(delta: Double): String = """
    (function() {
        if (!window.__m3d || typeof window.__m3d.zoomBy !== 'function') return null;
        return window.__m3d.zoomBy($delta);
    })();
    """
}
