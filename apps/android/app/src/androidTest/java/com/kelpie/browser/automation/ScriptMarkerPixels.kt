package com.kelpie.browser.automation

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** Scene-local native screenshot oracle; chrome color or text fringes cannot qualify. */
internal object ScriptMarkerPixels {
    data class Evidence(
        val area: Int,
        val x: Double,
        val y: Double,
        val centerCoverage: Double,
    )

    fun locate(
        image: Bitmap,
        target: Rect,
    ): Evidence? {
        if (target.width() <= 0 || target.height() <= 0) return null
        val roi = Rect(target)
        if (!roi.intersect(0, 0, image.width, image.height)) return null
        val width = roi.width()
        val height = roi.height()
        if (width < 16 || height < 16) return null
        val mask = BooleanArray(width * height)

        fun blue(
            x: Int,
            y: Int,
        ): Boolean {
            val color = image.getPixel(x, y)
            return Color.blue(color) > Color.red(color) + 50 && Color.blue(color) > Color.green(color) + 20
        }
        for (y in 0 until height) for (x in 0 until width) mask[y * width + x] = blue(x + roi.left, y + roi.top)
        val queue = IntArray(mask.size)
        var bestArea = 0
        var bestX = 0.0
        var bestY = 0.0
        var bestWidth = 0
        var bestHeight = 0
        for (start in mask.indices) {
            if (!mask[start]) continue
            var head = 0
            var tail = 1
            var xSum = 0L
            var ySum = 0L
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            queue[0] = start
            mask[start] = false
            while (head < tail) {
                val index = queue[head++]
                val x = index % width
                val y = index / width
                xSum += x
                ySum += y
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                for (dy in -1..1) {
                    for (dx in -1..1) {
                        val nx = x + dx
                        val ny = y + dy
                        if (nx !in 0 until width || ny !in 0 until height) continue
                        val next = ny * width + nx
                        if (mask[next]) {
                            mask[next] = false
                            queue[tail++] = next
                        }
                    }
                }
            }
            if (tail > bestArea) {
                bestArea = tail
                bestX = roi.left + xSum.toDouble() / tail
                bestY = roi.top + ySum.toDouble() / tail
                bestWidth = maxX - minX + 1
                bestHeight = maxY - minY + 1
            }
        }
        if (bestArea < max(100.0, width * height * 0.02) || bestArea > width * height * 0.60) return null
        if (min(bestWidth, bestHeight) < 16 || bestWidth.toDouble() / bestHeight !in 0.6..1.67) return null
        val tolerance = max(4.0, min(width, height) * 0.08)
        if (abs(bestX - roi.exactCenterX()) > tolerance || abs(bestY - roi.exactCenterY()) > tolerance) return null
        val half = max(3, min(width, height) / 10)
        val center = Rect(roi.centerX() - half, roi.centerY() - half, roi.centerX() + half, roi.centerY() + half)
        var blueCenter = 0
        for (y in center.top until center.bottom) for (x in center.left until center.right) if (blue(x, y)) blueCenter++
        val coverage = blueCenter.toDouble() / (center.width() * center.height())
        if (coverage < 0.20) return null
        return Evidence(bestArea, bestX, bestY, coverage)
    }
}
