package com.kelpie.browser.browser

import kotlin.math.pow

/** Pure colour math, also used by tests without an Android runtime. */
object ChromePalette {
    const val GRAY: Int = -1709325 // #e5eaf3
    const val INK: Int = -14208179 // #27334d

    fun foreground(background: Int): Int {
        fun linear(shift: Int): Double {
            val value = ((background ushr shift) and 255) / 255.0
            return if (value <= 0.04045) value / 12.92 else ((value + 0.055) / 1.055).pow(2.4)
        }
        val luminance = 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
        return if (luminance < 0.35) -1 else INK
    }

    fun median(pixels: IntArray): Int {
        val visible = pixels.filter { (it ushr 24) > 127 }
        if (visible.isEmpty()) return -1

        fun channel(shift: Int) = visible.map { (it ushr shift) and 255 }.sorted()[visible.size / 2]
        return (255 shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
    }
}
