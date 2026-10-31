package com.oneova.camerakit.ar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import androidx.camera.core.AspectRatio
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.view.TextureRegistry
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The native AR camera, built like TikTok/Snap capture: one CameraX
 * session with separate use cases instead of one stream doing everything.
 *
 * - **Preview** at full resolution (1080p, 16:9) into [ArGlPipeline], which
 *   draws it into a Flutter texture and, while recording, composites the
 *   effects into the video encoder (so recording is full resolution too).
 * - **ImageAnalysis** at ~480p, KEEP_ONLY_LATEST, into [ArTracker]; only
 *   anchors, head pose and a 256-px mask go to Dart.
 * - **ImageCapture** for full-resolution stills (front camera mirrored like
 *   the preview).
 *
 * Owns its own lifecycle so the screen decides exactly when the camera runs.
 * All public methods are called on the main thread.
 */
internal class ArCameraSession(
    private val context: Context,
    textures: TextureRegistry,
    private val front: Boolean,
    needs: ArNeeds,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private class SessionLifecycle : LifecycleOwner {
        private val registry = LifecycleRegistry(this)
        override val lifecycle: Lifecycle get() = registry
        fun resume() { registry.currentState = Lifecycle.State.RESUMED }
        fun destroy() { registry.currentState = Lifecycle.State.DESTROYED }
    }

    private val main = Handler(Looper.getMainLooper())
    private val owner = SessionLifecycle()
    private val producer = textures.createSurfaceProducer()
    val textureId: Long get() = producer.id()

    private val pipeline = ArGlPipeline(producer) { size -> main.post { onPreviewSize(size) } }
    private val tracker = ArTracker { result, ms -> onTracked(result, ms) }
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor { r -> Thread(r, "OneovaArAnalysis") }
    private val stillExecutor: ExecutorService = Executors.newSingleThreadExecutor { r -> Thread(r, "OneovaArStill") }

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var useCases: List<UseCase> = emptyList()
    private var imageCapture: ImageCapture? = null
    private var previewSize: Size? = null
    private var onReady: ((Size?, String?) -> Unit)? = null
    private var closed = false

    // Tracking rate, measured on the worker thread.
    private var trackedFrames = 0
    private var trackWindowStart = 0L
    @Volatile private var trackingFps = 0.0

    init {
        tracker.needs = needs
        tracker.mirror = front
        pipeline.mirror = front
    }

    /** Binds the camera; [ready] gets the upright preview size or an error. */
    fun open(ready: (Size?, String?) -> Unit) {
        onReady = ready
        owner.resume()
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (closed) return@addListener
            try {
                provider = future.get()
                bind()
            } catch (e: Exception) {
                Log.e(TAG, "Camera unavailable", e)
                finishOpen(null, e.message ?: "camera_unavailable")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bind() {
        val p = provider ?: return
        val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
        val aspect = AspectRatioStrategy(AspectRatio.RATIO_16_9, AspectRatioStrategy.FALLBACK_RULE_AUTO)
        fun selectorFor(size: Size, rule: Int) = ResolutionSelector.Builder()
            .setAspectRatioStrategy(aspect)
            .setResolutionStrategy(ResolutionStrategy(size, rule))
            .build()

        val preview = Preview.Builder()
            .setResolutionSelector(selectorFor(Size(1920, 1080), ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
            .setTargetFrameRate(Range(30, 30))
            .build()
        preview.setSurfaceProvider(pipeline.executor) { request -> pipeline.provideSurface(request) }

        // Small, same aspect as the preview, so tracking maps 1:1 onto it.
        val analysis = ImageAnalysis.Builder()
            .setResolutionSelector(selectorFor(Size(854, 480), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()
        analysis.setAnalyzer(analysisExecutor, tracker)

        val capture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setAspectRatioStrategy(aspect)
                    .setResolutionStrategy(ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY)
                    .build(),
            )
            .build()

        p.unbind(*useCases.toTypedArray())
        camera = try {
            useCases = listOf(preview, analysis, capture)
            imageCapture = capture
            p.bindToLifecycle(owner, selector, preview, analysis, capture)
        } catch (e: IllegalArgumentException) {
            // Three streams not supported here: stills come from the preview instead.
            Log.w(TAG, "Preview + analysis + capture not supported; binding without capture", e)
            useCases = listOf(preview, analysis)
            imageCapture = null
            try {
                p.bindToLifecycle(owner, selector, preview, analysis)
            } catch (e2: Exception) {
                finishOpen(null, e2.message ?: "bind_failed")
                return
            }
        }
        Log.i(
            TAG,
            "AR camera bound: preview=${preview.resolutionInfo?.resolution} " +
                "analysis=${analysis.resolutionInfo?.resolution} capture=${imageCapture?.resolutionInfo?.resolution}",
        )
        // Fails if no preview frame arrives (camera taken by another app).
        main.postDelayed({ if (previewSize == null) finishOpen(null, "camera_timeout") }, 4000)
    }

    private fun onPreviewSize(size: Size) {
        if (closed) return
        previewSize = size
        tracker.previewAspect = size.width.toFloat() / size.height
        tracker.reset()
        if (onReady != null) {
            finishOpen(size, null)
        } else {
            emit(mapOf("type" to "previewSize", "width" to size.width, "height" to size.height))
        }
    }

    private fun finishOpen(size: Size?, error: String?) {
        val cb = onReady ?: return
        onReady = null
        cb(size, error)
    }

    // ── Tracking ───────────────────────────────────────────────────────────

    private fun onTracked(result: ArResult, ms: Double) {
        pipeline.onTracking(result)
        val now = SystemClock.elapsedRealtime()
        if (trackWindowStart == 0L) trackWindowStart = now
        trackedFrames++
        if (now - trackWindowStart >= 1000) {
            trackingFps = trackedFrames * 1000.0 / (now - trackWindowStart)
            trackedFrames = 0
            trackWindowStart = now
        }
        val event = encode(result, ms)
        main.post { if (!closed) emit(event) }
    }

    private fun encode(r: ArResult, ms: Double): Map<String, Any?> {
        val faces = r.faces.map { f ->
            val anchors = FloatArray(24)
            f.anchors().forEachIndexed { i, p ->
                anchors[i * 2] = p.x
                anchors[i * 2 + 1] = p.y
            }
            mapOf(
                "a" to anchors,
                "pose" to floatArrayOf(f.roll, f.yaw, f.pitch),
                "c" to f.contours.mapValues { (_, pts) ->
                    FloatArray(pts.size * 2).also { out ->
                        pts.forEachIndexed { i, p ->
                            out[i * 2] = p.x
                            out[i * 2 + 1] = p.y
                        }
                    }
                },
            )
        }
        val body = r.body?.let { b ->
            floatArrayOf(
                b.leftShoulder.x, b.leftShoulder.y, b.rightShoulder.x, b.rightShoulder.y,
                b.leftHip?.x ?: Float.NaN, b.leftHip?.y ?: Float.NaN,
                b.rightHip?.x ?: Float.NaN, b.rightHip?.y ?: Float.NaN,
            )
        }
        val mask = r.mask?.let { mapOf("w" to it.width, "h" to it.height, "c" to it.confidence) }
        return mapOf(
            "type" to "frame",
            "t" to r.timestampNs / 1_000_000L,
            "faces" to faces,
            "body" to body,
            "mask" to mask,
            "trackMs" to ms,
            "trackFps" to trackingFps,
            "previewFps" to pipeline.previewFps,
        )
    }

    fun setNeeds(needs: ArNeeds) {
        tracker.needs = needs
        if (!needs.any) pipeline.clearTracking()
    }

    // ── Scene for recording ────────────────────────────────────────────────

    fun setScene(map: Map<*, *>) {
        val effects = (map["effects"] as? List<*>)?.mapNotNull { (it as? Map<*, *>)?.let(ArEffectSpec::fromMap) }
            ?: emptyList()
        pipeline.retainImages(effects.map { it.id }.toSet())
        pipeline.setScene(
            ArScene(
                effects = effects,
                backgroundMode = (map["backgroundMode"] as? Number)?.toInt() ?: 0,
                blurSigma = (map["blurSigma"] as? Number)?.toFloat() ?: 14f,
                addYourself = map["addYourself"] == true,
                personOffsetX = (map["personOffsetX"] as? Number)?.toFloat() ?: 0f,
                personOffsetY = (map["personOffsetY"] as? Number)?.toFloat() ?: 0f,
                personScale = (map["personScale"] as? Number)?.toFloat() ?: 1f,
            ),
        )
    }

    fun putImage(id: String, image: Map<*, *>) {
        pipeline.putImage(id, bitmapFrom(image) ?: return)
    }

    fun setBackground(image: Map<*, *>?) {
        pipeline.setBackground(image?.let(::bitmapFrom))
    }

    fun setWorld(map: Map<*, *>) {
        pipeline.setWorld(
            map.entries.mapNotNull { (k, v) ->
                val l = (v as? List<*>)?.map { (it as Number).toFloat() } ?: return@mapNotNull null
                if (l.size < 4) null else (k as String) to ArWorldSpec(l[0], l[1], l[2], l[3])
            }.toMap(),
        )
    }

    /** `{w, h, rgba}` with premultiplied RGBA bytes (Flutter's rawRgba). */
    private fun bitmapFrom(m: Map<*, *>): Bitmap? {
        val w = (m["w"] as? Number)?.toInt() ?: return null
        val h = (m["h"] as? Number)?.toInt() ?: return null
        val bytes = m["rgba"] as? ByteArray ?: return null
        if (w <= 0 || h <= 0 || bytes.size < w * h * 4) return null
        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).apply {
            copyPixelsFromBuffer(ByteBuffer.wrap(bytes, 0, w * h * 4))
        }
    }

    // ── Controls ───────────────────────────────────────────────────────────

    fun setTorch(on: Boolean) {
        camera?.cameraControl?.enableTorch(on)
    }

    fun setFlashMode(mode: String) {
        imageCapture?.flashMode = when (mode) {
            "auto" -> ImageCapture.FLASH_MODE_AUTO
            "always" -> ImageCapture.FLASH_MODE_ON
            else -> ImageCapture.FLASH_MODE_OFF
        }
    }

    fun setZoom(ratio: Float) {
        val c = camera ?: return
        val state = c.cameraInfo.zoomState.value
        val min = state?.minZoomRatio ?: 1f
        val max = state?.maxZoomRatio ?: 1f
        c.cameraControl.setZoomRatio(ratio.coerceIn(min, max))
    }

    fun takePicture(file: File, done: (String?, String?) -> Unit) {
        val capture = imageCapture
        if (capture == null) {
            pipeline.snapshot(file) { ok -> main.post { if (ok) done(file.absolutePath, null) else done(null, "snapshot_failed") } }
            return
        }
        // Decoded and written upright (and mirrored for the front camera, like
        // the preview) with no EXIF transform, so every reader sees the same pixels.
        capture.takePicture(stillExecutor, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                val ok = runCatching {
                    val src = image.toBitmap()
                    val m = android.graphics.Matrix().apply {
                        postRotate(image.imageInfo.rotationDegrees.toFloat())
                        if (front) postScale(-1f, 1f)
                    }
                    val upright = Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
                    file.outputStream().use { upright.compress(Bitmap.CompressFormat.JPEG, 95, it) }
                    if (upright !== src) upright.recycle()
                    src.recycle()
                }.onFailure { Log.w(TAG, "Could not write the still", it) }.isSuccess
                image.close()
                main.post { if (ok) done(file.absolutePath, null) else done(null, "capture_failed") }
            }

            override fun onError(exception: ImageCaptureException) {
                Log.w(TAG, "Still capture failed; using the preview frame", exception)
                pipeline.snapshot(file) { ok ->
                    main.post { if (ok) done(file.absolutePath, null) else done(null, exception.message ?: "capture_failed") }
                }
            }
        })
    }

    fun startRecording(file: File, withAudio: Boolean, done: (String?) -> Unit) {
        val audio = withAudio && ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        pipeline.startRecording(file, audio) { err -> main.post { done(err) } }
    }

    fun stopRecording(done: (Long) -> Unit) {
        pipeline.stopRecording { ms -> main.post { done(ms) } }
    }

    fun stats(): Map<String, Any?> = mapOf(
        "previewFps" to pipeline.previewFps,
        "trackFps" to trackingFps,
        "previewWidth" to previewSize?.width,
        "previewHeight" to previewSize?.height,
        "recording" to pipeline.isRecording,
        "stillCapture" to (imageCapture != null),
    )

    fun close() {
        if (closed) return
        closed = true
        finishOpen(null, "closed")
        provider?.unbind(*useCases.toTypedArray())
        useCases = emptyList()
        owner.destroy()
        tracker.close()
        analysisExecutor.shutdown()
        stillExecutor.shutdown()
        pipeline.release()
        producer.release()
    }

    companion object {
        private const val TAG = "OneovaArCamera"
    }
}
