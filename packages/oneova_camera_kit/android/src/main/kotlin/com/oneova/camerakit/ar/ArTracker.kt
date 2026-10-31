package com.oneova.camerakit.ar

import android.graphics.PointF
import android.os.SystemClock
import android.util.Log
import androidx.annotation.OptIn
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.facemesh.FaceMesh
import com.google.mlkit.vision.facemesh.FaceMeshDetection
import com.google.mlkit.vision.facemesh.FaceMeshDetector
import com.google.mlkit.vision.facemesh.FaceMeshDetectorOptions
import com.google.mlkit.vision.facemesh.FaceMeshPoint
import com.google.mlkit.vision.pose.Pose
import com.google.mlkit.vision.pose.PoseDetection
import com.google.mlkit.vision.pose.PoseDetector
import com.google.mlkit.vision.pose.PoseLandmark
import com.google.mlkit.vision.pose.defaults.PoseDetectorOptions
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.SegmentationMask
import com.google.mlkit.vision.segmentation.Segmenter
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.atan2
import kotlin.math.roundToInt

/**
 * Tracks faces (468-point mesh), the person mask and shoulders on the small
 * ImageAnalysis stream, natively, so the Dart side only receives anchors,
 * head pose and a 256-px mask.
 *
 * The three ML Kit models run in parallel on the same frame. The frame is
 * held until all of them finish, so with KEEP_ONLY_LATEST CameraX simply
 * skips frames while tracking is busy instead of queueing them.
 *
 * Coordinates come back in the analysis image's upright pixels; they are
 * mapped into the preview's field of view (both streams are center crops of
 * the sensor, the preview possibly a narrower one) and mirrored for the
 * front camera, giving the normalized preview space the renderer uses.
 */
internal class ArTracker(private val onResult: (ArResult, Double) -> Unit) : ImageAnalysis.Analyzer {
    @Volatile var needs: ArNeeds = ArNeeds.NONE
    @Volatile var mirror = false

    /** Upright preview width / height; the field of view to map into. */
    @Volatile var previewAspect = 9f / 16f

    private val worker: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "OneovaArTracker").apply { priority = Thread.NORM_PRIORITY + 1 }
    }
    @Volatile private var closed = false

    private var meshDetector: FaceMeshDetector? = null
    private var segmenter: Segmenter? = null
    private var poseDetector: PoseDetector? = null

    // Smoothing state; only touched on [worker].
    private var lastFace: ArFace? = null
    private var lastBody: ArBody? = null
    private var lastConf: FloatArray? = null

    fun reset() {
        worker.execute {
            lastFace = null
            lastBody = null
            lastConf = null
        }
    }

    @OptIn(ExperimentalGetImage::class)
    override fun analyze(image: ImageProxy) {
        val n = needs
        val media = image.image
        if (closed || !n.any || media == null) {
            image.close()
            return
        }
        val started = SystemClock.elapsedRealtimeNanos()
        val rotation = image.imageInfo.rotationDegrees
        val input = try {
            InputImage.fromMediaImage(media, rotation)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Unsupported analysis frame", e)
            image.close()
            return
        }
        val upright = rotation == 90 || rotation == 270
        val uw = (if (upright) image.height else image.width).toFloat()
        val uh = (if (upright) image.width else image.height).toFloat()
        val space = FovSpace(uw, uh, previewAspect, mirror)

        val faceTask: Task<List<FaceMesh>>? = if (n.face) mesh().process(input) else null
        val maskTask: Task<SegmentationMask>? = if (n.mask) segmenter().process(input) else null
        val poseTask: Task<Pose>? = if (n.body) pose().process(input) else null
        val tasks = listOfNotNull<Task<*>>(faceTask, maskTask, poseTask)
        val timestamp = image.imageInfo.timestamp

        Tasks.whenAllComplete(tasks).addOnCompleteListener(worker) {
            try {
                if (closed) return@addOnCompleteListener
                val result = build(
                    timestamp,
                    space,
                    faceTask?.takeIf { it.isSuccessful }?.result,
                    maskTask?.takeIf { it.isSuccessful }?.result,
                    poseTask?.takeIf { it.isSuccessful }?.result,
                )
                onResult(result, (SystemClock.elapsedRealtimeNanos() - started) / 1e6)
            } catch (e: RuntimeException) {
                Log.w(TAG, "AR tracking frame failed", e)
            } finally {
                image.close()
            }
        }
    }

    fun close() {
        closed = true
        worker.execute {
            meshDetector?.close()
            segmenter?.close()
            poseDetector?.close()
            meshDetector = null
            segmenter = null
            poseDetector = null
        }
        worker.shutdown()
    }

    private fun mesh() = meshDetector ?: FaceMeshDetection.getClient(
        FaceMeshDetectorOptions.Builder().setUseCase(FaceMeshDetectorOptions.FACE_MESH).build(),
    ).also { meshDetector = it }

    private fun segmenter() = segmenter ?: Segmentation.getClient(
        SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.STREAM_MODE)
            .enableRawSizeMask()
            .build(),
    ).also { segmenter = it }

    private fun pose() = poseDetector ?: PoseDetection.getClient(
        PoseDetectorOptions.Builder().setDetectorMode(PoseDetectorOptions.STREAM_MODE).build(),
    ).also { poseDetector = it }

    private fun build(
        timestamp: Long,
        space: FovSpace,
        meshes: List<FaceMesh>?,
        seg: SegmentationMask?,
        pose: Pose?,
    ): ArResult {
        val faces = ArrayList<ArFace>(2)
        meshes?.take(2)?.forEach { m -> faceFromMesh(m, space)?.let(faces::add) }
        if (faces.isNotEmpty()) {
            val prev = lastFace
            if (prev != null && dist(prev.eyesCenter, faces[0].eyesCenter) < prev.width) {
                faces[0] = prev.lerpTo(faces[0], 0.55f)
            }
            lastFace = faces[0]
        } else if (meshes != null) {
            lastFace = null
        }

        var body = pose?.let { bodyFromPose(it, space) }
        if (body != null) {
            lastBody?.let { body = it.lerpTo(body!!, 0.5f) }
            lastBody = body
        }

        val mask = seg?.let { maskFrom(it, space) }
        return ArResult(timestamp, faces, body, mask)
    }

    // ── Face mesh → anchors (same mapping as the Dart ArTrackingService) ──

    private fun faceFromMesh(mesh: FaceMesh, space: FovSpace): ArFace? {
        val all = mesh.allPoints
        if (all.size < 468) return null
        val pts = arrayOfNulls<FaceMeshPoint>(468)
        for (p in all) if (p.index in 0 until 468) pts[p.index] = p
        if (pts.any { it == null }) return null

        fun n(i: Int) = space.map(pts[i]!!.position.x, pts[i]!!.position.y)
        fun z(i: Int) = space.z(pts[i]!!.position.z)
        fun mid(a: Int, b: Int) = lerp(n(a), n(b), 0.5f)

        val eyeA = mid(33, 133)
        val eyeB = mid(362, 263)
        val leftIsA = n(234).x <= n(454).x
        val lc = if (leftIsA) 234 else 454
        val rc = if (leftIsA) 454 else 234
        val le = if (eyeA.x <= eyeB.x) eyeA else eyeB
        val re = if (eyeA.x <= eyeB.x) eyeB else eyeA
        val blushA = n(50)
        val blushB = n(280)

        val yaw = atan2(z(rc) - z(lc), n(rc).x - n(lc).x)
        val pitch = atan2(z(152) - z(10), n(152).y - n(10).y)
        val roll = atan2(re.y - le.y, re.x - le.x)

        fun contour(type: Int) = mesh.getPoints(type).map { space.map(it.position.x, it.position.y) }
        val browA = contour(FaceMesh.LEFT_EYEBROW_TOP)
        val browB = contour(FaceMesh.RIGHT_EYEBROW_TOP)
        val eyeCA = contour(FaceMesh.LEFT_EYE)
        val eyeCB = contour(FaceMesh.RIGHT_EYE)
        val browsInOrder = isLeft(browA, browB)
        val eyesInOrder = isLeft(eyeCA, eyeCB)

        return ArFace(
            leftEye = le,
            rightEye = re,
            noseTip = n(1),
            forehead = n(10),
            chin = n(152),
            mouth = mid(13, 14),
            upperLip = n(13),
            lowerLip = n(14),
            leftCheek = n(lc),
            rightCheek = n(rc),
            leftBlush = if (blushA.x <= blushB.x) blushA else blushB,
            rightBlush = if (blushA.x <= blushB.x) blushB else blushA,
            roll = roll,
            yaw = yaw,
            pitch = pitch,
            contours = mapOf(
                "faceOval" to contour(FaceMesh.FACE_OVAL),
                "leftBrow" to if (browsInOrder) browA else browB,
                "rightBrow" to if (browsInOrder) browB else browA,
                "leftEye" to if (eyesInOrder) eyeCA else eyeCB,
                "rightEye" to if (eyesInOrder) eyeCB else eyeCA,
                "lipsOuter" to ring(contour(FaceMesh.UPPER_LIP_TOP), contour(FaceMesh.LOWER_LIP_BOTTOM)),
                "lipsInner" to ring(contour(FaceMesh.UPPER_LIP_BOTTOM), contour(FaceMesh.LOWER_LIP_TOP)),
            ),
        )
    }

    private fun bodyFromPose(pose: Pose, space: FovSpace): ArBody? {
        fun p(type: Int): PointF? {
            val l = pose.getPoseLandmark(type) ?: return null
            if (l.inFrameLikelihood < 0.5f) return null
            return space.map(l.position.x, l.position.y)
        }
        val a = p(PoseLandmark.LEFT_SHOULDER) ?: return null
        val b = p(PoseLandmark.RIGHT_SHOULDER) ?: return null
        val ha = p(PoseLandmark.LEFT_HIP)
        val hb = p(PoseLandmark.RIGHT_HIP)
        val aLeft = a.x <= b.x
        return ArBody(
            leftShoulder = if (aLeft) a else b,
            rightShoulder = if (aLeft) b else a,
            leftHip = if (aLeft) ha else hb,
            rightHip = if (aLeft) hb else ha,
        )
    }

    // ── Segmentation → preview-space mask ──

    private fun maskFrom(seg: SegmentationMask, space: FovSpace): ArMask {
        val mw = seg.width
        val mh = seg.height
        val src = seg.buffer.apply { rewind() }.order(ByteOrder.nativeOrder()).asFloatBuffer()
        val outH = MASK_HEIGHT
        val outW = (MASK_HEIGHT * previewAspect).roundToInt().coerceIn(16, MASK_HEIGHT * 2)
        val conf = FloatArray(outW * outH)
        val prev = lastConf?.takeIf { it.size == conf.size }
        val confBytes = ByteArray(conf.size)
        val alpha = ByteArray(conf.size)
        val sx = mw / space.uprightWidth
        val sy = mh / space.uprightHeight
        for (y in 0 until outH) {
            val ny = (y + 0.5f) / outH
            for (x in 0 until outW) {
                val nx = (x + 0.5f) / outW
                // Preview-space point → analysis pixel → mask cell (bilinear).
                val ux = space.unmapX(nx) * sx - 0.5f
                val uy = space.unmapY(ny) * sy - 0.5f
                var v = bilinear(src, mw, mh, ux, uy)
                val i = y * outW + x
                if (prev != null) v = prev[i] * 0.35f + v * 0.65f
                conf[i] = v
                confBytes[i] = (v * 255f).roundToInt().coerceIn(0, 255).toByte()
                // Soft threshold so edges stay feathered but the background drops out.
                val a = ((v - 0.35f) / 0.4f).coerceIn(0f, 1f)
                alpha[i] = (a * a * (3 - 2 * a) * 255f).roundToInt().toByte()
            }
        }
        lastConf = conf
        return ArMask(outW, outH, confBytes, alpha)
    }

    private fun bilinear(buf: java.nio.FloatBuffer, w: Int, h: Int, x: Float, y: Float): Float {
        val cx = x.coerceIn(0f, (w - 1).toFloat())
        val cy = y.coerceIn(0f, (h - 1).toFloat())
        val x0 = cx.toInt()
        val y0 = cy.toInt()
        val x1 = minOf(x0 + 1, w - 1)
        val y1 = minOf(y0 + 1, h - 1)
        val fx = cx - x0
        val fy = cy - y0
        val a = buf.get(y0 * w + x0)
        val b = buf.get(y0 * w + x1)
        val c = buf.get(y1 * w + x0)
        val d = buf.get(y1 * w + x1)
        return (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy
    }

    private fun isLeft(a: List<PointF>, b: List<PointF>) =
        a.isEmpty() || b.isEmpty() || a.sumOf { it.x.toDouble() } / a.size <= b.sumOf { it.x.toDouble() } / b.size

    /** Joins a top and bottom lip edge into one closed ring. */
    private fun ring(top: List<PointF>, bottom: List<PointF>): List<PointF> {
        if (top.isEmpty() || bottom.isEmpty()) return emptyList()
        val tail = if (dist(top.last(), bottom.first()) < dist(top.last(), bottom.last())) bottom else bottom.reversed()
        return top + tail
    }

    /**
     * Maps upright analysis pixels into the preview's normalized field of
     * view: the preview is the center crop of the analysis image that has
     * the preview's aspect ratio.
     */
    private class FovSpace(val uprightWidth: Float, val uprightHeight: Float, aspect: Float, val mirror: Boolean) {
        private val cropW: Float
        private val cropH: Float
        private val ox: Float
        private val oy: Float

        init {
            if (uprightWidth / uprightHeight > aspect) {
                cropH = uprightHeight
                cropW = uprightHeight * aspect
            } else {
                cropW = uprightWidth
                cropH = uprightWidth / aspect
            }
            ox = (uprightWidth - cropW) / 2
            oy = (uprightHeight - cropH) / 2
        }

        fun map(x: Float, y: Float): PointF {
            val nx = (x - ox) / cropW
            return PointF(if (mirror) 1 - nx else nx, (y - oy) / cropH)
        }

        /** Mesh z shares the x pixel scale; normalize it like x. */
        fun z(z: Float) = z / cropW

        fun unmapX(nx: Float) = ox + (if (mirror) 1 - nx else nx) * cropW
        fun unmapY(ny: Float) = oy + ny * cropH
    }

    companion object {
        private const val TAG = "OneovaArTracker"
        const val MASK_HEIGHT = 256
    }
}
