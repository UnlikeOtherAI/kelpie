
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
