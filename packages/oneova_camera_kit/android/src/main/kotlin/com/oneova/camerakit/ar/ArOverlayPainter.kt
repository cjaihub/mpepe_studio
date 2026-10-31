package com.oneova.camerakit.ar

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** Makeup colors (ARGB) and opacities; opacity 0 means "not drawn". */
internal class ArMakeupSpec(
    val lipColor: Int, val lipOpacity: Float,
    val blushColor: Int, val blushOpacity: Float,
    val eyeColor: Int, val eyeOpacity: Float, val eyeGlow: Float,
    val linerColor: Int, val linerOpacity: Float,
    val browColor: Int, val browOpacity: Float,
) {
    companion object {
        fun fromMap(m: Map<*, *>?): ArMakeupSpec {
            fun c(k: String) = (m?.get(k) as? Number)?.toInt() ?: 0
            fun d(k: String) = ((m?.get(k) as? Number)?.toFloat() ?: 0f).coerceIn(0f, 1f)
            return ArMakeupSpec(
                c("lipColor"), d("lipOpacity"), c("blushColor"), d("blushOpacity"),
                c("eyeColor"), d("eyeOpacity"), d("eyeGlow"), c("linerColor"), d("linerOpacity"),
                c("browColor"), d("browOpacity"),
            )
        }
    }
}

/** One active effect, as sent by `LiveArController` (mirrors `ArEffect`). */
internal class ArEffectSpec(
    val id: String,
    val kind: String,
    val anchor: String,
    val scale: Float,
    val offsetX: Float,
    val offsetY: Float,
    val makeup: ArMakeupSpec,
) {
    val isWorld: Boolean get() = kind == "sprite" && anchor == "world"

    companion object {
        fun fromMap(m: Map<*, *>) = ArEffectSpec(
            id = m["id"] as String,
            kind = m["kind"] as? String ?: "sprite",
            anchor = m["anchor"] as? String ?: "face",
            scale = (m["scale"] as? Number)?.toFloat() ?: 1f,
            offsetX = (m["offsetX"] as? Number)?.toFloat() ?: 0f,
            offsetY = (m["offsetY"] as? Number)?.toFloat() ?: 0f,
            makeup = ArMakeupSpec.fromMap(m["makeup"] as? Map<*, *>),
        )
    }
}

/** A world-anchored sticker's placement in normalized preview space. */
internal class ArWorldSpec(val x: Float, val y: Float, val scale: Float, val rotation: Float)

/**
 * Kotlin port of `ArEffectPainter.paintEffects`
 * (`lib/looks/ar/render/ar_effect_painter.dart`): same anchors, sizes,
 * offsets and head-pose perspective, so a recorded video matches what the
 * Dart overlay showed on the preview.
 *
 * It draws onto a transparent bitmap that the GL compositor lays over the
 * camera frame, so blend modes that need the camera pixels underneath
 * (multiply lips/brows, color-blended iris, additive glow) are drawn as
 * normal alpha blends at matching strength.
 */
internal object ArOverlayPainter {
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val dst = RectF()
    private val matrix = Matrix()
    private val values = FloatArray(9)

    fun paint(
        canvas: Canvas,
        w: Float,
        h: Float,
        result: ArResult?,
        effects: List<ArEffectSpec>,
        images: Map<String, Bitmap>,
        world: Map<String, ArWorldSpec>,
    ) {
        val faces = result?.faces ?: emptyList()
        val body = result?.body
        // Makeup first so sprites (glasses, masks) sit on top of it.
        for (e in effects) {
            if (e.kind != "makeup") continue
            for (f in faces) paintMakeup(canvas, w, h, f, e.makeup)
        }
        for (e in effects) {
            if (e.kind != "sprite") continue
            val img = images[e.id] ?: continue
            if (e.isWorld) {
                paintWorld(canvas, w, h, img, world[e.id] ?: ArWorldSpec(0.5f, 0.45f, 1f, 0f), e.scale)
                continue
            }
            if (e.anchor == "torso") {
                if (faces.isNotEmpty() || body != null) paintSprite(canvas, w, h, img, e, faces.firstOrNull(), body)
                continue
            }
            for (f in faces) paintSprite(canvas, w, h, img, e, f, null)
        }
    }

    private fun paintWorld(canvas: Canvas, w: Float, h: Float, img: Bitmap, p: ArWorldSpec, scale: Float) {
        val sw = w * 0.42f * scale * p.scale
        val sh = sw * img.height / img.width
        canvas.save()
        canvas.translate(p.x * w, p.y * h)
        canvas.rotate(Math.toDegrees(p.rotation.toDouble()).toFloat())
        dst.set(-sw / 2, -sh / 2, sw / 2, sh / 2)
        canvas.drawBitmap(img, null, dst, bitmapPaint)
        canvas.restore()
    }

    private fun paintSprite(
        canvas: Canvas,
        w: Float,
        h: Float,
        img: Bitmap,
        e: ArEffectSpec,
        f: ArFace?,
        body: ArBody?,
    ) {
        fun px(n: PointF) = PointF(n.x * w, n.y * h)
        fun add(a: PointF, b: PointF, k: Float) = PointF(a.x + b.x * k, a.y + b.y * k)

        var center: PointF
        val refW: Float
        val roll: Float
        var yaw = 0f
        var pitch = 0f
        var baseWidth: Float

        if (e.anchor == "torso" && body != null) {
            refW = body.shoulderWidth * w
            roll = body.roll
            val down = PointF(-sin(roll), cos(roll))
            center = add(px(body.shouldersCenter), down, refW * 0.55f)
            baseWidth = 1.45f
        } else {
            val face = f ?: return
            refW = face.width * w
            roll = face.roll
            yaw = face.yaw.coerceIn(-0.9f, 0.9f)
            pitch = face.pitch.coerceIn(-0.7f, 0.7f)
            val up = PointF(sin(roll), -cos(roll))
            when (e.anchor) {
                "eyes" -> { center = px(face.eyesCenter); baseWidth = 1.0f }
                "forehead" -> { center = add(px(face.forehead), up, refW * 0.05f); baseWidth = 0.8f }
                "headTop" -> { center = add(px(face.forehead), up, refW * 0.42f); baseWidth = 1.25f }
                "hair" -> { center = add(px(face.forehead), up, refW * 0.1f); baseWidth = 1.6f }
                "nose" -> { center = px(face.noseTip); baseWidth = 0.4f }
                "mouth" -> { center = px(face.mouth); baseWidth = 0.5f }
                "chin" -> { center = lerp(px(face.mouth), px(face.chin), 0.45f); baseWidth = 0.95f }
                "face" -> { center = lerp(px(face.forehead), px(face.chin), 0.5f); baseWidth = 1.15f }
                "neck" -> { center = add(px(face.chin), up, -refW * 0.35f); baseWidth = 0.8f }
                "torso" -> {
                    // No pose yet: estimate the chest from the face.
                    center = add(px(face.chin), up, -refW * 1.5f)
                    baseWidth = 2.6f
                    yaw = 0f
                    pitch = 0f
                }
                else -> return
            }
        }

        val right = PointF(cos(roll), sin(roll))
        val down = PointF(-sin(roll), cos(roll))
        center = add(add(center, right, e.offsetX * refW), down, e.offsetY * refW)
        val sw = refW * baseWidth * e.scale
        if (sw < 4) return
        val sh = sw * img.height / img.width

        canvas.save()
        canvas.translate(center.x, center.y)
        canvas.rotate(Math.toDegrees(roll.toDouble()).toFloat())
        // Matrix4.identity()..setEntry(3, 2, k)..rotateX(pitch)..rotateY(-yaw),
        // projected to 2D: x' = cy·x, y' = sp·sy·x + cp·y, w = 1 + k(sp·y − cp·sy·x).
        val k = 1f / (refW * 2.4f)
        val cy = cos(yaw)
        val sy = sin(-yaw)
        val cp = cos(pitch)
        val sp = sin(pitch)
        values[0] = cy; values[1] = 0f; values[2] = 0f
        values[3] = sp * sy; values[4] = cp; values[5] = 0f
        values[6] = -k * cp * sy; values[7] = k * sp; values[8] = 1f
        matrix.setValues(values)
        canvas.concat(matrix)
        dst.set(-sw / 2, -sh / 2, sw / 2, sh / 2)
        canvas.drawBitmap(img, null, dst, bitmapPaint)
        canvas.restore()
    }

    private fun path(pts: List<PointF>, w: Float, h: Float, close: Boolean = true): Path {
        val p = Path()
        if (pts.isEmpty()) return p
        p.moveTo(pts[0].x * w, pts[0].y * h)
        for (i in 1 until pts.size) p.lineTo(pts[i].x * w, pts[i].y * h)
        if (close) p.close()
        return p
    }

    private fun alpha(color: Int, a: Float): Int =
        ((a.coerceIn(0f, 1f) * 255f).roundToInt() shl 24) or (color and 0xFFFFFF)

    private fun blur(radius: Float) =
        if (radius >= 0.5f) BlurMaskFilter(radius, BlurMaskFilter.Blur.NORMAL) else null

    private fun paintMakeup(canvas: Canvas, w: Float, h: Float, f: ArFace, m: ArMakeupSpec) {
        val refW = f.width * w
        if (refW < 8) return

        // Lips: outer ring minus inner ring so an open mouth stays clear.
        val outer = f.contours["lipsOuter"] ?: emptyList()
        if (m.lipOpacity > 0 && outer.size > 6) {
            val lips = path(outer, w, h).apply { fillType = Path.FillType.EVEN_ODD }
            val inner = f.contours["lipsInner"] ?: emptyList()
            if (inner.size > 6) lips.addPath(path(inner, w, h))
            // Dart: multiply at 0.55 + normal at 0.35 over the skin.
            canvas.drawPath(lips, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = alpha(m.lipColor, m.lipOpacity * 0.6f)
                maskFilter = blur(refW * 0.006f)
            })
        }

        if (m.blushOpacity > 0) {
            for (c in listOf(f.leftBlush, f.rightBlush)) {
                val ox = c.x * w
                val oy = c.y * h
                val r = refW * 0.17f
                canvas.drawCircle(ox, oy, r, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    shader = RadialGradient(
                        ox, oy, r,
                        intArrayOf(alpha(m.blushColor, m.blushOpacity * 0.5f), alpha(m.blushColor, 0f)),
                        null, Shader.TileMode.CLAMP,
                    )
                })
            }
        }

        for (key in listOf("leftEye", "rightEye")) {
            val eye = f.contours[key] ?: emptyList()
            if (eye.size < 6) continue
            val p = path(eye, w, h)
            val bounds = RectF().also { p.computeBounds(it, true) }
            val cx = bounds.centerX()
            val cyy = bounds.centerY()
            if (m.eyeOpacity > 0) {
                // Tinted iris: a disc at the eye center, clipped to the eye opening.
                canvas.save()
                canvas.clipPath(p)
                val r = bounds.height() * 0.62f
                if (r > 0.5f) {
                    canvas.drawCircle(cx, cyy, r, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        shader = RadialGradient(
                            cx, cyy, r,
                            intArrayOf(
                                alpha(m.eyeColor, m.eyeOpacity * 0.55f),
                                alpha(m.eyeColor, m.eyeOpacity * 0.35f),
                                alpha(m.eyeColor, 0f),
                            ),
                            floatArrayOf(0f, 0.7f, 1f), Shader.TileMode.CLAMP,
                        )
                    })
                }
                canvas.restore()
            }
            if (m.eyeGlow > 0) {
                canvas.drawCircle(cx, cyy, bounds.width() * 0.45f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = alpha(m.eyeColor, 0.9f * m.eyeGlow)
                    maskFilter = blur(refW * 0.04f)
                })
                canvas.drawPath(p, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeWidth = refW * 0.012f
                    color = alpha(m.eyeColor, m.eyeGlow)
                    maskFilter = blur(refW * 0.01f)
                })
            }
            if (m.linerOpacity > 0) {
                val cyNorm = cyy / h
                val upper = eye.filter { it.y <= cyNorm }.sortedBy { it.x }
                if (upper.size > 2) {
                    canvas.drawPath(path(upper, w, h, close = false), Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeCap = Paint.Cap.ROUND
                        strokeWidth = refW * 0.014f
                        color = alpha(m.linerColor, m.linerOpacity)
                    })
                }
            }
        }

        if (m.browOpacity > 0) {
            for (key in listOf("leftBrow", "rightBrow")) {
                val brow = f.contours[key] ?: emptyList()
                if (brow.size < 3) continue
                canvas.drawPath(path(brow, w, h, close = false), Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeCap = Paint.Cap.ROUND
                    strokeWidth = refW * 0.03f
                    color = alpha(m.browColor, m.browOpacity * 0.4f)
                    maskFilter = blur(refW * 0.006f)
                })
            }
        }
    }
}
