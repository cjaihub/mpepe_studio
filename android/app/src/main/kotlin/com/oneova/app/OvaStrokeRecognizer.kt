package com.oneova.app

import android.graphics.PointF
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max

/**
 * Recognises a hand-drawn "O" (closed loop). Same rules as the in-app
 * recogniser in `ova_gesture_detector.dart`, measured in dp so it behaves the
 * same on every screen density.
 */
object OvaStrokeRecognizer {

    fun isCircle(points: List<PointF>, density: Float): Boolean {
        if (points.size < 12) return false

        var minX = points[0].x
        var maxX = minX
        var minY = points[0].y
        var maxY = minY
        var length = 0f
        for (i in points.indices) {
            val p = points[i]
            if (p.x < minX) minX = p.x
            if (p.x > maxX) maxX = p.x
            if (p.y < minY) minY = p.y
            if (p.y > maxY) maxY = p.y
            if (i > 0) length += hypot(p.x - points[i - 1].x, p.y - points[i - 1].y)
        }
        val width = (maxX - minX) / density
        val height = (maxY - minY) / density
        length /= density

        // Big enough to be deliberate, round enough to be an "O".
        if (width < 40f || height < 40f) return false
        val aspect = width / height
        if (aspect < 0.4f || aspect > 2.4f) return false

        // Start and end meet.
        val closure = hypot(points.first().x - points.last().x, points.first().y - points.last().y) / density
        if (closure > max(width, height) * 0.5f) return false

        // Perimeter roughly matches a circle of that size.
        val radius = (width + height) / 4f
        if (length < 3.2f * radius || length > 12f * radius) return false

        // Sweeps at least ~250 degrees around its centre.
        val cx = (minX + maxX) / 2f
        val cy = (minY + maxY) / 2f
        var total = 0.0
        var prev: Double? = null
        for (p in points) {
            val a = atan2((p.y - cy).toDouble(), (p.x - cx).toDouble())
            prev?.let {
                var d = a - it
                while (d > PI) d -= 2 * PI
                while (d < -PI) d += 2 * PI
                total += d
            }
            prev = a
        }
        return abs(total) >= 4.3
    }

    /**
     * True once a stroke in progress turns steadily one way (> ~100 degrees)
     * over a real distance: an "O" being drawn, not a tap or a swipe. Used to
     * show the trail only for O strokes.
     */
    fun looksLikeO(points: List<PointF>, density: Float): Boolean {
        if (points.size < 6) return false
        var length = 0f
        var turning = 0.0
        var prevAngle: Double? = null
        var last = points[0]
        for (i in 1 until points.size) {
            val dx = points[i].x - last.x
            val dy = points[i].y - last.y
            val seg = hypot(dx, dy)
            if (seg < 4 * density) continue
            length += seg
            val a = atan2(dy.toDouble(), dx.toDouble())
            prevAngle?.let {
                var d = a - it
                while (d > PI) d -= 2 * PI
                while (d < -PI) d += 2 * PI
                turning += d
            }
            prevAngle = a
            last = points[i]
        }
        return length / density >= 48f && abs(turning) >= 1.75
    }
}
