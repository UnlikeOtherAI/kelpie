package com.kelpie.browser.handlers

fun elementSelectorBuilderScript(): String =
    """
    function kelpieEscapeIdentifier(value) {
        if (window.CSS && typeof window.CSS.escape === 'function') {
            return window.CSS.escape(String(value));
        }
        return String(value).replace(/([ !"#$%&'()*+,./:;<=>?@[\\\]^`{|}~])/g, '\\$1');
    }
    function kelpieEscapeAttribute(value) {
        return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    }
    function kelpieBuildSelector(node) {
        if (!node || node.nodeType !== 1) return null;
        function identifiesNode(candidate) {
            try {
                var matches = document.querySelectorAll(candidate);
                return matches.length === 1 && matches[0] === node;
            } catch (error) { return false; }
        }
        if (node.id) {
            var id = '#' + kelpieEscapeIdentifier(node.id);
            if (identifiesNode(id)) return id;
        }
        var segments = [];
        var current = node;
        while (current && current.nodeType === 1) {
            var tag = current.tagName.toLowerCase();
            var segment = tag;
            if (current.id) {
                var identified = [tag + '#' + kelpieEscapeIdentifier(current.id)].concat(segments).join(' > ');
                if (identifiesNode(identified)) return identified;
            }
            var name = current.getAttribute && current.getAttribute('name');
            if (name) {
                var named = tag + '[name="' + kelpieEscapeAttribute(name) + '"]';
                var namedPath = [named].concat(segments).join(' > ');
                if (identifiesNode(namedPath)) return namedPath;
            }
            var parent = current.parentElement;
            if (parent) {
                var index = 1;
                var sibling = current;
                while ((sibling = sibling.previousElementSibling)) {
                    if (sibling.tagName === current.tagName) index += 1;
                }
                segment += ':nth-of-type(' + index + ')';
            }
            segments.unshift(segment);
            var candidate = segments.join(' > ');
            if (identifiesNode(candidate)) return candidate;
            current = parent;
        }
        return null;
    }
    """.trimIndent()

fun formControlMutationScript(): String =
    """
    function kelpieFormControlPrototype(node) {
        if (window.HTMLInputElement && node instanceof window.HTMLInputElement) return window.HTMLInputElement.prototype;
        if (window.HTMLTextAreaElement && node instanceof window.HTMLTextAreaElement) return window.HTMLTextAreaElement.prototype;
        return null;
    }
    function kelpieReadFormControlValue(node) {
        if (!node) return '';
        if (typeof node.value === 'string') return node.value;
        if (node.isContentEditable) return node.textContent || '';
        return '';
    }
    function kelpieWriteFormControlValue(node, value) {
        if (!node) return '';
        var previousValue = kelpieReadFormControlValue(node);
        if (window.HTMLSelectElement && node instanceof window.HTMLSelectElement) {
            node.value = value;
            return previousValue;
        }
        if (node.isContentEditable) {
            node.textContent = value;
            return previousValue;
        }
        var prototype = kelpieFormControlPrototype(node);
        var setter = prototype ? Object.getOwnPropertyDescriptor(prototype, 'value')?.set : null;
        if (setter) setter.call(node, value);
        else if ('value' in node) node.value = value;
        else node.textContent = value;
        var tracker = node._valueTracker;
        if (tracker && typeof tracker.setValue === 'function') {
            tracker.setValue(previousValue);
        }
        return previousValue;
    }
    function kelpieDispatchFormControlInput(node) {
        node.dispatchEvent(new Event('input', { bubbles: true }));
    }
    function kelpieDispatchFormControlChange(node) {
        node.dispatchEvent(new Event('change', { bubbles: true }));
    }
    """.trimIndent()
