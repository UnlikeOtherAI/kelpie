package com.kelpie.browser.handlers

fun annotationElementsScript(): String =
    """
    (function() {
        ${elementSelectorBuilderScript()}
        var els = document.querySelectorAll('a,button,input,select,textarea,[role=button]');
        return Array.from(els).map(function(el) {
            var r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0) return null;
            return {
                role: el.getAttribute('role') || el.tagName.toLowerCase(),
                name: (el.textContent || el.value || el.placeholder || '').trim().substring(0, 50),
                selector: kelpieBuildSelector(el),
                rect: {x: r.x, y: r.y, width: r.width, height: r.height}
            };
        }).filter(Boolean).slice(0, 50).map(function(item, index) {
            item.index = index;
            return item;
        });
    })()
    """.trimIndent()

fun selectorActivationScript(selector: String): String {
    val escaped = JSEscape.string(selector)
    val resolver =
        """
        (function() {
            var selector = '$escaped';
            var el = null;
            try { el = document.querySelector(selector); } catch (_) {}
            if (el) return el;
            var normalized = selector.trim().toLowerCase();
            if (!normalized) return null;
            var tags = 'a,button,input,select,textarea,' +
                '[role=button],[role=link],[role=menuitem]';
            var candidates = Array.from(document.querySelectorAll(tags));
            var textFor = function(node) {
                return ((node.textContent || node.value || node.placeholder
                    || node.getAttribute('aria-label') || '') + '')
                    .trim().toLowerCase();
            };
            el = candidates.find(function(node) {
                return textFor(node) === normalized;
            }) || candidates.find(function(node) {
                return textFor(node).indexOf(normalized) >= 0;
            });
            return el || null;
        })()
        """.trimIndent()
    return activationScript(resolver = resolver, selector = selector)
}

fun annotationActivationScript(index: Int): String =
    activationScript(
        resolver = "(function() { return (${annotationElementsScript()}).find(function(item) { return item.index === $index; }); })()",
        annotationIndex = index,
        usingAnnotation = true,
    )

fun fillElementScript(
    selector: String,
    value: String,
): String =
    """
    (function() {
        ${elementSelectorBuilderScript()}
        ${interactionHelpersScript()}
        ${formControlMutationScript()}
        var selector = '${JSEscape.string(selector)}';
        var value = '${JSEscape.string(value)}';
        var el = document.querySelector(selector);
        if (!el) {
            return {error: 'not_found', diagnostics: kelpieNotFoundDiagnostics(selector, null)};
        }
        var tag = el.tagName ? el.tagName.toLowerCase() : '';
        var editable = ['input', 'textarea', 'select'].includes(tag) || !!el.isContentEditable;
        if (!editable || !!el.disabled || !!el.readOnly) {
            return {error: 'not_editable', diagnostics: kelpieEditableDiagnostics(el, selector, null)};
        }
        el.focus();
        if (el.isContentEditable) {
            el.textContent = value;
        } else {
            kelpieWriteFormControlValue(el, value);
        }
        kelpieDispatchFormControlInput(el);
        kelpieDispatchFormControlChange(el);
        return {
            selector: selector,
            value: value,
            element: kelpieElementSummary(el)
        };
    })()
    """.trimIndent()

fun fillAnnotationScript(
    index: Int,
    value: String,
): String =
    """
    (function() {
        ${elementSelectorBuilderScript()}
        ${interactionHelpersScript()}
        ${formControlMutationScript()}
        var annotationIndex = $index;
        var value = '${JSEscape.string(value)}';
        var annotation = (${annotationElementsScript()}).find(function(item) { return item.index === annotationIndex; });
        if (!annotation) {
            return {error: 'not_found', diagnostics: kelpieBaseDiagnostics(null, annotationIndex)};
        }
        var matches = Array.from(document.querySelectorAll('a,button,input,select,textarea,[role=button]')).filter(function(node) {
            var rect = node.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0;
        });
        var el = matches[annotation.index];
        if (!el) {
            return {error: 'not_found', diagnostics: kelpieNotFoundDiagnostics(annotation.selector || null, annotationIndex)};
        }
        var tag = el.tagName ? el.tagName.toLowerCase() : '';
        var editable = ['input', 'textarea', 'select'].includes(tag) || !!el.isContentEditable;
        if (!editable || !!el.disabled || !!el.readOnly) {
            return {error: 'not_editable', diagnostics: kelpieEditableDiagnostics(el, annotation.selector || null, annotationIndex)};
        }
        el.focus();
        if (el.isContentEditable) {
            el.textContent = value;
        } else {
            kelpieWriteFormControlValue(el, value);
        }
        kelpieDispatchFormControlInput(el);
        kelpieDispatchFormControlChange(el);
        return {
            role: el.getAttribute('role') || el.tagName.toLowerCase(),
            name: (el.placeholder || el.name || '').trim(),
            selector: kelpieBuildSelector(el)
        };
    })()
    """.trimIndent()

fun interactionHelpersScript(): String =
    """
    function kelpieRectJSON(rect) {
        return {x: rect.x, y: rect.y, width: rect.width, height: rect.height};
    }
    function kelpieViewportDiagnostics() {
        return {
            viewport: {width: window.innerWidth || 0, height: window.innerHeight || 0},
            scrollPosition: {x: window.scrollX || 0, y: window.scrollY || 0}
        };
    }
    function kelpieElementSummary(node) {
        if (!node) return null;
        var rect = typeof node.getBoundingClientRect === 'function'
            ? node.getBoundingClientRect()
            : {x: 0, y: 0, width: 0, height: 0};
        return {
            tag: node.tagName ? node.tagName.toLowerCase() : null,
            role: node.getAttribute ? (node.getAttribute('role') || (node.tagName ? node.tagName.toLowerCase() : null)) : null,
            text: ((node.innerText || node.textContent || node.value || node.placeholder || '') + '').trim().substring(0, 100),
            selector: node.tagName ? kelpieBuildSelector(node) : null,
            rect: kelpieRectJSON(rect)
        };
    }
    function kelpieBaseDiagnostics(selector, annotationIndex) {
        var diagnostics = kelpieViewportDiagnostics();
        if (selector) diagnostics.selector = selector;
        if (annotationIndex !== null && annotationIndex !== undefined) diagnostics.annotationIndex = annotationIndex;
        return diagnostics;
    }
    function kelpieSelectorTokens(selector) {
        var matches = (selector || '').toLowerCase().match(/[a-z0-9_-]+/g) || [];
        var seen = new Set();
        return matches.filter(function(token) {
            if (token.length < 2) return false;
            if (['div', 'span', 'button', 'input', 'select', 'textarea', 'role', 'aria', 'data'].includes(token)) return false;
            if (seen.has(token)) return false;
            seen.add(token);
            return true;
        }).slice(0, 6);
    }
    function kelpieSimilarElements(selector) {
        var tokens = kelpieSelectorTokens(selector);
        if (!tokens.length) return [];
        return Array.from(document.querySelectorAll('a,button,input,select,textarea,[role=button]')).map(function(node) {
            var rect = node.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) return null;
            var haystack = [
                node.id || '',
                node.getAttribute('name') || '',
                node.getAttribute('aria-label') || '',
                node.getAttribute('placeholder') || '',
                typeof node.className === 'string' ? node.className : '',
                node.innerText || '',
                node.textContent || '',
                node.value || '',
                node.tagName || ''
            ].join(' ').toLowerCase();
            var score = tokens.reduce(function(total, token) {
                return total + (haystack.indexOf(token) >= 0 ? 1 : 0);
            }, 0);
            if (!score) return null;
            var summary = kelpieElementSummary(node);
            summary.score = score;
            return summary;
        }).filter(Boolean).sort(function(lhs, rhs) {
            return rhs.score - lhs.score;
        }).slice(0, 5).map(function(item) {
            return {
                selector: item.selector,
                text: item.text,
                tag: item.tag,
                role: item.role,
                rect: item.rect
            };
        });
    }
    function kelpieNotFoundDiagnostics(selector, annotationIndex) {
        var diagnostics = kelpieBaseDiagnostics(selector, annotationIndex);
        if (selector) diagnostics.similarElements = kelpieSimilarElements(selector);
        return diagnostics;
    }
    function kelpieEditableDiagnostics(el, selector, annotationIndex) {
        var tag = el.tagName ? el.tagName.toLowerCase() : null;
        var diagnostics = kelpieBaseDiagnostics(selector, annotationIndex);
        diagnostics.tag = tag;
        diagnostics.targetRect = kelpieRectJSON(el.getBoundingClientRect());
        diagnostics.isInput = ['input', 'textarea', 'select'].includes(tag);
        diagnostics.disabled = !!el.disabled;
        diagnostics.readOnly = !!el.readOnly;
        diagnostics.isContentEditable = !!el.isContentEditable;
        return diagnostics;
    }
    function kelpieTapDiagnostics(target, requestedX, requestedY, appliedX, appliedY, offsetX, offsetY) {
        var diagnostics = kelpieBaseDiagnostics(null, null);
        diagnostics.requestedPoint = {x: requestedX, y: requestedY};
        diagnostics.clickedPoint = {x: appliedX, y: appliedY};
        diagnostics.offset = {x: offsetX, y: offsetY};
        diagnostics.actualElementAtPoint = kelpieElementSummary(target);
        return diagnostics;
    }
    """.trimIndent()

private fun activationScript(
    resolver: String,
    selector: String? = null,
    annotationIndex: Int? = null,
    usingAnnotation: Boolean = false,
): String {
    val selectorLiteral = selector?.let { "'${JSEscape.string(it)}'" } ?: "null"
    val annotationLiteral = annotationIndex?.toString() ?: "null"
    val elementLookup =
        if (usingAnnotation) {
            """
            var annotation = $resolver;
            if (!annotation) return {error: 'not_found', diagnostics: kelpieBaseDiagnostics(null, requestedAnnotationIndex)};
            var matches = Array.from(document.querySelectorAll('a,button,input,select,textarea,[role=button]')).filter(function(node) {
                var rect = node.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            });
            var el = matches[annotation.index];
            if (!el) return {error: 'not_found', diagnostics: kelpieNotFoundDiagnostics(annotation.selector || null, requestedAnnotationIndex)};
            """.trimIndent()
        } else {
            """
            var el = $resolver;
            if (!el) return {error: 'not_found', diagnostics: kelpieNotFoundDiagnostics(requestedSelector, requestedAnnotationIndex)};
            """.trimIndent()
        }

    return """
        |(function() {
        |    ${elementSelectorBuilderScript().prependIndent("    ").trimStart()}
        |    ${interactionHelpersScript().prependIndent("    ").trimStart()}
        |    var requestedSelector = $selectorLiteral;
        |    var requestedAnnotationIndex = $annotationLiteral;
        |    $elementLookup
        |    el.scrollIntoView({block: 'center', inline: 'center'});
        |    var rect = el.getBoundingClientRect();
        |    if (rect.width <= 0 || rect.height <= 0) {
        |        var diagnostics = kelpieBaseDiagnostics(requestedSelector, requestedAnnotationIndex);
        |        diagnostics.targetRect = kelpieRectJSON(rect);
        |        return {error: 'not_visible', diagnostics: diagnostics};
        |    }
        |    var centerX = rect.left + rect.width / 2;
        |    var centerY = rect.top + rect.height / 2;
        |    var hit = document.elementFromPoint(centerX, centerY);
        |    if (!hit) {
        |        var diagnostics = kelpieBaseDiagnostics(requestedSelector, requestedAnnotationIndex);
        |        diagnostics.targetRect = kelpieRectJSON(rect);
        |        diagnostics.targetCenter = {x: centerX, y: centerY};
        |        return {error: 'not_visible', diagnostics: diagnostics};
        |    }
        |    if (!(hit === el || el.contains(hit) || hit.contains(el))) {
        |        var diagnostics = kelpieBaseDiagnostics(requestedSelector, requestedAnnotationIndex);
        |        diagnostics.targetRect = kelpieRectJSON(rect);
        |        diagnostics.targetCenter = {x: centerX, y: centerY};
        |        diagnostics.actualElementAtPoint = kelpieElementSummary(hit);
        |        diagnostics.obstruction = kelpieElementSummary(hit);
        |        return {error: 'not_visible', diagnostics: diagnostics};
        |    }
        |    if (typeof hit.focus === 'function') {
        |        try { hit.focus({preventScroll: true}); } catch (error) { try { hit.focus(); } catch (focusError) {} }
        |    }
        |    function dispatchPointer(type, button, buttons) {
        |        if (typeof window.PointerEvent !== 'function') return;
        |        hit.dispatchEvent(new PointerEvent(type, {
        |            bubbles: true,
        |            cancelable: true,
        |            composed: true,
        |            clientX: centerX,
        |            clientY: centerY,
        |            screenX: centerX,
        |            screenY: centerY,
        |            pointerId: 1,
        |            pointerType: 'touch',
        |            isPrimary: true,
        |            button: button,
        |            buttons: buttons
        |        }));
        |    }
        |    function dispatchMouse(type, button, buttons) {
        |        hit.dispatchEvent(new MouseEvent(type, {
        |            bubbles: true,
        |            cancelable: true,
        |            composed: true,
        |            clientX: centerX,
        |            clientY: centerY,
        |            screenX: centerX,
        |            screenY: centerY,
        |            detail: type === 'click' ? 1 : 0,
        |            button: button,
        |            buttons: buttons
        |        }));
        |    }
        |    dispatchPointer('pointermove', 0, 0);
        |    dispatchMouse('mousemove', 0, 0);
        |    dispatchPointer('pointerdown', 0, 1);
        |    dispatchMouse('mousedown', 0, 1);
        |    dispatchPointer('pointerup', 0, 0);
        |    dispatchMouse('mouseup', 0, 0);
        |    if (typeof hit.click === 'function') {
        |        hit.click();
        |    } else {
        |        dispatchMouse('click', 0, 0);
        |    }
        |    return {
        |        tag: el.tagName.toLowerCase(),
        |        role: el.getAttribute('role') || el.tagName.toLowerCase(),
        |        name: (el.textContent || el.value || el.placeholder || '').trim().substring(0, 50),
        |        selector: kelpieBuildSelector(el),
        |        text: (el.textContent || '').trim().substring(0, 100),
        |        rect: {x: rect.x, y: rect.y, width: rect.width, height: rect.height},
        |        center: {x: centerX, y: centerY}
        |    };
        |})()
        """.trimMargin()
}

data class TapExecution(
    val requestedX: Double,
    val requestedY: Double,
    val appliedX: Double,
    val appliedY: Double,
    val offsetX: Double,
    val offsetY: Double,
)
