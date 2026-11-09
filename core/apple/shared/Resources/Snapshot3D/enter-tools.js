    // Isolate scene-local controls from the inspected site's CSS and handlers.
    var toolsHost = document.createElement('div');
    toolsHost.style.cssText = 'position:absolute;inset:0;pointer-events:none;';
    overlay.appendChild(toolsHost);
    var uiScale = 1;
    function layoutTools() {
        uiScale = 1 / ((window.visualViewport && window.visualViewport.scale) || 1);
        toolsHost.style.width = (window.innerWidth / uiScale) + 'px';
        toolsHost.style.height = (window.innerHeight / uiScale) + 'px';
        toolsHost.style.transformOrigin = 'top left';
        toolsHost.style.transform = 'scale(' + uiScale + ')';
    }
    layoutTools();
    addListener(window, 'resize', layoutTools, false);
    if (window.visualViewport) addListener(window.visualViewport, 'resize', layoutTools, false);
    var tools = toolsHost.attachShadow({mode: 'open'});
    ['click', 'dblclick', 'mousedown', 'mousemove', 'touchstart', 'touchmove', 'wheel', 'keydown'].forEach(function(type) {
        toolsHost.addEventListener(type, function(e) { e.stopPropagation(); });
    });
    var toolStyle = document.createElement('style');
    toolStyle.textContent = `
        :host { all: initial; color-scheme: dark; container-type: size; }
        * { box-sizing: border-box; }
        .panel { pointer-events: auto; color: #eef1f7; background: rgba(25,29,39,.96);
            border: 1px solid #434b5e; border-radius: 14px; box-shadow: 0 8px 30px #0004;
            font: 13px/1.4 -apple-system,system-ui,sans-serif; }
        button, select { font: inherit; color: inherit; background: #303747; border: 1px solid #50596d;
            border-radius: 8px; min-width: 40px; min-height: 40px; cursor: pointer; }
        button:hover, button[aria-pressed=true] { background: #435f90; border-color: #8bb7ff; }
        button:focus-visible, select:focus-visible, input:focus-visible, .tree-row:focus-visible { outline: 2px solid #8bb7ff; outline-offset: 2px; }
        .left { position: absolute; left: 12px; top: 20px; padding: 6px; display: grid; gap: 6px; }
        .left button { display: grid; justify-items: center; padding: 5px; font-size: 11px; }
        .left svg { width: 20px; height: 20px; margin-bottom: 2px; }
        .right { position: absolute; top: 20px; right: 12px; width: 200px; display: grid; gap: 10px; }
        .orientation { padding: 12px; }
        .heading { color: #aeb8cb; font-size: 11px; text-transform: uppercase; letter-spacing: .08em; }
        .orbit { height: 150px; position: relative; perspective: 550px; touch-action: none; cursor: grab; }
        .mini { position: absolute; left: calc(50% - 36px); top: 26px; width: 72px; height: 96px;
            transform-style: preserve-3d; }
        .mini img { width: 72px; height: 96px; object-fit: contain; background: #fff; border: 1px solid #929aab; }
        .ring { position: absolute; left: -30px; top: -18px; width: 132px; height: 132px; border: 2px solid;
            border-radius: 50%; pointer-events: none; }
        .x { border-color: #ff646f; transform: rotateY(90deg); }
        .y { border-color: #62d99b; transform: rotateX(90deg); }
        .z { border-color: #6aabff; }
        .axes, .zoom { display: flex; gap: 5px; align-items: center; justify-content: space-between; }
        .axes button { min-width: 0; flex: 1; min-height: 32px; font-size: 11px; }
        .axes button:nth-child(1) { color: #ff8790; }
        .axes button:nth-child(2) { color: #80e4b0; }
        .axes button:nth-child(3) { color: #8cbdff; }
        .zoom { padding: 7px; }
        .zoom button { min-width: 34px; }
        select { min-width: 0; width: 82px; text-align: center; }
        .spacing { justify-self: end; padding: 12px 8px; display: grid; justify-items: center; gap: 8px; }
        .spacing input { writing-mode: vertical-lr; direction: rtl; appearance: auto;
            width: 28px; height: min(26cqh,200px); accent-color: #8bb7ff; touch-action: none; }
        .tree { position: absolute; left: 84px; top: 20px; bottom: 72px; width: min(340px, calc(100% - 340px)); overflow: hidden; }
        .tree header { height: 48px; padding: 7px 10px; display: flex; align-items: center; justify-content: space-between; }
        .tree header button { min-height: 32px; min-width: 32px; }
        .tree-root { height: calc(100% - 48px); overflow: auto; overscroll-behavior: contain; padding: 5px 0; }
        .tree-row { display: flex; align-items: center; min-height: 32px; white-space: nowrap; cursor: pointer;
            font: 12px/1.5 ui-monospace,monospace; padding-right: 12px; width: max-content; min-width: 100%; }
        .tree-row:hover, .tree-row[aria-selected=true] { background: #35496b; color: #ffcf83; }
        .disclosure { flex: 0 0 22px; text-align: center; }
        [hidden] { display: none !important; }
        @container (max-width: 600px) {
            .left { left: 6px; top: 10px; } .right { right: 6px; top: 10px; width: 120px; }
            .orientation { padding: 7px; } .orbit { height: 112px; transform: scale(.73); margin: -8px -20px; }
            .axes { gap: 2px; } .axes button { font-size: 10px; }
            .zoom { gap: 2px; padding: 5px; flex-wrap: wrap; } select { flex: 1; width: 44px; }
            .zoom button { min-width: 28px; } .vertical-pan { flex-direction: column; }
            .vertical-pan button { min-height: 44px !important; } .tree { left: 6px; top: 430px; bottom: 16px; width: calc(100% - 138px); }
        }
        @container (max-height: 520px) { .orbit { height: 95px; transform: scale(.65); margin: -12px 0; }
            .spacing input { height: 70px; } .left { top: 8px; gap: 2px; } .left button { padding: 3px; min-height: 32px; }
            .vertical-pan { flex-direction: row; } .vertical-pan button { min-height: 32px !important; }
            .right { top: 8px; width: 250px; gap: 8px; grid-template-columns: 1fr 56px; }
            .orientation { grid-column: 1; } .zoom { grid-column: 1; }
            .spacing { grid-column: 2; grid-row: 1 / span 2; }
            .tree { top: 8px; bottom: 8px; left: 80px; width: calc(100% - 92px); z-index: 1; } }
    `;
    tools.appendChild(toolStyle);

    function toolElement(tag, className, parent, text) {
        var el = document.createElement(tag);
        el.className = className;
        if (text) el.textContent = text;
        parent.appendChild(el);
        return el;
    }
    function toolButton(parent, label, text, action) {
        var button = toolElement('button', '', parent, text);
        button.type = 'button';
        button.title = label;
        button.setAttribute('aria-label', label);
        button.addEventListener('click', action);
        return button;
    }
    var leftTools = toolElement('nav', 'panel left', tools);
    leftTools.setAttribute('aria-label', '3D navigation');
    var modeButtons = {};
    [['rotate', 'Rotate', '↻'], ['pan', 'Pan', '✥'], ['scroll', 'Scroll', '↕'], ['inspect', 'Inspect', '⌖']].forEach(function(mode) {
        var button = toolButton(leftTools, mode[1] + ' 3D view', mode[2] + '\n' + mode[1], function() { state.setMode(mode[0]); });
        button.style.whiteSpace = 'pre-line';
        modeButtons[mode[0]] = button;
    });
    var verticalTools = toolElement('div', 'vertical-pan', leftTools);
    verticalTools.style.cssText = 'display:flex;gap:4px;';
    toolButton(verticalTools, 'Move page up without zooming', '↑', function() {
        panY -= window.innerHeight * 0.6; applyTransform();
    }).style.cssText = 'min-width:0;min-height:32px;flex:1;';
    toolButton(verticalTools, 'Move page down without zooming', '↓', function() {
        panY += window.innerHeight * 0.6; applyTransform();
    }).style.cssText = 'min-width:0;min-height:32px;flex:1;';
    var treeToggle = toolButton(leftTools, 'Open element toolbox', '☷\nElements', function() {
        treePanel.hidden = !treePanel.hidden;
        treeToggle.setAttribute('aria-expanded', String(!treePanel.hidden));
        if (!treePanel.hidden && hoveredEl) revealTreeElement(hoveredEl);
    });
    treeToggle.style.whiteSpace = 'pre-line';
    treeToggle.setAttribute('aria-expanded', 'false');
    toolButton(leftTools, 'Reset 3D view', '↺\nReset', resetView).style.whiteSpace = 'pre-line';

    var rightTools = toolElement('aside', 'right', tools);
    rightTools.setAttribute('aria-label', '3D camera');
    var orientation = toolElement('section', 'panel orientation', rightTools);
    toolElement('div', 'heading', orientation, 'Page orientation');
    var orbit = toolElement('div', 'orbit', orientation);
    orbit.setAttribute('aria-label', 'Drag to rotate page orientation');
    var mini = toolElement('div', 'mini', orbit);
    var preview = toolElement('img', '', mini);
    preview.alt = 'Snapshot of the inspected website';
    preview.hidden = true;
    var previewStatus = toolElement('div', '', mini, 'Snapshot unavailable');
    previewStatus.style.cssText = 'width:72px;height:96px;background:#ddd;color:#333;padding:8px;font-size:10px;';
    ['x', 'y', 'z'].forEach(function(axis) { toolElement('div', 'ring ' + axis, mini); });
    var axes = toolElement('div', 'axes', orientation);
    [['X', 'Top', 90, 0], ['Y', 'Side', 0, 90], ['Z', 'Front', 0, 0]].forEach(function(axis) {
        toolButton(axes, axis[1] + ' view (' + axis[0] + ' axis)', axis[0] + ' ' + axis[1], function() {
            rotX = axis[2]; rotY = axis[3]; rotZ = 0; applyTransform();
        });
    });
    var orbitDrag = null;
    orbit.addEventListener('pointerdown', function(e) {
        orbitDrag = {x: e.clientX, y: e.clientY}; orbit.setPointerCapture(e.pointerId); e.preventDefault();
    });
    orbit.addEventListener('pointermove', function(e) {
        if (!orbitDrag) return;
        rotY += (e.clientX - orbitDrag.x) * 0.8 / uiScale;
        rotX = Math.max(-90, Math.min(90, rotX - (e.clientY - orbitDrag.y) * 0.8 / uiScale));
        orbitDrag = {x: e.clientX, y: e.clientY}; applyTransform();
    });
    ['pointerup', 'pointercancel', 'lostpointercapture'].forEach(function(type) {
        orbit.addEventListener(type, function() { orbitDrag = null; });
    });
    var zoomTools = toolElement('div', 'panel zoom', rightTools);
    toolButton(zoomTools, 'Zoom out 3D view', '−', function() { zoomBy(-0.1); });
    var zoomSelect = toolElement('select', '', zoomTools);
    zoomSelect.setAttribute('aria-label', '3D zoom level');
    [15, 25, 50, 75, 85, 100, 125, 150, 200, 250].forEach(function(percent) {
        var option = toolElement('option', '', zoomSelect, percent + '%'); option.value = percent;
    });
    var customZoom = toolElement('option', '', zoomSelect); customZoom.hidden = true;
    zoomSelect.addEventListener('change', function() { scale = clampScale(Number(zoomSelect.value) / 100); applyTransform(); });
    toolButton(zoomTools, 'Zoom in 3D view', '+', function() { zoomBy(0.1); });
    var spacingTools = toolElement('label', 'panel spacing', rightTools);
    toolElement('span', 'heading', spacingTools, 'Layers');
    var spacingOutput = toolElement('output', '', spacingTools);
    var spacingInput = toolElement('input', '', spacingTools);
    spacingInput.type = 'range'; spacingInput.min = '0'; spacingInput.max = '80'; spacingInput.step = '1';
    spacingInput.setAttribute('aria-label', 'Layer separation');
    spacingInput.setAttribute('aria-orientation', 'vertical');
    spacingInput.addEventListener('input', function() { state.spacing = Number(spacingInput.value); reapplyDepths(); });
    toolElement('span', '', spacingTools, '↥');

    treePanel = toolElement('section', 'panel tree', tools);
    treePanel.hidden = true;
    treePanel.setAttribute('aria-label', 'Element toolbox');
    var header = toolElement('header', '', treePanel);
    toolElement('strong', '', header, 'Elements');
    toolButton(header, 'Close element toolbox', '×', function() { treePanel.hidden = true; treeToggle.setAttribute('aria-expanded', 'false'); });
    treeRoot = toolElement('div', 'tree-root', treePanel);
    treeRoot.setAttribute('role', 'tree');
    treeRoot.setAttribute('aria-label', 'Page elements');
    treeRoot.appendChild(makeTreeRow(document.documentElement, 1));
    expandRow(treeRows.get(document.documentElement), true);
    expandRow(treeRows.get(document.body), true);

    state.setPreview = function(dataURL) {
        preview.onload = function() { preview.hidden = false; previewStatus.hidden = true; };
        preview.src = dataURL;
    };
    state.updateTools = function() {
        mini.style.transform = 'rotateX(' + rotX + 'deg) rotateY(' + rotY + 'deg) rotateZ(' + rotZ + 'deg)';
        Object.keys(modeButtons).forEach(function(mode) { modeButtons[mode].setAttribute('aria-pressed', String(state.mode === mode)); });
        var percent = Math.round(scale * 100);
        var known = Array.from(zoomSelect.options).some(function(option) { return option !== customZoom && Number(option.value) === percent; });
        customZoom.hidden = known; customZoom.value = String(percent); customZoom.textContent = percent + '%';
        zoomSelect.value = String(percent);
        spacingInput.value = String(state.spacing); spacingOutput.textContent = state.spacing + ' px';
    };
    state.updateTools();
