package com.oneova.camerakit.ar

import android.graphics.PointF
import kotlin.math.atan2
import kotlin.math.hypot

/**
 * One tracked face in normalized preview space (0..1, already mirrored for
 * the front camera). Mirrors `TrackedFace` in
 * `lib/looks/ar/tracking/ar_tracking_models.dart`; the Dart side receives
 * exactly these values, so the preview overlay and the baked video agree.
 */
internal class ArFace(
    val leftEye: PointF,
    val rightEye: PointF,
    val noseTip: PointF,
    val forehead: PointF,
    val chin: PointF,
    val mouth: PointF,
    val upperLip: PointF,
    val lowerLip: PointF,
    val leftCheek: PointF,
    val rightCheek: PointF,
    val leftBlush: PointF,
    val rightBlush: PointF,
    val roll: Float,
    val yaw: Float,
    val pitch: Float,
    /** Keyed by the Dart `ArContour` names. */
    val contours: Map<String, List<PointF>>,
) {
    val width: Float get() = dist(leftCheek, rightCheek)
    val eyesCenter: PointF get() = lerp(leftEye, rightEye, 0.5f)

    /** Anchors in the order the Dart decoder reads them. */
    fun anchors(): List<PointF> = listOf(
        leftEye, rightEye, noseTip, forehead, chin, mouth,
        upperLip, lowerLip, leftCheek, rightCheek, leftBlush, rightBlush,
    )

    /** Exponential smoothing toward [next] (same as `TrackedFace.lerpTo`). */
    fun lerpTo(next: ArFace, t: Float): ArFace {
        fun l(a: PointF, b: PointF) = lerp(a, b, t)
        fun d(a: Float, b: Float) = a + (b - a) * t
        val merged = HashMap<String, List<PointF>>()
        for ((k, v) in next.contours) {
            val prev = contours[k]
            merged[k] = if (prev != null && prev.size == v.size) {
                List(v.size) { l(prev[it], v[it]) }
            } else {
                v
            }
        }
        return ArFace(
            l(leftEye, next.leftEye), l(rightEye, next.rightEye), l(noseTip, next.noseTip),
            l(forehead, next.forehead), l(chin, next.chin), l(mouth, next.mouth),
            l(upperLip, next.upperLip), l(lowerLip, next.lowerLip),
            l(leftCheek, next.leftCheek), l(rightCheek, next.rightCheek),
            l(leftBlush, next.leftBlush), l(rightBlush, next.rightBlush),
            d(roll, next.roll), d(yaw, next.yaw), d(pitch, next.pitch), merged,
        )
    }
}

/** Full/upper body and hand/wrist pose landmarks, normalized like [ArFace]. */
internal class ArBody(
    val leftShoulder: PointF,
    val rightShoulder: PointF,
    val leftHip: PointF?,
    val rightHip: PointF?,
    val leftElbow: PointF? = null,
    val rightElbow: PointF? = null,
    val leftWrist: PointF? = null,
    val rightWrist: PointF? = null,
    val leftAnkle: PointF? = null,
    val rightAnkle: PointF? = null,
) {
    val shoulderWidth: Float get() = dist(leftShoulder, rightShoulder)
    val shouldersCenter: PointF get() = lerp(leftShoulder, rightShoulder, 0.5f)
    val roll: Float get() = atan2(rightShoulder.y - leftShoulder.y, rightShoulder.x - leftShoulder.x)

    private fun lerpOpt(a: PointF?, b: PointF?, t: Float): PointF? =
        if (a != null && b != null) lerp(a, b, t) else b

    fun lerpTo(next: ArBody, t: Float) = ArBody(
        lerp(leftShoulder, next.leftShoulder, t),
        lerp(rightShoulder, next.rightShoulder, t),
        lerpOpt(leftHip, next.leftHip, t),
        lerpOpt(rightHip, next.rightHip, t),
        lerpOpt(leftElbow, next.leftElbow, t),
        lerpOpt(rightElbow, next.rightElbow, t),
        lerpOpt(leftWrist, next.leftWrist, t),
        lerpOpt(rightWrist, next.rightWrist, t),
        lerpOpt(leftAnkle, next.leftAnkle, t),
        lerpOpt(rightAnkle, next.rightAnkle, t),
    )
}

/**
 * Person mask in preview space (mirrored like the faces). [confidence] is
 * the temporally smoothed model output (0..255); [alpha] the soft-thresholded
 * matte the compositor uses (same curve as the Dart viewfinder).
 */
internal class ArMask(val width: Int, val height: Int, val confidence: ByteArray, val alpha: ByteArray)

/** Everything tracked on one analysis frame. */
internal class ArResult(
    val timestampNs: Long,
    val faces: List<ArFace>,
    val body: ArBody?,
    val mask: ArMask?,
    /** Scene brightness 0..1 (mean luma of the analysis frame), for light-aware effects. */
    val light: Float = 0.5f,
    /** Average scene colour (r, g, b scaled so the largest is 1), or null. */
    val tint: FloatArray? = null,
)

/** Which models the active effects need; models that are not needed are not run. */
internal data class ArNeeds(val face: Boolean, val mask: Boolean, val body: Boolean) {
    val any: Boolean get() = face || mask || body

    companion object {
        val NONE = ArNeeds(false, false, false)

        fun fromMap(m: Map<*, *>?) = ArNeeds(
            face = m?.get("face") == true,
            mask = m?.get("mask") == true,
            body = m?.get("body") == true,
        )
    }
}

internal fun lerp(a: PointF, b: PointF, t: Float) = PointF(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)

internal fun dist(a: PointF, b: PointF) = hypot(b.x - a.x, b.y - a.y)
