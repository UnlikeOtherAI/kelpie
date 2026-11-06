package com.kelpie.browser.ui

import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.clearAndSetSemantics

/** Keep normal chrome in place while the separate Stop popup owns interaction. */
internal fun Modifier.scriptInputBlock(active: Boolean): Modifier =
    if (!active) {
        this
    } else {
        clearAndSetSemantics { }
            .onPreviewKeyEvent { blocksScriptBrowserKey(active, it.nativeKeyEvent.isSystem) }
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
                    }
                }
            }
    }
