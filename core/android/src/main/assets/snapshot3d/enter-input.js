
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
            window.webkit.messageHandlers.kelpie3DSnapshot) {
            window.webkit.messageHandlers.kelpie3DSnapshot.postMessage({action: 'exit'});
        } else if (window.KelpieBridge && typeof window.KelpieBridge.on3DSnapshotEvent === 'function') {
            window.KelpieBridge.on3DSnapshotEvent(JSON.stringify({action: 'exit'}));
        } else {
            console.log('__kelpie_3d_exit__');
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
