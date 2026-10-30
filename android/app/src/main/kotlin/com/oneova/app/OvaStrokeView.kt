package com.oneova.app

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ArgbEvaluator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.SweepGradient
import android.view.View
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Full-screen, touch-through view that draws the "O" stroke while it is
 * being drawn (brand blue -> pink gradient, soft glow, tapered tail), fades
 * it out when the stroke is not an O, and plays the summon animation when it
 * is: the ring closes, pulses and morphs into the Ova orb.
 *
 * Glow is drawn with wide translucent strokes instead of blur filters so it
 * stays at 60fps on the hardware renderer.
 */
class OvaStrokeView(context: Context) : View(context) {

    private val density = resources.displayMetrics.density
    private val blue = context.getColor(R.color.brand_blue)
    private val pink = context.getColor(R.color.brand_pink)
    private val argb = ArgbEvaluator()
    private val loc = IntArray(2)

    private val points = ArrayList<PointF>()
    private var strokeAlpha = 1f

    // Summon state
    private var summoning = false
    private var progress = 0f
    private var reduceMotion = false
    private var cx = 0f
    private var cy = 0f
    private var radius = 0f
    private var startAngle = -90f

    private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val core = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    private val rect = RectF()
    private val matrixRot = Matrix()

    private var animator: ValueAnimator? = null

    init {
        setLayerType(LAYER_TYPE_HARDWARE, null)
    }

    /** Raw screen coordinates of the stroke so far. */
    fun update(raw: List<PointF>) {
        getLocationOnScreen(loc)
        points.clear()
        raw.forEach { points.add(PointF(it.x - loc[0], it.y - loc[1])) }
        invalidate()
    }

    /** Not an O: fade out quietly, then [onDone]. */
    fun fadeOut(reduceMotion: Boolean, onDone: () -> Unit) {
        animate(if (reduceMotion) 120L else 240L, LinearInterpolator(), { strokeAlpha = 1f - it }, onDone)
    }

    /** O recognised: ring closes, pulses, morphs into the orb, then [onDone]. */
    fun summon(raw: List<PointF>, reduceMotion: Boolean, onDone: () -> Unit) {
        update(raw)
        if (points.isEmpty()) {
            onDone()
            return
        }
        var minX = points[0].x
        var maxX = minX
        var minY = points[0].y
        var maxY = minY
        points.forEach {
            minX = min(minX, it.x); maxX = max(maxX, it.x)
            minY = min(minY, it.y); maxY = max(maxY, it.y)
        }
        cx = (minX + maxX) / 2f
        cy = (minY + maxY) / 2f
        radius = ((maxX - minX) + (maxY - minY)) / 4f
        startAngle = Math.toDegrees(atan2((points[0].y - cy).toDouble(), (points[0].x - cx).toDouble())).toFloat()
        this.reduceMotion = reduceMotion
        summoning = true
        animate(if (reduceMotion) 200L else 720L, LinearInterpolator(), { progress = it }, onDone)
    }

    private fun animate(duration: Long, interp: android.animation.TimeInterpolator, onValue: (Float) -> Unit, onDone: () -> Unit) {
        animator?.cancel()
        animator = ValueAnimator.ofFloat(0f, 1f).apply {
            this.duration = duration
            interpolator = interp
            addUpdateListener {
                onValue(it.animatedValue as Float)
                invalidate()
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) = onDone()
            })
            start()
        }
    }

    override fun onDetachedFromWindow() {
        animator?.removeAllListeners()
        animator?.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        if (!summoning) {
            drawStroke(canvas, strokeAlpha)
            return
        }
        val t = progress
        if (reduceMotion) {
            drawRing(canvas, radius, 1f - t, 4f, 0f, startAngle, 360f)
            return
        }
        // 1. Hand-drawn stroke fades while a perfect ring closes over it.
        val close = ease(interval(t, 0f, 0.35f))
        if (close < 1f) drawStroke(canvas, 1f - close)
        // 2. Pulse.
        val pulse = sin(PI * interval(t, 0.30f, 0.58f)).toFloat()
        // 3. Morph into the orb.
        val morph = easeInOut(interval(t, 0.55f, 1f))
        val orb = 26f * density
        val r = lerp(radius * (1f + 0.12f * pulse), orb, morph)
        if (morph < 1f) drawRing(canvas, r, 1f - morph * 0.4f, 5f + 3f * pulse, t, startAngle, 360f * close)
        if (morph > 0f) drawOrb(canvas, r, morph)
    }

    private fun drawStroke(canvas: Canvas, alpha: Float) {
        if (points.size < 2 || alpha <= 0f) return
        path.reset()
        path.moveTo(points[0].x, points[0].y)
        for (i in 1 until points.size) path.lineTo(points[i].x, points[i].y)
        // Soft glow: two wide translucent passes.
        glow.color = withAlpha(blue, 0.14f * alpha)
        glow.strokeWidth = 22f * density
        canvas.drawPath(path, glow)
        glow.color = withAlpha(pink, 0.18f * alpha)
        glow.strokeWidth = 12f * density
        canvas.drawPath(path, glow)
        // Tapered gradient core: thin and faint at the tail, bold at the finger.
        val n = points.size - 1
        for (i in 1..n) {
            val f = i.toFloat() / n
            core.strokeWidth = (2f + 5.5f * f) * density
            core.color = withAlpha(argb.evaluate(f, blue, pink) as Int, (0.3f + 0.7f * f) * alpha)
            canvas.drawLine(points[i - 1].x, points[i - 1].y, points[i].x, points[i].y, core)
        }
        val tip = points[n]
        fill.shader = null
        fill.color = withAlpha(pink, 0.35f * alpha)
        canvas.drawCircle(tip.x, tip.y, 9f * density, fill)
        fill.color = withAlpha(Color.WHITE, 0.95f * alpha)
        canvas.drawCircle(tip.x, tip.y, 3.5f * density, fill)
    }

    private fun drawRing(canvas: Canvas, r: Float, alpha: Float, width: Float, spin: Float, start: Float, sweep: Float) {
        if (alpha <= 0f || sweep <= 0f) return
        rect.set(cx - r, cy - r, cx + r, cy + r)
        glow.shader = null
        glow.color = withAlpha(blue, 0.22f * alpha)
        glow.strokeWidth = width * 4f * density
        canvas.drawArc(rect, start, sweep, false, glow)
        val sg = SweepGradient(cx, cy, intArrayOf(withAlpha(blue, alpha), withAlpha(pink, alpha), withAlpha(blue, alpha)), null)
        matrixRot.setRotate(start + 360f * spin, cx, cy)
        sg.setLocalMatrix(matrixRot)
        core.shader = sg
        core.strokeWidth = width * density
        canvas.drawArc(rect, start, sweep, false, core)
        core.shader = null
    }

    private fun drawOrb(canvas: Canvas, r: Float, a: Float) {
        fill.shader = null
        fill.color = withAlpha(pink, 0.22f * a)
        canvas.drawCircle(cx, cy, r * 1.9f, fill)
        fill.color = withAlpha(blue, 0.18f * a)
        canvas.drawCircle(cx, cy, r * 1.45f, fill)
        fill.shader = RadialGradient(
            cx - r * 0.3f, cy - r * 0.35f, r * 1.4f,
            intArrayOf(withAlpha(Color.WHITE, 0.95f * a), withAlpha(pink, a), withAlpha(blue, a)),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP
        )
        canvas.drawCircle(cx, cy, r, fill)
        fill.shader = null
    }

    private fun interval(t: Float, b: Float, e: Float) = ((t - b) / (e - b)).coerceIn(0f, 1f)
    private fun ease(x: Float) = DECEL.getInterpolation(x)
    private fun easeInOut(x: Float) = if (x < 0.5f) 4 * x * x * x else 1 - Math.pow((-2.0 * x + 2), 3.0).toFloat() / 2
    private fun lerp(a: Float, b: Float, f: Float) = a + (b - a) * f
    private fun withAlpha(color: Int, a: Float) =
        Color.argb((Color.alpha(color) * a.coerceIn(0f, 1f)).toInt(), Color.red(color), Color.green(color), Color.blue(color))

    companion object {
        private val DECEL = DecelerateInterpolator(2f)
    }
}
