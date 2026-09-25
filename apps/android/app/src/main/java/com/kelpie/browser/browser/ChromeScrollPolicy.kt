package com.kelpie.browser.browser

import kotlin.math.abs

/** Mirrors iOS: only deliberate finger motion changes the browser surface. */
class ChromeScrollPolicy {
    private var anchor = 0f

    fun update(translation: Float, offset: Float, maximum: Float, userDragging: Boolean): Boolean? {
        if (!userDragging || maximum <= 24 || offset < 0 || offset > maximum) {
            anchor = translation
            return null
        }
        val distance = translation - anchor
        if (abs(distance) <= 18) return null
        anchor = translation
        return distance < 0
    }
}
