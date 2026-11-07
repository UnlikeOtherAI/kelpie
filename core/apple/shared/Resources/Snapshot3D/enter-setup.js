(function() {
    'use strict';
    // Guard: clean up any stale partial state first
    if (window.__m3d) {
        // Previous enter failed or wasn't cleaned up — run exit
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

    // ---- State object ----
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

    // ---- Phase 0: Save scroll positions for custom scroll containers ----
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

    // ---- Phase 0b: Pause media ----
    var media = document.querySelectorAll('video, audio');
    for (var m = 0; m < media.length; m++) {
        if (!media[m].paused) {
            media[m].pause();
            state.pausedMedia.push(media[m]);
        }
    }

    // ---- Phase 0c: Inject suppression stylesheet ----
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

