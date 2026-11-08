package com.kelpie.browser.browser

import android.view.View
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

class KeyboardObserver(
    private val rootView: View,
) {
    var isVisible: Boolean = false
        private set

    var height: Int = 0
        private set

    init {
        ViewCompat.setOnApplyWindowInsetsListener(rootView) { _, insets ->
            update(insets)
            insets
        }
        ViewCompat.getRootWindowInsets(rootView)?.let(::update)
        ViewCompat.requestApplyInsets(rootView)
    }

    private fun update(insets: WindowInsetsCompat) {
        val imeInsets = insets.getInsets(WindowInsetsCompat.Type.ime())
        val navigationBars = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
        height = (imeInsets.bottom - navigationBars.bottom).coerceAtLeast(0)
        isVisible = height > 0
    }
}
