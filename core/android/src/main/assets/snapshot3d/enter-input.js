    addListener(inputCapture, 'mousedown', function(e) {
        if (state.mode === 'inspect') { highlightAt(e.clientX, e.clientY); return; }
        isDragging = true;
        lastX = e.clientX;
        lastY = e.clientY;
        updateCursor();
        e.preventDefault();
    }, false);

    addListener(inputCapture, 'touchstart', function(e) {
        if (e.touches.length === 1 && state.mode === 'inspect') {
            highlightAt(e.touches[0].clientX, e.touches[0].clientY);
            e.preventDefault();
            return;
        }
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
            dragScene(e.clientX, e.clientY);
            return;
        }

        if (!isToolEvent(e)) highlightAt(e.clientX, e.clientY);
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

        dragScene(touch.clientX, touch.clientY);
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
        if (state.mode === 'pan' && !e.ctrlKey) {
            panX -= e.shiftKey ? e.deltaY : e.deltaX;
            panY -= e.shiftKey ? 0 : e.deltaY;
            applyTransform();
        } else if (state.mode === 'scroll' && !e.ctrlKey) {
            scrollScene(-e.deltaY);
        } else {
            zoomBy(e.deltaY * -0.002);
        }
    }, { passive: false });

    // ---- Phase 5: Keyboard controls ----

    addListener(document, 'keydown', function(e) {
        if (isToolEvent(e) && e.key !== 'Escape') return;
        if (e.key === 'Escape') {
            exitViaMessage();
        } else if (e.key === '=' || e.key === '+') {
            state.spacing = Math.min(80, state.spacing + 5);
            reapplyDepths();
        } else if (e.key === '-') {
            state.spacing = Math.max(0, state.spacing - 5);
            reapplyDepths();
        } else if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].indexOf(e.key) >= 0) {
            panX += e.key === 'ArrowLeft' ? 48 : e.key === 'ArrowRight' ? -48 : 0;
            panY += e.key === 'ArrowUp' ? 48 : e.key === 'ArrowDown' ? -48 : 0;
            applyTransform();
        } else if (e.key === 'r' || e.key === 'R') {
            resetView();
        }
        e.preventDefault();
        e.stopPropagation();
    }, true);
})();
