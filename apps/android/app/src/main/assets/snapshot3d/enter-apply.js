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
