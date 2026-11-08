(function() {
    'use strict';
    var state = window.__m3d;
    if (!state) return;

    // Remove event listeners
    for (var i = 0; i < state.listeners.length; i++) {
        var entry = state.listeners[i];
        try { entry[0].removeEventListener(entry[1], entry[2], entry[3]); } catch(e) {}
    }

    // Remove overlay, suppression style, and warning toast
    var overlay = document.getElementById('__m3d_overlay');
    if (overlay) overlay.remove();
    var suppress = document.getElementById('__m3d_suppress');
    if (suppress) suppress.remove();
    var toast = document.getElementById('__m3d_toast');
    if (toast) toast.remove();

    // Remove cross-origin iframe labels
    var labels = document.querySelectorAll('.__m3d_iframe_label');
    for (var l = 0; l < labels.length; l++) labels[l].remove();

    // Restore element styles from WeakMap
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

    // Restore html
    var htmlEl = document.documentElement;
    htmlEl.style.perspective = state.origHtmlStyles.perspective;
    htmlEl.style.perspectiveOrigin = state.origHtmlStyles.perspectiveOrigin;
    htmlEl.style.overflow = state.origHtmlStyles.overflow;

    // Restore body
    var bodyEl = document.body;
    bodyEl.style.transformStyle = state.origBodyStyles.transformStyle;
    bodyEl.style.transform = state.origBodyStyles.transform;
    bodyEl.style.overflow = state.origBodyStyles.overflow;

    // Restore scroll positions
    window.scrollTo(state.scrollX, state.scrollY);
    for (var s = 0; s < state.scrollPositions.length; s++) {
        var sp = state.scrollPositions[s];
        try {
            sp.el.scrollTop = sp.top;
            sp.el.scrollLeft = sp.left;
        } catch(e) {}
    }

    // Resume paused media
    for (var m = 0; m < state.pausedMedia.length; m++) {
        try { state.pausedMedia[m].play(); } catch(e) {}
    }

    delete window.__m3d;
})();
