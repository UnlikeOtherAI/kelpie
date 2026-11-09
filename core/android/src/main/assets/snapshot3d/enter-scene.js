    // ---- Phase 4: Input handling ----

    var rotX = 15, rotY = -25, rotZ = 0, scale = 0.85;
    var panX = 0, panY = 0;
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
        bodyEl.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + scale + ') rotateX(' + rotX + 'deg) rotateY(' + rotY + 'deg) rotateZ(' + rotZ + 'deg)';
        if (state.updateTools) state.updateTools();
    }
    applyTransform();

    function clampScale(nextScale) {
        return Math.max(0.15, Math.min(2.5, nextScale));
    }

    function resetView() {
        rotX = 15;
        rotY = -25;
        rotZ = 0;
        panX = 0;
        panY = 0;
        scale = 0.85;
        applyTransform();
    }

    function updateCursor() {
        inputCapture.style.cursor = isDragging ? 'grabbing' : (state.mode === 'scroll' ? 'ns-resize' : state.mode === 'inspect' ? 'crosshair' : 'grab');
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
            if (!el.hasAttribute('data-m3d-depth')) continue;
            var d = parseInt(el.getAttribute('data-m3d-depth')) || 0;
            el.style.transform = 'translateZ(' + (d * state.spacing) + 'px)';
        }
        applyTransform();
    }

    state.setMode = function(nextMode) {
        state.mode = ['rotate', 'pan', 'scroll', 'inspect'].indexOf(nextMode) >= 0 ? nextMode : 'rotate';
        updateCursor();
        if (state.updateTools) state.updateTools();
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

    function dragScene(x, y) {
        var dx = x - lastX, dy = y - lastY;
        if (state.mode === 'scroll') scrollScene(dy);
        else if (state.mode === 'pan') { panX += dx; panY += dy; }
        else if (state.mode === 'rotate') {
            rotY += dx * 0.4;
            rotX = Math.max(-90, Math.min(90, rotX - dy * 0.4));
        }
        lastX = x;
        lastY = y;
        applyTransform();
    }

    function isToolEvent(e) {
        return e.composedPath().indexOf(toolsHost) >= 0;
    }
