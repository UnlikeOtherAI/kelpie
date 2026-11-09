    // The toolbox follows the real DOM, including unrendered nodes. Children are
    // created on expansion so a large document doesn't require a second full copy.
    var treeRows = new WeakMap();
    var sceneEntries = new WeakMap();
    collected.forEach(function(item) { sceneEntries.set(item.el, item); });
    var treePanel, treeRoot, selectedRow;

    function elementLabel(el) {
        return '<' + el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
            (el.classList.length ? '.' + Array.from(el.classList).join('.') : '') + '>';
    }

    function parentNode(el) {
        if (el.parentElement) return el.parentElement;
        var root = el.getRootNode();
        if (root.host) return root.host;
        try { return el.ownerDocument.defaultView.frameElement; } catch(e) { return null; }
    }

    function childElements(el) {
        var children = Array.from(el.children);
        if (el.shadowRoot) children = children.concat(Array.from(el.shadowRoot.children));
        if (el.tagName === 'IFRAME') {
            try { if (el.contentDocument) children.push(el.contentDocument.documentElement); } catch(e) {}
        }
        return children.filter(function(child) {
            return child !== overlay && child !== suppressStyle && !child.classList.contains('__m3d_iframe_label');
        });
    }

    function expandRow(record, expand) {
        record.row.setAttribute('aria-expanded', String(expand));
        record.toggle.textContent = expand ? '▾' : '▸';
        record.children.hidden = !expand;
        if (expand && !record.loaded) {
            childElements(record.el).forEach(function(el) {
                record.children.appendChild(makeTreeRow(el, record.level + 1));
            });
            record.loaded = true;
        }
    }

    function makeTreeRow(el, level) {
        var branch = document.createElement('div');
        var row = document.createElement('div');
        row.className = 'tree-row';
        row.setAttribute('role', 'treeitem');
        row.setAttribute('aria-level', String(level));
        row.setAttribute('aria-selected', 'false');
        row.tabIndex = 0;
        row.style.paddingLeft = (8 + (level - 1) * 14) + 'px';
        var toggle = document.createElement('span');
        toggle.className = 'disclosure';
        toggle.setAttribute('aria-hidden', 'true');
        var hasChildren = childElements(el).length > 0;
        toggle.textContent = hasChildren ? '▸' : '·';
        if (hasChildren) row.setAttribute('aria-expanded', 'false');
        var label = document.createElement('span');
        label.textContent = elementLabel(el);
        row.title = label.textContent;
        row.setAttribute('aria-label', label.textContent);
        row.append(toggle, label);
        var children = document.createElement('div');
        children.setAttribute('role', 'group');
        children.hidden = true;
        branch.append(row, children);
        var record = {el: el, row: row, toggle: toggle, children: children, level: level, loaded: false};
        treeRows.set(el, record);
        row.addEventListener('pointerenter', function() { highlightElement(el, true); });
        row.addEventListener('focus', function() { highlightElement(el, true); });
        row.addEventListener('click', function(e) {
            if (hasChildren && e.target === toggle) {
                expandRow(record, children.hidden);
            } else highlightElement(el, true);
        });
        row.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowRight' && hasChildren) expandRow(record, true);
            else if (e.key === 'ArrowLeft' && hasChildren) expandRow(record, false);
            else if (e.key === 'Enter' || e.key === ' ') highlightElement(el, true);
            else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
                var rows = Array.from(treeRoot.querySelectorAll('.tree-row')).filter(function(r) { return r.getClientRects().length; });
                var next = rows[rows.indexOf(row) + (e.key === 'ArrowDown' ? 1 : -1)];
                if (next) next.focus();
            } else return;
            e.preventDefault();
        });
        return branch;
    }

    function revealTreeElement(el) {
        if (!treePanel || treePanel.hidden) return;
        var path = [], current = el;
        while (current && current !== document.documentElement) { path.unshift(current); current = parentNode(current); }
        if (!current) return;
        var parent = treeRows.get(document.documentElement);
        for (var i = 0; i < path.length && parent; i++) {
            expandRow(parent, true);
            parent = treeRows.get(path[i]);
        }
        var record = treeRows.get(el);
        if (!record) return;
        if (selectedRow) selectedRow.setAttribute('aria-selected', 'false');
        selectedRow = record.row;
        selectedRow.setAttribute('aria-selected', 'true');
        // Scroll only the toolbox; scrollIntoView can also scroll the source page.
        var rowRect = selectedRow.getBoundingClientRect(), box = treeRoot.getBoundingClientRect();
        if (rowRect.top < box.top) treeRoot.scrollTop += rowRect.top - box.top;
        else if (rowRect.bottom > box.bottom) treeRoot.scrollTop += rowRect.bottom - box.bottom;
    }

    function revealSceneElement(el) {
        if (!sceneEntries.has(el)) return;
        var left = treePanel && !treePanel.hidden ? treePanel.getBoundingClientRect().right + 16 : leftTools.getBoundingClientRect().right + 16;
        var right = rightTools.getBoundingClientRect().left - 16;
        var top = 24, bottom = window.innerHeight - 80;
        // Translation, rather than fit-to-selection, preserves zoom and rotation.
        for (var i = 0; i < 3; i++) {
            var rect = el.getBoundingClientRect();
            var dx = rect.right < left || rect.left > right ? (left + right - rect.left - rect.right) / 2 : 0;
            var dy = rect.bottom < top || rect.top > bottom ? (top + bottom - rect.top - rect.bottom) / 2 : 0;
            if (!dx && !dy) break;
            panX += dx;
            panY += dy;
            applyTransform();
        }
    }

    function highlightElement(el, reveal) {
        if (hoveredEl && sceneEntries.has(hoveredEl)) hoveredEl.style.outline = '1px solid rgba(0,150,255,0.25)';
        hoveredEl = el;
        var item = el && sceneEntries.get(el);
        if (item) {
            el.style.outline = '3px solid #f5a623';
            if (reveal) revealSceneElement(el);
            var rect = el.getBoundingClientRect();
            infoPanel.textContent = elementLabel(el) + ' ' + Math.round(rect.width) + '×' + Math.round(rect.height) +
                ' depth:' + item.depth + ' ' + item.metadata;
        } else if (el) {
            infoPanel.textContent = elementLabel(el) + ' — no rendered plane (hidden, too small, or outside the 5,000-plane limit)';
        }
        infoPanel.style.opacity = el ? '1' : '0';
        if (el) revealTreeElement(el);
    }

    function highlightAt(x, y) {
        overlay.style.display = 'none';
        var target;
        try {
            target = document.elementFromPoint(x, y);
            while (target) {
                var inner = target.shadowRoot && target.shadowRoot.elementFromPoint(x, y);
                if (!inner || inner === target) break;
                target = inner;
            }
        } finally { overlay.style.display = ''; }
        if (target === hoveredEl) return;
        highlightElement(target && sceneEntries.has(target) ? target : null, false);
    }
