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

/**
 * Makeup colors (ARGB) and amounts; opacity 0 means "not drawn". Mirrors
 * `ArMakeup.toNative()` in `lib/looks/ar/models/ar_effect.dart`.
 */
internal class ArMakeupSpec(
    val lipColor: Int, val lipOpacity: Float, val lipGloss: Float,
    val blushColor: Int, val blushOpacity: Float,
    val eyeColor: Int, val eyeOpacity: Float, val eyeGlow: Float,
    val shadowColor: Int, val shadowOpacity: Float,
    val linerColor: Int, val linerOpacity: Float, val linerWidth: Float, val linerWing: Float,
    val browColor: Int, val browOpacity: Float, val browWidth: Float,
    val foundationColor: Int, val foundationOpacity: Float,
    val contourOpacity: Float, val highlightOpacity: Float,
    val smoothing: Float,
) {
    companion object {
        fun fromMap(m: Map<*, *>?): ArMakeupSpec {
            fun c(k: String) = (m?.get(k) as? Number)?.toInt() ?: 0
            fun d(k: String, def: Float = 0f) = ((m?.get(k) as? Number)?.toFloat() ?: def).coerceIn(0f, 1f)
            return ArMakeupSpec(
                c("lipColor"), d("lipOpacity"), d("lipGloss"),
                c("blushColor"), d("blushOpacity"),
                c("eyeColor"), d("eyeOpacity"), d("eyeGlow"),
                c("shadowColor"), d("shadowOpacity"),
                c("linerColor"), d("linerOpacity"), d("linerWidth", 0.35f), d("linerWing"),
                c("browColor"), d("browOpacity"), d("browWidth", 0.5f),
                c("foundationColor"), d("foundationOpacity"),
                d("contourOpacity"), d("highlightOpacity"),
                d("smoothing"),
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
        perPerson: Boolean = false,
    ) {
        val faces = result?.faces ?: emptyList()
        val body = result?.body
        // Light-aware stickers (same curve as the Dart ArEffectPainter).
        val k = ((0.62f + (result?.light ?: 0.5f) * 0.6f)).coerceIn(0.7f, 1.08f)
        bitmapPaint.colorFilter = android.graphics.ColorMatrixColorFilter(
            android.graphics.ColorMatrix().apply { setScale(k, k, k, 1f) },
        )
        val faceSprites = effects.filter { it.kind == "sprite" && !it.isWorld && it.anchor != "torso" && images.containsKey(it.id) }
        val split = perPerson && faceSprites.size > 1 && faces.size > 1
        // Makeup first so sprites (glasses, masks) sit on top of it.
        for (e in effects) {
            if (e.kind != "makeup") continue
            for (f in faces) paintMakeup(canvas, w, h, f, e.makeup)
        }
        // CapCut/TikTok-grade procedural VFX (body aura, cyber HUD, soul clone, hand energy).
        for (e in effects) {
            if (e.kind != "vfx") continue
            paintVfx(canvas, w, h, e.id, faces, body)
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
            for ((i, f) in faces.withIndex()) {
                if (split && faceSprites[i % faceSprites.size].id != e.id) continue
                paintSprite(canvas, w, h, img, e, f, null)
            }
        }
        bitmapPaint.colorFilter = null
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

    /** Scales a contour about its centroid (gives eyes/lips a safety margin). */
    private fun grow(pts: List<PointF>, k: Float): List<PointF> {
        var cx = 0f
        var cy = 0f
        for (p in pts) { cx += p.x; cy += p.y }
        cx /= pts.size
        cy /= pts.size
        return pts.map { PointF(cx + (it.x - cx) * k, cy + (it.y - cy) * k) }
    }

    /** Face oval minus eyes and lips (even-odd), like `ArEffectPainter.skinPath`. */
    fun skinPath(f: ArFace, w: Float, h: Float): Path? {
        val oval = f.contours["faceOval"] ?: return null
        if (oval.size < 10) return null
        val p = path(oval, w, h).apply { fillType = Path.FillType.EVEN_ODD }
        for (key in listOf("leftEye", "rightEye", "lipsOuter")) {
            val c = f.contours[key] ?: continue
            if (c.size > 5) p.addPath(path(grow(c, 1.25f), w, h))
        }
        return p
    }

    private fun upperLid(eye: List<PointF>): List<PointF> {
        val cy = eye.sumOf { it.y.toDouble() }.toFloat() / eye.size
        return eye.filter { it.y <= cy }.sortedBy { it.x }
    }

    private fun paintMakeup(canvas: Canvas, w: Float, h: Float, f: ArFace, m: ArMakeupSpec) {
        val refW = f.width * w
        if (refW < 8) return
        fun px(n: PointF) = PointF(n.x * w, n.y * h)
        val roll = f.roll
        val upX = sin(roll)
        val upY = -cos(roll)
        val oval = f.contours["faceOval"] ?: emptyList()
        val ovalPath = if (oval.size > 10) path(oval, w, h) else null

        if (m.foundationOpacity > 0) {
            skinPath(f, w, h)?.let {
                canvas.drawPath(it, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = alpha(m.foundationColor, m.foundationOpacity * 0.42f)
                    maskFilter = blur(refW * 0.025f)
                })
            }
        }

        if (m.contourOpacity > 0 && ovalPath != null) {
            val shade = 0xFF5A3A2A.toInt()
            canvas.save()
            canvas.clipPath(ovalPath)
            canvas.drawPath(ovalPath, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = refW * 0.14f
                color = alpha(shade, m.contourOpacity * 0.32f)
                maskFilter = blur(refW * 0.05f)
            })
            for ((i, cheek) in listOf(f.leftCheek, f.rightCheek).withIndex()) {
                val a = px(cheek)
                val b = px(f.mouth)
                val cx = a.x + (b.x - a.x) * 0.3f - upX * refW * 0.02f
                val cy = a.y + (b.y - a.y) * 0.3f - upY * refW * 0.02f
                canvas.save()
                canvas.translate(cx, cy)
                canvas.rotate(Math.toDegrees((roll + if (i == 0) 0.35f else -0.35f).toDouble()).toFloat())
                canvas.drawOval(RectF(-refW * 0.16f, -refW * 0.045f, refW * 0.16f, refW * 0.045f), Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = alpha(shade, m.contourOpacity * 0.3f)
                    maskFilter = blur(refW * 0.04f)
                })
                canvas.restore()
            }
            canvas.restore()
        }

        if (m.highlightOpacity > 0) {
            val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = alpha(0xFFFFF4E6.toInt(), m.highlightOpacity * 0.38f)
                maskFilter = blur(refW * 0.03f)
                strokeCap = Paint.Cap.ROUND
            }
            val top = px(f.eyesCenter)
            val nose = px(f.noseTip)
            canvas.drawLine(top.x, top.y, top.x + (nose.x - top.x) * 0.8f, top.y + (nose.y - top.y) * 0.8f,
                Paint(glow).apply { strokeWidth = refW * 0.05f; style = Paint.Style.STROKE })
            for ((b, e) in listOf(f.leftBlush to f.leftEye, f.rightBlush to f.rightEye)) {
                val p = lerp(px(b), px(e), 0.45f)
                canvas.drawCircle(p.x, p.y, refW * 0.06f, glow)
            }
            val fh = px(f.forehead)
            canvas.drawCircle(fh.x - upX * refW * 0.12f, fh.y - upY * refW * 0.12f, refW * 0.07f, glow)
            val ch = lerp(px(f.lowerLip), px(f.chin), 0.65f)
            canvas.drawCircle(ch.x, ch.y, refW * 0.04f, glow)
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

        val noseX = f.noseTip.x * w
        for (key in listOf("leftEye", "rightEye")) {
            val eye = f.contours[key] ?: emptyList()
            if (eye.size < 6) continue
            val p = path(eye, w, h)
            val bounds = RectF().also { p.computeBounds(it, true) }
            val cx = bounds.centerX()
            val cyy = bounds.centerY()
            val lid = upperLid(eye).map { px(it) }

            if (m.shadowOpacity > 0 && lid.size > 2) {
                val lift = bounds.height() * 1.5f + refW * 0.02f
                val shadow = Path().apply {
                    moveTo(lid[0].x, lid[0].y)
                    for (i in 1 until lid.size) lineTo(lid[i].x, lid[i].y)
                    for (i in lid.indices.reversed()) {
                        val t = sin(Math.PI.toFloat() * i / (lid.size - 1))
                        val k = lift * (0.35f + 0.65f * t)
                        lineTo(lid[i].x + upX * k, lid[i].y + upY * k)
                    }
                    close()
                }
                canvas.drawPath(shadow, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = alpha(m.shadowColor, m.shadowOpacity * 0.55f)
                    maskFilter = blur(refW * 0.018f)
                })
            }

            if (m.eyeOpacity > 0) {
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
                    // Realistic dual catchlight reflections on the iris.
                    canvas.drawCircle(
                        cx - r * 0.28f, cyy - r * 0.25f, r * 0.18f,
                        Paint(Paint.ANTI_ALIAS_FLAG).apply { color = alpha(0xFFFFFFFF.toInt(), m.eyeOpacity * 0.55f) },
                    )
                    canvas.drawCircle(
                        cx + r * 0.22f, cyy + r * 0.20f, r * 0.09f,
                        Paint(Paint.ANTI_ALIAS_FLAG).apply { color = alpha(0xFFFFFFFF.toInt(), m.eyeOpacity * 0.35f) },
                    )
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
            if (m.linerOpacity > 0 && lid.size > 2) {
                val sw = refW * (0.006f + 0.02f * m.linerWidth)
                val liner = Path().apply {
                    moveTo(lid[0].x, lid[0].y)
                    for (i in 1 until lid.size) lineTo(lid[i].x, lid[i].y)
                }
                canvas.drawPath(liner, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    style = Paint.Style.STROKE
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                    strokeWidth = sw
                    color = alpha(m.linerColor, m.linerOpacity)
                })
                if (m.linerWing > 0) {
                    val first = lid.first()
                    val last = lid.last()
                    val outerIsFirst = kotlin.math.abs(first.x - noseX) > kotlin.math.abs(last.x - noseX)
                    val outer = if (outerIsFirst) first else last
                    val outward = if (outerIsFirst) -1f else 1f
                    val dx = cos(roll) * outward * 0.85f + upX * 0.5f
                    val dy = sin(roll) * outward * 0.85f + upY * 0.5f
                    val len = refW * 0.1f * m.linerWing
                    canvas.drawPath(Path().apply {
                        moveTo(outer.x - upX * sw * 0.5f, outer.y - upY * sw * 0.5f)
                        lineTo(outer.x + dx * len, outer.y + dy * len)
                        lineTo(outer.x + upX * sw, outer.y + upY * sw)
                        close()
                    }, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = alpha(m.linerColor, m.linerOpacity) })
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
                    strokeWidth = refW * (0.015f + 0.035f * m.browWidth)
                    color = alpha(m.browColor, m.browOpacity * 0.4f)
                    maskFilter = blur(refW * 0.006f)
                })
            }
        }

        // Lips: outer ring minus inner ring so an open mouth stays clear.
        val outer = f.contours["lipsOuter"] ?: emptyList()
        if (m.lipOpacity > 0 && outer.size > 6) {
            val lips = path(outer, w, h).apply { fillType = Path.FillType.EVEN_ODD }
            val inner = f.contours["lipsInner"] ?: emptyList()
            if (inner.size > 6) lips.addPath(path(inner, w, h))
            canvas.drawPath(lips, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = alpha(m.lipColor, m.lipOpacity * 0.6f)
                maskFilter = blur(refW * 0.006f)
            })
            if (m.lipGloss > 0) {
                val bottom = outer.minByOrNull { dist(it, f.chin) } ?: f.lowerLip
                val c = lerp(px(f.lowerLip), px(bottom), 0.45f)
                canvas.save()
                canvas.clipPath(lips)
                canvas.translate(c.x, c.y)
                canvas.rotate(Math.toDegrees(roll.toDouble()).toFloat())
                canvas.drawOval(RectF(-refW * 0.08f, -refW * 0.015f, refW * 0.08f, refW * 0.015f), Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    color = alpha(0xFFFFFFFF.toInt(), 0.5f * m.lipGloss)
                    maskFilter = blur(refW * 0.008f)
                })
                canvas.restore()
            }
        }
    }

    private fun paintVfx(
        canvas: Canvas,
        w: Float,
        h: Float,
        id: String,
        faces: List<ArFace>,
        body: ArBody?,
    ) {
        fun px(n: PointF) = PointF(n.x * w, n.y * h)
        val pink = 0xFFFF2D87.toInt()
        val blue = 0xFF0C4FA8.toInt()
        val cyan = 0xFF38BDF8.toInt()
        when (id.removePrefix("builtin_")) {
            "vfx_neon_aura" -> {
                for (f in faces) {
                    val oval = f.contours["faceOval"] ?: continue
                    if (oval.size < 10) continue
                    val p = path(grow(oval, 1.08f), w, h)
                    val refW = f.width * w
                    canvas.drawPath(p, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = refW * 0.045f
                        color = alpha(pink, 0.75f)
                        maskFilter = blur(refW * 0.04f)
                    })
                    canvas.drawPath(p, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = refW * 0.014f
                        color = 0xFFFFFFFF.toInt()
                    })
                }
                if (body != null) {
                    val ls = px(body.leftShoulder)
                    val rs = px(body.rightShoulder)
                    val sw = dist(ls, rs).coerceAtLeast(w * 0.15f)
                    val auraPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeCap = Paint.Cap.ROUND
                        strokeJoin = Paint.Join.ROUND
                        strokeWidth = sw * 0.08f
                        color = alpha(blue, 0.85f)
                        maskFilter = blur(sw * 0.05f)
                    }
                    val corePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeCap = Paint.Cap.ROUND
                        strokeWidth = sw * 0.022f
                        color = alpha(cyan, 0.95f)
                    }
                    val skeleton = Path().apply {
                        moveTo(ls.x, ls.y)
                        lineTo(rs.x, rs.y)
                        body.leftElbow?.let { le ->
                            val ple = px(le)
                            moveTo(ls.x, ls.y); lineTo(ple.x, ple.y)
                            body.leftWrist?.let { lw -> val plw = px(lw); lineTo(plw.x, plw.y) }
                        }
                        body.rightElbow?.let { re ->
                            val pre = px(re)
                            moveTo(rs.x, rs.y); lineTo(pre.x, pre.y)
                            body.rightWrist?.let { rw -> val prw = px(rw); lineTo(prw.x, prw.y) }
                        }
                        if (body.leftHip != null && body.rightHip != null) {
                            val lh = px(body.leftHip)
                            val rh = px(body.rightHip)
                            moveTo(ls.x, ls.y); lineTo(lh.x, lh.y); lineTo(rh.x, rh.y); lineTo(rs.x, rs.y)
                        }
                    }
                    canvas.drawPath(skeleton, auraPaint)
                    canvas.drawPath(skeleton, corePaint)
                }
            }
            "vfx_cyber_hud" -> {
                for (f in faces) {
                    val refW = f.width * w
                    if (refW < 12f) continue
                    val hudStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = (refW * 0.01f).coerceAtLeast(1.5f)
                        color = alpha(cyan, 0.85f)
                    }
                    for (key in listOf("faceOval", "leftEye", "rightEye", "leftBrow", "rightBrow", "lipsOuter")) {
                        val pts = f.contours[key] ?: continue
                        if (pts.size > 3) canvas.drawPath(path(pts, w, h, close = key != "leftBrow" && key != "rightBrow"), hudStroke)
                    }
                    for (eye in listOf(f.leftEye, f.rightEye)) {
                        val ep = px(eye)
                        canvas.drawCircle(ep.x, ep.y, refW * 0.14f, Paint(hudStroke).apply { color = alpha(pink, 0.8f) })
                        canvas.drawCircle(ep.x, ep.y, refW * 0.025f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = alpha(pink, 0.95f) })
                    }
                }
            }
            "vfx_angel_glow" -> {
                for (f in faces) {
                    val refW = f.width * w
                    val fh = px(f.forehead)
                    val upX = sin(f.roll)
                    val upY = -cos(f.roll)
                    val hx = fh.x + upX * refW * 0.36f
                    val hy = fh.y + upY * refW * 0.36f
                    canvas.save()
                    canvas.translate(hx, hy)
                    canvas.rotate(Math.toDegrees(f.roll.toDouble()).toFloat())
                    val haloRect = RectF(-refW * 0.48f, -refW * 0.13f, refW * 0.48f, refW * 0.13f)
                    canvas.drawOval(haloRect, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = refW * 0.08f
                        color = alpha(0xFFFFE57F.toInt(), 0.75f)
                        maskFilter = blur(refW * 0.05f)
                    })
                    canvas.drawOval(haloRect, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = refW * 0.024f
                        color = 0xFFFFFFFF.toInt()
                    })
                    canvas.restore()
                }
            }
            "vfx_soul_clone" -> {
                for (f in faces) {
                    val oval = f.contours["faceOval"] ?: continue
                    if (oval.size < 10) continue
                    val refW = f.width * w
                    for ((dx, col) in listOf(-refW * 0.28f to pink, refW * 0.28f to blue)) {
                        canvas.save()
                        canvas.translate(dx, -refW * 0.06f)
                        val p = path(grow(oval, 1.05f), w, h)
                        canvas.drawPath(p, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                            style = Paint.Style.STROKE
                            strokeWidth = refW * 0.03f
                            color = alpha(col, 0.7f)
                            maskFilter = blur(refW * 0.025f)
                        })
                        for (key in listOf("leftEye", "rightEye", "lipsOuter")) {
                            val c = f.contours[key] ?: continue
                            if (c.size > 4) {
                                canvas.drawPath(path(c, w, h), Paint(Paint.ANTI_ALIAS_FLAG).apply {
                                    style = Paint.Style.STROKE
                                    strokeWidth = refW * 0.015f
                                    color = alpha(col, 0.8f)
                                })
                            }
                        }
                        canvas.restore()
                    }
                }
            }
            "vfx_hand_sparks" -> {
                val points = mutableListOf<PointF>()
                body?.leftWrist?.let { points.add(px(it)) }
                body?.rightWrist?.let { points.add(px(it)) }
                if (points.isEmpty()) {
                    for (f in faces) {
                        points.add(px(f.leftEye))
                        points.add(px(f.rightEye))
                    }
                }
                val r = w * 0.09f
                for ((idx, pt) in points.withIndex()) {
                    val col = if (idx % 2 == 0) pink else blue
                    canvas.drawCircle(pt.x, pt.y, r, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        shader = RadialGradient(
                            pt.x, pt.y, r,
                            intArrayOf(0xFFFFFFFF.toInt(), alpha(col, 0.85f), alpha(col, 0f)),
                            floatArrayOf(0f, 0.45f, 1f),
                            Shader.TileMode.CLAMP,
                        )
                    })
                    canvas.drawCircle(pt.x, pt.y, r * 0.65f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        style = Paint.Style.STROKE
                        strokeWidth = w * 0.008f
                        color = 0xFFFFFFFF.toInt()
                    })
                }
            }
        }
    }
}
