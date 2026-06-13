package com.kelpie.browser.handlers

import com.kelpie.browser.KelpieApp

/**
 * Bridge exposing the 3D-inspector JavaScript to Kotlin callers.
 *
 * The enter and exit scripts live as standalone JS sources under
 * `assets/snapshot3d/`. The enter script is assembled at first access
 * from four phase files (setup, collect, apply, input) so each individual
 * source file stays within the project's 500-line limit. The phases share
 * closure state inside one IIFE, so the concatenation is what runs.
 *
 * The small runtime-control scripts (mode/zoom/reset) stay inline because
 * they take Kotlin-side arguments.
 */
object Snapshot3DBridge {
    val ENTER_SCRIPT: String by lazy {
        listOf(
            "enter-setup",
            "enter-collect",
            "enter-apply",
            "enter-input",
        ).joinToString(separator = "") { loadAsset(it) }
    }

    val EXIT_SCRIPT: String by lazy { loadAsset("exit") }

    fun setModeScript(mode: String): String =
        """
        (function() {
            if (!window.__m3d || typeof window.__m3d.setMode !== 'function') return null;
            return window.__m3d.setMode('$mode');
        })();
        """.trimIndent()

    val RESET_VIEW_SCRIPT: String =
        """
        (function() {
            if (!window.__m3d || typeof window.__m3d.resetView !== 'function') return false;
            return window.__m3d.resetView();
        })();
        """.trimIndent()

    fun zoomByScript(delta: Double): String =
        """
        (function() {
            if (!window.__m3d || typeof window.__m3d.zoomBy !== 'function') return null;
            return window.__m3d.zoomBy($delta);
        })();
        """.trimIndent()

    /**
     * Load a bundled JS asset from `assets/snapshot3d/<name>.js`.
     *
     * The script is part of the app bundle; if the asset is missing the
     * bundle is broken and the inspector cannot run. Throw loudly rather
     * than silently returning an empty script.
     */
    private fun loadAsset(name: String): String {
        val path = "snapshot3d/$name.js"
        return KelpieApp.app.assets
            .open(path)
            .bufferedReader(Charsets.UTF_8)
            .use { it.readText() }
    }
}
