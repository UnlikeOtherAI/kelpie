# 3D DOM Inspector Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a 3D DOM inspection mode that explodes the page into layered depth planes, allowing click-drag rotation and scroll zoom to visually debug element stacking, overlapping layers, and invisible overlays.

**Architecture:** Inject JavaScript via `evaluateJS()` that walks the DOM tree, applies CSS 3D `translateZ()` per element based on DOM depth, and adds mouse drag (rotation) + scroll wheel (zoom) controls. A transparent input overlay captures all interaction. Controls live outside the 3D scene. Page is best-effort suppressed, not truly frozen.

**Contract:** This is a **best-effort structural inspection tool**, not a pixel-perfect frozen snapshot. Background JavaScript (timers, WebSocket handlers, workers) may still fire. CSS animations are paused. The 3D view reflects DOM depth — not true CSS paint order. Canvas, WebGL, video, cross-origin iframes, and closed shadow DOM appear as opaque leaf planes.

**Tech Stack:** JavaScript (injected), Swift (handler + UI wiring), CSS 3D transforms

**Cross-Provider Review:** Reviewed by Claude (Opus), Gemini (2.5 Pro), and Codex (GPT-5.4) on 2026-04-02. All findings incorporated below. Original reviews preserved in git history.

---

## Architecture Decisions

### Scene structure (not html/body)

Do NOT apply perspective or rotation to `<html>` or `<body>`. Instead:

```
<html>
  <body>
    ... page content (gets translateZ per element) ...
  </body>
  <div id="__m3d_scene_root">       <!-- perspective + rotation applied here -->
    <!-- wraps body visually via CSS -->
  </div>
  <div id="__m3d_overlay">          <!-- outside 3D tree entirely -->
    <div id="__m3d_close">...</div>
    <div id="__m3d_info">...</div>
    <div id="__m3d_input_capture">  <!-- transparent full-viewport, pointer-events: all -->
    </div>
  </div>
</html>
```

Wait — we cannot reparent `<body>` without breaking the page. Revised approach:

1. Apply `perspective` to `<html>` (read-only container, no transform on it)
2. Apply `transform-style: preserve-3d` and rotation to `<body>`
3. Apply `translateZ()` to individual elements inside body
4. Create `__m3d_overlay` as a direct child of `<html>`, sibling of `<body>`, with:
   - `position: fixed; top: 0; left: 0; width: 100vw; height: 100vh`
   - `z-index: 2147483647; pointer-events: none`
   - `transform: none !important` (escapes the 3D tree)
5. Inside `__m3d_overlay`: close button (`pointer-events: auto`), info panel, and a transparent input-capture div (`pointer-events: auto` when 3D is active)

The input-capture div intercepts all mouse/wheel events and drives rotation/zoom. The close button and info panel stay pinned to the viewport regardless of rotation.

### Why DOM depth only (no stacking heuristic)

CSS paint order depends on stacking contexts, which are created by dozens of CSS properties (`opacity < 1`, `transform`, `filter`, `position + z-index`, `isolation`, `contain`, `mix-blend-mode`, etc.) in a nested tree structure. Computing true paint order requires building a full stacking context tree — that's a browser-engine-level operation.

Instead: visualize **DOM depth** (tree nesting level). Show `z-index`, `position`, and whether the element creates a stacking context as metadata in the hover info panel. The user gets structural insight without a misleading fake stacking order.

### Style overrides for `preserve-3d` propagation

The CSS spec flattens `preserve-3d` through any element with these properties. ALL must be temporarily overridden:

| Property | Override to | Why |
|----------|------------|-----|
| `overflow` | `visible` (selective — see below) | Clips 3D children |
| `opacity` | `1` | Flattens preserve-3d |
| `filter` | `none` | Flattens preserve-3d |
| `clip-path` | `none` | Clips 3D children |
| `mask` / `-webkit-mask` | `none` | Clips 3D children |
| `mix-blend-mode` | `normal` | Flattens preserve-3d |
| `isolation` | `auto` | Flattens preserve-3d |
| `contain` | `none` | Flattens preserve-3d + skips rendering |
| `content-visibility` | `visible` | Skips off-screen rendering entirely |
| `-webkit-backdrop-filter` / `backdrop-filter` | `none` | WebKit-specific preserve-3d bug |

**`overflow` is selective** — don't blanket-set `visible` on everything:
- Only override `overflow` on elements that are **direct ancestors** of processed 3D children
- Skip overriding on leaf elements (no 3D children below them)
- This avoids breaking virtualized lists, text truncation, carousels, and hidden panels

### State storage: WeakMap, not data attributes

Store original styles in a `WeakMap<Element, Record<string, string>>` on `window.__m3d.origStyles`. This:
- Avoids DOM mutation (no `setAttribute` calls that wake MutationObservers)
- Has no serialization/escaping issues
- Is faster than DOM attribute read/write
- Is garbage-collected if elements are removed

Still use `data-m3d-depth` attribute for depth (needed by `reapplyDepths()` on spacing change), but that's one small attribute vs. a JSON blob of 15+ properties.

### Element processing rules

| Element type | Action |
|-------------|--------|
| `<script>`, `<style>`, `<meta>`, `<link>`, `<head>`, `<br>`, `<wbr>` | Skip entirely |
| Zero-width or zero-height `getBoundingClientRect()` | Skip |
| `display: none` or `visibility: hidden` | Skip |
| Elements inside `<svg>` | Skip — treat `<svg>` itself as leaf plane |
| `<canvas>`, `<video>`, `<audio>` | Leaf plane (gets translateZ but no recursion into children) |
| `<iframe>` (cross-origin) | Leaf plane with domain label |
| `<iframe>` (same-origin) | Recurse into `iframe.contentDocument` |
| Open shadow roots | Recurse into `element.shadowRoot` |
| Closed shadow roots | Leaf plane (inaccessible) |
| `position: fixed` / `position: sticky` | Convert to `position: absolute`, depth based on DOM position |

### Performance caps

- **Hard cap: 5,000 elements.** If the filtered element count exceeds 5,000, stop processing and show a warning toast: "Page has too many elements for 3D inspection. Showing top 5,000."
- **Two-phase processing:** Phase 1: read all computed styles and bounding rects (no writes). Phase 2: batch-write all style modifications. This avoids layout thrashing from interleaved reads/writes.
- **Skip tiny elements:** Elements with both width and height < 4px are skipped (invisible dots, tracking pixels).

### Page suppression (best-effort, not freeze)

What we CAN suppress from injected JS:
- Inject global style: `*, *::before, *::after { animation-play-state: paused !important; transition-duration: 0s !important; transition-delay: 0s !important; }`
- Pause all `<video>` and `<audio>` elements
- Capture-phase listeners on the input overlay intercept pointer/keyboard/wheel events
- Save and restore scroll positions for `window` AND all elements with `scrollTop > 0`

What we CANNOT suppress from injected JS (and don't try):
- `setInterval` / `setTimeout` / `requestAnimationFrame` callbacks
- WebSocket / EventSource message handlers
- Web Workers
- MutationObserver callbacks (minimised by using WeakMap instead of data attributes)
- Service Worker fetch events

Document this honestly.

---

### Task 1: 3D Inspector JavaScript Engine

The core JavaScript: a single IIFE injected via `evaluateJS()`, cleaned up by a second script.

**Files:**
- Create: `apps/macos/Kelpie/Handlers/Snapshot3DBridge.swift` (JS as Swift string constants)

**Step 1: Write the enter script**

The enter script structure:

```javascript
(function() {
    'use strict';
    // Guard: clean up any stale partial state first
    if (window.__m3d) {
        // Previous enter failed or wasn't cleaned up — run exit
        /* ... inline exit logic ... */
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

    // ---- Phase 1: Read pass (no writes) ----
    // Collect elements, compute depths, read styles

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

    // Collect processable elements (light DOM + open shadow roots + same-origin iframes)
    var collected = [];

    function collectElements(root, baseDepth) {
        var els = root.querySelectorAll('*');
        for (var i = 0; i < els.length && collected.length < MAX_ELEMENTS; i++) {
            var el = els[i];
            if (!shouldProcess(el)) continue;
            if (isInsideSVG(el) && el.tagName !== 'svg' && el.tagName !== 'SVG') continue;

            var depth = getDepth(el) + baseDepth;
            collected.push({ el: el, depth: depth, isLeaf: isLeafPlane(el) });

            // Recurse into open shadow roots
            if (el.shadowRoot && collected.length < MAX_ELEMENTS) {
                collectElements(el.shadowRoot, depth);
            }

            // Recurse into same-origin iframes
            if (el.tagName === 'IFRAME') {
                try {
                    var idoc = el.contentDocument;
                    if (idoc && idoc.body && collected.length < MAX_ELEMENTS) {
                        collectElements(idoc.body, depth);
                    }
                } catch(e) { /* cross-origin — skip */ }
            }
        }
    }

    collectElements(document.body, 0);

    // Read original styles for each element
    for (var r = 0; r < collected.length; r++) {
        var entry = collected[r];
        var orig = {};
        for (var p = 0; p < OVERRIDE_PROPS.length; p++) {
            orig[OVERRIDE_PROPS[p]] = entry.el.style[OVERRIDE_PROPS[p]] || '';
        }
        state.origStyles.set(entry.el, orig);
    }

    // Save html/body original inline styles
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

    // ---- Phase 2: Write pass (batch all modifications) ----

    // Apply perspective to html (not body — no transform on html)
    htmlEl.style.perspective = '3000px';
    htmlEl.style.perspectiveOrigin = '50% 30%';
    htmlEl.style.overflow = 'visible';

    // Apply preserve-3d + rotation base to body
    bodyEl.style.transformStyle = 'preserve-3d';
    bodyEl.style.overflow = 'visible';

    // Process each collected element
    for (var w = 0; w < collected.length; w++) {
        var item = collected[w];
        var el = item.el;
        var depth = item.depth;

        el.style.transformStyle = item.isLeaf ? 'flat' : 'preserve-3d';
        el.style.transform = 'translateZ(' + (depth * LAYER_SPACING) + 'px)';
        el.style.outline = '1px solid rgba(0, 150, 255, 0.25)';
        el.style.outlineOffset = '-1px';

        // Override preserve-3d flattening properties
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

        // Only override overflow on ancestors of 3D children (not leaf nodes)
        if (!item.isLeaf) {
            el.style.overflow = 'visible';
        }

        // Convert fixed/sticky to absolute
        var cs = window.getComputedStyle(el);
        if (cs.position === 'fixed' || cs.position === 'sticky') {
            el.style.position = 'absolute';
        }

        // Subtle background for transparent containers
        if (!item.isLeaf && el.children.length > 0) {
            var bg = cs.backgroundColor;
            if (!bg || bg === 'rgba(0, 0, 0, 0)' || bg === 'transparent') {
                el.style.background = 'rgba(200, 210, 220, 0.04)';
            }
        }

        el.setAttribute('data-m3d-depth', String(depth));
        state.modifiedElements.push(el);
    }

    // ---- Phase 3: Create overlay (outside 3D tree) ----

    var overlay = document.createElement('div');
    overlay.id = '__m3d_overlay';
    overlay.style.cssText = [
        'position: fixed', 'top: 0', 'left: 0',
        'width: 100vw', 'height: 100vh',
        'z-index: 2147483647',
        'pointer-events: none',
        'transform: none'
    ].join(';');
    // Append to <html> as sibling of <body> — outside the 3D tree
    document.documentElement.appendChild(overlay);

    // Input capture layer
    var inputCapture = document.createElement('div');
    inputCapture.id = '__m3d_input';
    inputCapture.style.cssText = [
        'position: absolute', 'top: 0', 'left: 0',
        'width: 100%', 'height: 100%',
        'pointer-events: auto', 'cursor: grab'
    ].join(';');
    overlay.appendChild(inputCapture);

    // Close button
    var closeBtn = document.createElement('div');
    closeBtn.id = '__m3d_close';
    closeBtn.textContent = '\u00D7 Exit 3D';
    closeBtn.style.cssText = [
        'position: absolute', 'top: 16px', 'right: 16px',
        'padding: 8px 16px', 'border-radius: 10px',
        'background: rgba(0,0,0,0.85)', 'color: #fff',
        'font: 600 13px/1 -apple-system, system-ui, sans-serif',
        'cursor: pointer', 'pointer-events: auto',
        'border: 1px solid rgba(255,255,255,0.3)',
        'backdrop-filter: blur(8px)', '-webkit-backdrop-filter: blur(8px)',
        'user-select: none'
    ].join(';');
    overlay.appendChild(closeBtn);

    // Info panel
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

    // ---- Phase 4: Input handling ----

    var rotX = 15, rotY = -25, scale = 0.85;
    var isDragging = false, lastX = 0, lastY = 0;
    var hoveredEl = null;

    function applyTransform() {
        bodyEl.style.transform = 'scale(' + scale + ') rotateX(' + rotX + 'deg) rotateY(' + rotY + 'deg)';
    }
    applyTransform();

    function addListener(target, type, fn, opts) {
        target.addEventListener(type, fn, opts);
        state.listeners.push([target, type, fn, opts]);
    }

    addListener(inputCapture, 'mousedown', function(e) {
        isDragging = true;
        lastX = e.clientX;
        lastY = e.clientY;
        inputCapture.style.cursor = 'grabbing';
        e.preventDefault();
    }, false);

    addListener(document, 'mousemove', function(e) {
        if (isDragging) {
            rotY += (e.clientX - lastX) * 0.4;
            rotX -= (e.clientY - lastY) * 0.4;
            rotX = Math.max(-90, Math.min(90, rotX));
            lastX = e.clientX;
            lastY = e.clientY;
            applyTransform();
            return;
        }

        // Hover detection (best-effort — degrades at steep angles)
        // Temporarily hide overlay to hit-test the 3D scene
        overlay.style.display = 'none';
        var target = document.elementFromPoint(e.clientX, e.clientY);
        overlay.style.display = '';

        if (target === hoveredEl) return;

        // Remove previous highlight
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

            // Show original dimensions (pre-transform)
            var origRect = state.origStyles.get(hoveredEl);
            var rect = hoveredEl.getBoundingClientRect();
            var dim = Math.round(rect.width) + '\u00D7' + Math.round(rect.height);

            // Stacking context info
            var cs = window.getComputedStyle(hoveredEl);
            var pos = cs.position;
            var zIdx = cs.zIndex;
            var meta = pos !== 'static' ? ' pos:' + pos : '';
            meta += zIdx !== 'auto' ? ' z:' + zIdx : '';

            infoPanel.textContent = '<' + tag + id + cls + '> ' + dim + ' depth:' + depthAttr + meta;
            infoPanel.style.opacity = '1';
        } else {
            infoPanel.style.opacity = '0';
        }
    }, false);

    addListener(document, 'mouseup', function() {
        if (isDragging) {
            isDragging = false;
            inputCapture.style.cursor = 'grab';
        }
    }, false);

    addListener(inputCapture, 'wheel', function(e) {
        e.preventDefault();
        scale += e.deltaY * -0.002;
        scale = Math.max(0.15, Math.min(2.5, scale));
        applyTransform();
    }, { passive: false });

    // ---- Phase 5: Keyboard controls ----

    function exitViaMessage() {
        if (window.webkit && window.webkit.messageHandlers &&
            window.webkit.messageHandlers.kelpie3DSnapshot) {
            window.webkit.messageHandlers.kelpie3DSnapshot.postMessage({action: 'exit'});
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
            rotX = 15; rotY = -25; scale = 0.85;
            applyTransform();
        }
        e.preventDefault();
        e.stopPropagation();
    }, true);

    // Close button
    addListener(closeBtn, 'click', function(e) {
        e.stopPropagation();
        exitViaMessage();
    }, false);
})();
```

**Step 2: Write the exit script**

```javascript
(function() {
    'use strict';
    var state = window.__m3d;
    if (!state) return;

    // Remove event listeners
    for (var i = 0; i < state.listeners.length; i++) {
        var entry = state.listeners[i];
        try { entry[0].removeEventListener(entry[1], entry[2], entry[3]); } catch(e) {}
    }

    // Remove overlay and suppression style
    var overlay = document.getElementById('__m3d_overlay');
    if (overlay) overlay.remove();
    var suppress = document.getElementById('__m3d_suppress');
    if (suppress) suppress.remove();

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
```

**Step 3: Create `Snapshot3DBridge.swift`**

Hold both scripts as `static let enterScript: String` and `static let exitScript: String` in an `enum Snapshot3DBridge`. Follow the same pattern as `NetworkBridge.swift`.

**Step 4: Commit**

```bash
git add apps/macos/Kelpie/Handlers/Snapshot3DBridge.swift
git commit -m "feat(macos): 3D DOM inspector JavaScript engine"
```

---

### Task 2: Feature Flag

The 3D inspector is behind a feature flag. Hidden by default, enabled via Settings toggle or environment variable for testing.

**Files:**
- Create: `apps/macos/Kelpie/Browser/FeatureFlags.swift`
- Modify: `apps/macos/Kelpie/Views/SettingsView.swift`

**Step 1: Create `FeatureFlags.swift`**

```swift
import Foundation

enum FeatureFlags {
    /// 3D DOM Inspector — experimental, behind feature flag.
    /// Enable via Settings toggle or `KELPIE_3D_INSPECTOR=1` environment variable.
    static var is3DInspectorEnabled: Bool {
        if UserDefaults.standard.bool(forKey: "enable3DInspector") {
            return true
        }
        if ProcessInfo.processInfo.environment["KELPIE_3D_INSPECTOR"] == "1" {
            return true
        }
        return false
    }
}
```

**Step 2: Add toggle to `SettingsView.swift`**

Add an "Experimental" section to the Form, between the "App" section and the "Done" button:

```swift
Section("Experimental") {
    Toggle("3D DOM Inspector", isOn: Binding(
        get: { UserDefaults.standard.bool(forKey: "enable3DInspector") },
        set: { UserDefaults.standard.set($0, forKey: "enable3DInspector") }
    ))
    Text("Explode the page into 3D layers to debug element stacking. Restart not required.")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

**Step 3: Commit**

```bash
git add apps/macos/Kelpie/Browser/FeatureFlags.swift \
    apps/macos/Kelpie/Views/SettingsView.swift
git commit -m "feat(macos): feature flag for 3D DOM inspector (settings toggle + env var)"
```

---

### Task 3: Swift Handler — Snapshot3DHandler

**Files:**
- Create: `apps/macos/Kelpie/Handlers/Snapshot3DHandler.swift`
- Modify: `apps/macos/Kelpie/Handlers/HandlerContext.swift`
- Modify: `apps/macos/Kelpie/Network/Router.swift`
- Modify: `apps/macos/Kelpie/Renderer/WKWebViewRenderer.swift`

**Step 1: Create `Snapshot3DHandler.swift`**

```swift
import Foundation

enum Snapshot3DHandler {
    static func register(on router: Router, context: HandlerContext) {
        router.register("snapshot-3d-enter") { _ in
            await enter(context: context)
        }
        router.register("snapshot-3d-exit") { _ in
            await exit(context: context)
        }
        router.register("snapshot-3d-status") { _ in
            successResponse(["active": context.isIn3DInspector])
        }
    }

    @MainActor
    private static func enter(context: HandlerContext) async -> [String: Any] {
        guard FeatureFlags.is3DInspectorEnabled else {
            return errorResponse(code: "FEATURE_DISABLED", message: "3D inspector is not enabled. Enable in Settings or set KELPIE_3D_INSPECTOR=1")
        }
        guard !context.isIn3DInspector else {
            return errorResponse(code: "ALREADY_ACTIVE", message: "3D inspector is already active")
        }
        do {
            try await context.evaluateJS(Snapshot3DBridge.enterScript)
            // Verify it actually activated
            let active = try? await context.evaluateJSReturningString("!!window.__m3d")
            if active == "true" {
                context.isIn3DInspector = true
                return successResponse()
            } else {
                return errorResponse(code: "ACTIVATION_FAILED", message: "3D inspector script did not activate")
            }
        } catch {
            return errorResponse(code: "JS_ERROR", message: error.localizedDescription)
        }
    }

    @MainActor
    private static func exit(context: HandlerContext) async -> [String: Any] {
        guard context.isIn3DInspector else { return successResponse() }
        do {
            try await context.evaluateJS(Snapshot3DBridge.exitScript)
            context.isIn3DInspector = false
            return successResponse()
        } catch {
            return errorResponse(code: "JS_ERROR", message: error.localizedDescription)
        }
    }
}
```

**Step 2: Add state and message handling to `HandlerContext.swift`**

```swift
// Property
var isIn3DInspector = false

// In handleScriptMessage(name:body:)
case "kelpie3DSnapshot":
    if body["action"] as? String == "exit" {
        Task { @MainActor in
            try? await evaluateJS(Snapshot3DBridge.exitScript)
            isIn3DInspector = false
            NotificationCenter.default.post(name: .snapshot3DExited, object: nil)
        }
    }

// In kelpieConsole handler — CEF fallback
case "kelpieConsole":
    let message = body["message"] as? String ?? ""
    if message == "__kelpie_3d_exit__" && isIn3DInspector {
        Task { @MainActor in
            try? await evaluateJS(Snapshot3DBridge.exitScript)
            isIn3DInspector = false
            NotificationCenter.default.post(name: .snapshot3DExited, object: nil)
        }
        return
    }
    consoleMessages.append(body)
    // ...
```

Add notification name:
```swift
extension Notification.Name {
    static let snapshot3DExited = Notification.Name("kelpie.snapshot3DExited")
}
```

**Step 3: Register WKWebView message handler**

In `WKWebViewRenderer.swift`, where `kelpieConsole` and `kelpieNetwork` are registered:
```swift
ucc.add(self, name: "kelpie3DSnapshot")
```

**Step 4: Register routes in `Router.swift`**

```swift
Snapshot3DHandler.register(on: router, context: context)
```

**Step 5: Auto-exit on navigation**

In the navigation delegate (`didStartNavigation` or equivalent):
```swift
if isIn3DInspector {
    isIn3DInspector = false
}
```

**Step 6: Commit**

```bash
git add apps/macos/Kelpie/Handlers/Snapshot3DHandler.swift \
    apps/macos/Kelpie/Handlers/HandlerContext.swift \
    apps/macos/Kelpie/Network/Router.swift \
    apps/macos/Kelpie/Renderer/WKWebViewRenderer.swift
git commit -m "feat(macos): 3D inspector HTTP handler and bridge message routing"
```

---

### Task 4: Floating Menu Integration (gated by feature flag)

**Files:**
- Modify: `apps/macos/Kelpie/Views/FloatingMenuView.swift`
- Modify: `apps/macos/Kelpie/Views/BrowserView.swift`

**Step 1: Add callback to `FloatingMenuView`**

Add property:
```swift
let onSnapshot3D: () -> Void
```

Add to `actions` array, **only when the feature flag is enabled**:
```swift
// In the actions computed property, conditionally include:
if FeatureFlags.is3DInspectorEnabled {
    items.append(.init(id: "snapshot-3d", icon: "cube.transparent", accessibilityID: "browser.floating-menu.cube-transparent", tooltip: "3D Inspector", action: onSnapshot3D))
}
```

Note: the `actions` property may need to change from a computed array literal to a `var` that conditionally appends. The button only appears when enabled via Settings or env var.

**Step 2: Wire in `BrowserView.swift`**

Add state:
```swift
@State private var isIn3DInspector = false
```

Wire the callback:
```swift
onSnapshot3D: {
    Task {
        if isIn3DInspector {
            try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.exitScript)
            serverState.handlerContext.isIn3DInspector = false
            isIn3DInspector = false
        } else {
            try? await serverState.handlerContext.evaluateJS(Snapshot3DBridge.enterScript)
            let active = try? await serverState.handlerContext.evaluateJSReturningString("!!window.__m3d")
            if active == "true" {
                serverState.handlerContext.isIn3DInspector = true
                isIn3DInspector = true
            }
        }
    }
}
```

Add notification listener:
```swift
.onReceive(NotificationCenter.default.publisher(for: .snapshot3DExited)) { _ in
    isIn3DInspector = false
}
```

**Step 3: Commit**

```bash
git add apps/macos/Kelpie/Views/FloatingMenuView.swift \
    apps/macos/Kelpie/Views/BrowserView.swift
git commit -m "feat(macos): 3D inspector button in floating menu"
```

---

### Task 5: Build, Launch, Verify

**Step 1:** Kill any stale Kelpie instance
```bash
pkill -f Kelpie || true
```

**Step 2:** Build the macOS app in Xcode

**Step 3:** Launch with the feature flag enabled via environment variable:
```bash
KELPIE_3D_INSPECTOR=1 open apps/macos/build/Debug/Kelpie.app
```
Or: launch normally, open Settings, toggle "3D DOM Inspector" under Experimental.

**Step 4:** Navigate to a test page (e.g., `https://news.ycombinator.com` — simple DOM, good first test)

**Step 5:** Verify the 3D button appears in the floating menu. Click it. Verify:
- Page explodes into 3D layers
- Mouse drag rotates the scene
- Scroll wheel zooms
- Close button stays pinned to viewport (not rotating)
- Info panel shows element details on hover
- `+`/`-` adjusts spacing
- `R` resets view
- Escape exits cleanly
- Page is fully restored after exit

**Step 6:** Test on a complex page (e.g., `https://github.com`). Verify:
- Shadow DOM components are visible in the 3D tree
- Performance is acceptable (no multi-second freeze)
- Fixed headers are converted to absolute positioning
- Exit restores page completely

**Step 7:** Verify the button does NOT appear when the flag is off (neither env var nor Settings toggle)

**Step 8:** Verify the HTTP endpoint returns `FEATURE_DISABLED` error when the flag is off

**Step 9: Commit** (if any fixes were needed)

---

### Task 6: Documentation

**Files:**
- Modify: `docs/functionality.md`
- Modify: `docs/api/devtools.md`

**Step 1: Add to `functionality.md`**

After "Network Inspector":

```markdown
## 3D DOM Inspector

A visual debugging tool for inspecting element stacking and layer order. Click the 3D button in the floating menu (or call the `snapshot-3d-enter` endpoint) to explode the page DOM into a 3D layered view. Every element is pushed along the Z-axis based on its depth in the DOM tree, making it easy to see which elements overlap, identify invisible overlays blocking interaction, and understand the page structure.

**Controls:**
- **Click and drag** — rotate the 3D scene to view from any angle
- **Scroll wheel** — zoom in and out
- **Hover** — highlight element and show tag, classes, dimensions, position, z-index
- **+ / -** keys — increase or decrease layer spacing
- **R** key — reset rotation and zoom to default
- **Escape** or close button — exit 3D mode and restore the page

The 3D view shows DOM depth (tree nesting), not CSS paint order. Position, z-index, and stacking context information appear in the hover info panel. User interactions are suppressed while in 3D mode, but background page logic (timers, network callbacks) may still execute. The page is restored to its original state on exit. Works with both WebKit and Chromium renderers.

**Limitations:** Canvas, WebGL, and video elements appear as opaque layers. Cross-origin iframes appear as labeled blocks. Closed shadow DOM roots are not traversable. Hover detection degrades at steep rotation angles. Pages with more than 5,000 visible elements are capped with a warning.

API: `snapshot-3d-enter`, `snapshot-3d-exit`, `snapshot-3d-status`.
```

**Step 2: Add API endpoints to devtools doc**

```markdown
### snapshot-3d-enter

Enter 3D DOM inspection mode. Explodes the page into a layered depth view.

- Method: POST
- Body: none
- Response: `{success: true}` or error if already active

### snapshot-3d-exit

Exit 3D DOM inspection mode. Restores the page to its original state.

- Method: POST
- Body: none
- Response: `{success: true}` (idempotent)

### snapshot-3d-status

Check whether 3D inspection mode is currently active.

- Method: GET
- Body: none
- Response: `{success: true, active: true|false}`
```

**Step 3: Commit**

```bash
git add docs/functionality.md docs/api/devtools.md
git commit -m "docs: 3D DOM inspector feature and API endpoints"
```

---

## Known Limitations (documented, not fixable)

| Limitation | Reason |
|-----------|--------|
| Background JS keeps running | Cannot stop timers/workers from injected JS |
| Hover degrades at steep angles | `elementFromPoint()` is 2D; 3D projection not accounted for |
| Canvas/WebGL/video are opaque | Raster surfaces with no DOM internals |
| Cross-origin iframes are opaque | Security sandbox prevents access |
| Closed shadow roots are opaque | Web platform restriction |
| Not true CSS paint order | Would require browser-engine-level stacking context tree computation |
| MutationObservers may fire | Minimised by using WeakMap, but `data-m3d-depth` attribute and style writes still trigger |
| Max 5,000 elements | Performance cap to avoid freezing large SPAs |

## Controls Summary

| Input | Action |
|-------|--------|
| Click + drag | Rotate the 3D scene |
| Scroll wheel | Zoom in/out |
| Hover (not dragging) | Highlight element, show info with position/z-index |
| `+` / `-` keys | Increase / decrease layer spacing |
| `R` key | Reset rotation and zoom |
| `Escape` or close button | Exit 3D mode |

## Platform Scope

This feature is macOS-only. The JavaScript works identically on iOS WKWebView and Android CDP, but the floating menu integration and mouse drag interaction are desktop-specific. Mobile would need touch gesture handling (pinch-zoom, two-finger rotate) as a separate follow-up.
