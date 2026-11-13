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

    /**
     * [worker] that drops work after [close]: ML Kit can finish a frame after
     * the camera closed, and posting its result to a shut-down pool threw
     * RejectedExecutionException on the main thread and killed the app.
     */
    private val safeWorker = java.util.concurrent.Executor { r ->
        try {
            worker.execute(r)
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            Log.d(TAG, "Tracking result dropped after close")
        }
    }

    private var meshDetector: FaceMeshDetector? = null
    private var segmenter: Segmenter? = null
    private var poseDetector: PoseDetector? = null

    // Per-person face tracks with stable ids; only touched on [worker].
    private class Track(val id: Int, var face: ArFace, var seenNs: Long)
    private val tracks = ArrayList<Track>(MAX_FACES)
    private var nextTrackId = 0

    // Auto-optimised scheduling: when a frame takes longer than the camera's
    // frame time, segmentation and pose run on alternate frames (the last
    // result is reused between) so face tracking keeps ~30 fps.
    @Volatile private var lastTrackMs = 0.0

    /** Heat guard from the camera screen: heavy models on alternate frames. */
    @Volatile var throttle = false
    private var frameNo = 0L
    private var lastMask: ArMask? = null

    // Smoothing state; only touched on [worker].
    private var lastFace: ArFace? = null
    private var lastBody: ArBody? = null
    private var lastConf: FloatArray? = null

    fun reset() {
        safeWorker.execute {
            lastFace = null
            lastBody = null
            lastConf = null
            lastMask = null
            tracks.clear()
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

        val heavy = lastTrackMs > 30.0 || throttle
        val alternate = heavy && (frameNo++ % 2L == 1L)
        val light = meanLuma(media)
        val tint = meanTint(media)
        val faceTask: Task<List<FaceMesh>>? = if (n.face) mesh().process(input) else null
        val maskTask: Task<SegmentationMask>? = if (n.mask && !(alternate && lastMask != null)) segmenter().process(input) else null
        val poseTask: Task<Pose>? = if (n.body && !(alternate && lastBody != null)) pose().process(input) else null
        val tasks = listOfNotNull<Task<*>>(faceTask, maskTask, poseTask)
        val timestamp = image.imageInfo.timestamp

        Tasks.whenAllComplete(tasks).addOnCompleteListener(safeWorker) {
            try {
                if (closed) return@addOnCompleteListener
                val result = build(
                    timestamp,
                    space,
                    faceTask?.takeIf { it.isSuccessful }?.result,
                    maskTask?.takeIf { it.isSuccessful }?.result,
                    poseTask?.takeIf { it.isSuccessful }?.result,
                    reuseMask = n.mask && maskTask == null,
                    reuseBody = n.body && poseTask == null,
                    light = light,
                    tint = tint,
                )
                val ms = (SystemClock.elapsedRealtimeNanos() - started) / 1e6
                lastTrackMs = lastTrackMs * 0.8 + ms * 0.2
                onResult(result, ms)
            } catch (e: RuntimeException) {
                Log.w(TAG, "AR tracking frame failed", e)
            } finally {
                image.close()
            }
        }
    }

    fun close() {
        closed = true
        safeWorker.execute {
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
        reuseMask: Boolean = false,
        reuseBody: Boolean = false,
        light: Float = 0.5f,
        tint: FloatArray? = null,
    ): ArResult {
        val faces = if (meshes != null) trackFaces(timestamp, meshes.take(MAX_FACES).mapNotNull { faceFromMesh(it, space) })
            else tracks.map { it.face }
        lastFace = faces.firstOrNull()

        var body = pose?.let { bodyFromPose(it, space) }
        if (body != null) {
            lastBody?.let { prev ->
                // Same speed-adaptive smoothing as faces.
                val speed = dist(prev.leftShoulder, body!!.leftShoulder) / maxOf(0.05f, prev.shoulderWidth)
                body = prev.lerpTo(body!!, (0.6f + speed * 6f).coerceIn(0.6f, 1f))
            }
            lastBody = body
        } else if (reuseBody) {
            body = lastBody
        } else if (pose != null) {
            lastBody = null
        }

        val mask = seg?.let { maskFrom(it, space) } ?: if (reuseMask) lastMask else null
        if (seg != null) lastMask = mask
        return ArResult(timestamp, faces, body, mask, light, tint)
    }

    /**
     * Matches detections to the previous people (nearest eyes within a face
     * width), smooths each by how fast it moves — still faces don't jitter,
     * fast turns don't lag — keeps a lost face for [HOLD_NS] so a missed
     * frame doesn't make effects blink, and snaps when a face reappears.
     */
    private fun trackFaces(ts: Long, detected: List<ArFace>): List<ArFace> {
        val used = HashSet<Int>()
        for (f in detected) {
            val match = tracks.filter { it.id !in used }
                .minByOrNull { dist(it.face.eyesCenter, f.eyesCenter) }
                ?.takeIf { dist(it.face.eyesCenter, f.eyesCenter) < it.face.width * 1.2f && ts - it.seenNs < HOLD_NS * 2 }
            if (match != null) {
                val speed = dist(match.face.eyesCenter, f.eyesCenter) / maxOf(0.02f, match.face.width)
                // Light smoothing at rest, none while moving: effects stay glued
                // to the face instead of trailing behind a turn.
                val t = (0.6f + speed * 8f).coerceIn(0.6f, 1f)
                match.face = match.face.lerpTo(f, t)
                match.seenNs = ts
                used += match.id
            } else if (tracks.size < MAX_FACES * 2) {
                val tr = Track(nextTrackId++, f, ts)
                tracks += tr
                used += tr.id
            }
        }
        // Faces at the frame edge or very close are the ones the detector
        // drops for a frame or two: hold them longer so effects don't blink.
        tracks.removeAll {
            val c = it.face.eyesCenter
            val edgy = c.x < 0.15f || c.x > 0.85f || c.y < 0.12f || c.y > 0.88f || it.face.width > 0.5f
            it.id !in used && ts - it.seenNs > (if (edgy) HOLD_NS * 3 else HOLD_NS)
        }
        // Stable order (first person seen first) for per-person effects.
        return tracks.sortedBy { it.id }.take(MAX_FACES).map { it.face }
    }

    /** Mean luma of the frame from a sparse grid of the Y plane. */
    private fun meanLuma(img: android.media.Image): Float = runCatching {
        val p = img.planes[0]
        val buf = p.buffer
        val w = img.width
        val h = img.height
        var sum = 0L
        var n = 0
        var y = h / 16
        while (y < h) {
            var x = w / 16
            while (x < w) {
                sum += buf.get(y * p.rowStride + x * p.pixelStride).toInt() and 0xFF
                n++
                x += w / 8
            }
            y += h / 8
        }
        if (n == 0) 0.5f else sum / (n * 255f)
    }.getOrDefault(0.5f)

    /** Average colour of the frame from a sparse grid of the chroma planes. */
    private fun meanTint(img: android.media.Image): FloatArray? = runCatching {
        val y = img.planes[0]
        val u = img.planes[1]
        val v = img.planes[2]
        val cw = img.width / 2
        val ch = img.height / 2
        var sy = 0L; var su = 0L; var sv = 0L; var n = 0
        var r = ch / 16
        while (r < ch) {
            var c = cw / 16
            while (c < cw) {
                sy += y.buffer.get(r * 2 * y.rowStride + c * 2 * y.pixelStride).toInt() and 0xFF
                su += u.buffer.get(r * u.rowStride + c * u.pixelStride).toInt() and 0xFF
                sv += v.buffer.get(r * v.rowStride + c * v.pixelStride).toInt() and 0xFF
                n++
                c += cw / 8
            }
            r += ch / 8
        }
        if (n == 0) return@runCatching null
        val yy = sy.toFloat() / n
        val uu = su.toFloat() / n - 128f
        val vv = sv.toFloat() / n - 128f
        val rgb = floatArrayOf(yy + 1.402f * vv, yy - 0.344f * uu - 0.714f * vv, yy + 1.772f * uu).map { it.coerceAtLeast(1f) }
        val m = rgb.max()
        floatArrayOf(rgb[0] / m, rgb[1] / m, rgb[2] / m)
    }.getOrNull()

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
            if (l.inFrameLikelihood < 0.45f) return null
            return space.map(l.position.x, l.position.y)
        }
        val a = p(PoseLandmark.LEFT_SHOULDER) ?: return null
        val b = p(PoseLandmark.RIGHT_SHOULDER) ?: return null
        val ha = p(PoseLandmark.LEFT_HIP)
        val hb = p(PoseLandmark.RIGHT_HIP)
        val ea = p(PoseLandmark.LEFT_ELBOW)
        val eb = p(PoseLandmark.RIGHT_ELBOW)
        val wa = p(PoseLandmark.LEFT_WRIST)
        val wb = p(PoseLandmark.RIGHT_WRIST)
        val aa = p(PoseLandmark.LEFT_ANKLE)
        val ab = p(PoseLandmark.RIGHT_ANKLE)
        val aLeft = a.x <= b.x
        return ArBody(
            leftShoulder = if (aLeft) a else b,
            rightShoulder = if (aLeft) b else a,
            leftHip = if (aLeft) ha else hb,
            rightHip = if (aLeft) hb else ha,
            leftElbow = if (aLeft) ea else eb,
            rightElbow = if (aLeft) eb else ea,
            leftWrist = if (aLeft) wa else wb,
            rightWrist = if (aLeft) wb else wa,
            leftAnkle = if (aLeft) aa else ab,
            rightAnkle = if (aLeft) ab else aa,
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
                // Motion-aware smoothing: steady areas keep most of the last
                // frame (no edge flicker); where the mask moves it follows at
                // once (no ghosting behind fast motion).
                if (prev != null) {
                    val d = kotlin.math.abs(v - prev[i])
                    val keep = if (d < 0.12f) 0.6f else if (d < 0.3f) 0.3f else 0.08f
                    v = prev[i] * keep + v * (1f - keep)
                }
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
        // 384 rows keeps hair and fingers; the GPU refines edges further.
        const val MASK_HEIGHT = 384
        const val MAX_FACES = 3
        const val HOLD_NS = 150_000_000L
    }
}
