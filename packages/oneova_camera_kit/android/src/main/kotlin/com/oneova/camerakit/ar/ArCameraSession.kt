package com.oneova.camerakit.ar

import android.Manifest
import android.annotation.SuppressLint
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CameraMetadata
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import androidx.camera.camera2.interop.Camera2CameraControl
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.CaptureRequestOptions
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.AspectRatio
import androidx.camera.core.CameraInfo
import androidx.camera.core.ConcurrentCamera
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.SurfaceOrientedMeteringPointFactory
import androidx.camera.core.UseCaseGroup
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
import java.util.concurrent.TimeUnit

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
    /** 4:3 like the stock camera's photo mode; 16:9 for video. */
    private val aspect43: Boolean = false,
    /** "1080p30" (default), "1080p60" or "4k30" (video). */
    private val quality: String = "1080p30",
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

    /** Dual mode: both cameras bound together (concurrent camera). */
    private var dualOn = false
    private var secondCamera: Camera? = null
    private var aeLocked = false

    /** Low-light boost: auto exposure may drop to 10 fps for a brighter image. */
    private var lowLight = false

    fun setLowLight(on: Boolean) {
        lowLight = on
        applyManual(manual)
    }
    private var manual = ManualSettings()

    /** Manual sensor settings; null fields stay automatic. */
    private data class ManualSettings(
        val iso: Int? = null,
        val exposureNs: Long? = null,
        val awb: Int? = null,
        val focus: Float? = null,
    )

    // Tracking rate, measured on the worker thread.
    private var trackedFrames = 0
    private var trackWindowStart = 0L
    @Volatile private var trackingFps = 0.0

    private var requestedNeeds = needs
    private var imageAnalysis: ImageAnalysis? = null

    /** Surface.ROTATION_* of the phone (landscape saving). */
    private var deviceRotation = android.view.Surface.ROTATION_0

    fun setDeviceRotation(rotation: Int) {
        deviceRotation = rotation
        imageCapture?.targetRotation = rotation
        pipeline.orientationHint = when (rotation) {
            android.view.Surface.ROTATION_90 -> 270
            android.view.Surface.ROTATION_270 -> 90
            android.view.Surface.ROTATION_180 -> 180
            else -> 0
        }
    }

    /** True while another app records from the microphone. */
    fun micBusy(): Boolean = runCatching {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        am.activeRecordingConfigurations.isNotEmpty()
    }.getOrDefault(false)

    /** PowerManager thermal status (0 none … 6 shutdown), -1 unknown. */
    fun thermalStatus(): Int = if (android.os.Build.VERSION.SDK_INT >= 29) {
        (context.getSystemService(Context.POWER_SERVICE) as android.os.PowerManager).currentThermalStatus
    } else -1

    private var soundsLoaded = false
    private val sounds by lazy {
        soundsLoaded = true
        android.media.MediaActionSound()
    }
    private var audioFocusReq: android.media.AudioFocusRequest? = null

    /** Claims Android audio focus so external players/assistants yield to the camera. */
    private fun claimAudioFocus(exclusive: Boolean) {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        runCatching {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioFocusReq?.let { am.abandonAudioFocusRequest(it) }
            val gain = if (exclusive) {
                android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE
            } else {
                android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            }
            val attrs = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_MOVIE)
                .build()
            val req = android.media.AudioFocusRequest.Builder(gain)
                .setAudioAttributes(attrs)
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener { }
                .build()
            audioFocusReq = req
            am.requestAudioFocus(req)
        }
    }

    private fun releaseAudioFocus() {
        if (android.os.Build.VERSION.SDK_INT < 26) return
        runCatching {
            val am = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audioFocusReq?.let { am.abandonAudioFocusRequest(it) }
            audioFocusReq = null
        }
    }

    fun playSound(kind: String) {
        runCatching {
            sounds.play(
                when (kind) {
                    "start" -> android.media.MediaActionSound.START_VIDEO_RECORDING
                    "stop" -> android.media.MediaActionSound.STOP_VIDEO_RECORDING
                    else -> android.media.MediaActionSound.SHUTTER_CLICK
                },
            )
        }
    }

    /** Heat guard: tracking on alternate frames only. */
    fun setThrottle(on: Boolean) {
        tracker.throttle = on
    }

    init {
        tracker.needs = needs
        tracker.mirror = front
        pipeline.mirror = front
    }

    /** Binds the camera; [ready] gets the upright preview size or an error. */
    fun open(ready: (Size?, String?) -> Unit) {
        onReady = ready
        claimAudioFocus(exclusive = false)
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
        if (dualOn && bindDual(p)) return
        val leavingDual = secondCamera != null || runCatching { p.isConcurrentCameraModeOn }.getOrDefault(false)
        dualOn = false
        secondCamera = null
        pipeline.setDual(null)
        tracker.needs = requestedNeeds
        if (leavingDual) p.unbindAll()
        val selector = if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
        val aspect = AspectRatioStrategy(if (aspect43) AspectRatio.RATIO_4_3 else AspectRatio.RATIO_16_9, AspectRatioStrategy.FALLBACK_RULE_AUTO)
        val previewTarget = when {
            aspect43 -> Size(1440, 1080)
            quality == "4k30" -> Size(3840, 2160)
            else -> Size(1920, 1080)
        }
        val fps = if (quality == "1080p60" && !aspect43) 60 else 30
        fun selectorFor(size: Size, rule: Int) = ResolutionSelector.Builder()
            .setAspectRatioStrategy(aspect)
            .setResolutionStrategy(ResolutionStrategy(size, rule))
            .build()

        val preview = Preview.Builder()
            .setResolutionSelector(selectorFor(previewTarget, ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
            .setTargetFrameRate(Range(fps, fps))
            .build()
        pipeline.recordFps = fps
        preview.setSurfaceProvider(pipeline.executor) { request -> pipeline.provideSurface(request) }

        // Small, same aspect as the preview, so tracking maps 1:1 onto it.
        val analysis = ImageAnalysis.Builder()
            // 640×360 is plenty for face mesh / segmentation and about twice
            // as fast as 960×540 on mid-range phones (lower tracking latency).
            .setResolutionSelector(selectorFor(if (aspect43) Size(640, 480) else Size(640, 360), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()
        // No effect needs tracking: no analysis frames at all (idle power).
        if (requestedNeeds.any) analysis.setAnalyzer(analysisExecutor, tracker)
        imageAnalysis = analysis

        // ~12 MP 4:3 stills. Zero-shutter-lag capped stills at 5 MP on the
        // TECNO; with the direct JPEG write, minimum latency is already fast.
        val capture = ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
            .setTargetRotation(deviceRotation)
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY)
                    .setResolutionStrategy(ResolutionStrategy(Size(4000, 3000), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER))
                    .build(),
            )
            .build()

        p.unbind(*useCases.toTypedArray())
        // Photo mode with nothing tracked: preview + still only, so the
        // camera can give full-sensor stills (a third YUV stream caps JPEG at
        // the guaranteed combination, 5 MP on the TECNO). Analysis is bound
        // again as soon as an effect needs tracking (setNeeds).
        analysisBound = !aspect43 || requestedNeeds.any
        camera = try {
            imageCapture = capture
            if (analysisBound) {
                useCases = listOf(preview, analysis, capture)
                p.bindToLifecycle(owner, selector, preview, analysis, capture)
            } else {
                useCases = listOf(preview, capture)
                p.bindToLifecycle(owner, selector, preview, capture)
            }
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
                b.leftElbow?.x ?: Float.NaN, b.leftElbow?.y ?: Float.NaN,
                b.rightElbow?.x ?: Float.NaN, b.rightElbow?.y ?: Float.NaN,
                b.leftWrist?.x ?: Float.NaN, b.leftWrist?.y ?: Float.NaN,
                b.rightWrist?.x ?: Float.NaN, b.rightWrist?.y ?: Float.NaN,
                b.leftAnkle?.x ?: Float.NaN, b.leftAnkle?.y ?: Float.NaN,
                b.rightAnkle?.x ?: Float.NaN, b.rightAnkle?.y ?: Float.NaN,
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
            "light" to r.light.toDouble(),
            "tint" to r.tint,
        )
    }

    private var analysisBound = true

    fun setNeeds(needs: ArNeeds) {
        val wasAny = requestedNeeds.any
        requestedNeeds = needs
        if (dualOn) return
        tracker.needs = needs
        // Photo mode binds analysis only while tracking (full-size stills otherwise).
        if (aspect43 && needs.any != analysisBound && provider != null && !closed) {
            bind()
            return
        }
        // Analysis frames only while something is tracked (idle power).
        if (needs.any && !wasAny) imageAnalysis?.setAnalyzer(analysisExecutor, tracker)
        if (!needs.any && wasAny) imageAnalysis?.clearAnalyzer()
        if (!needs.any) pipeline.clearTracking()
    }

    // ── Scene for recording ────────────────────────────────────────────────

    fun setScene(map: Map<*, *>) {
        val effects = (map["effects"] as? List<*>)?.mapNotNull { (it as? Map<*, *>)?.let(ArEffectSpec::fromMap) }
            ?: emptyList()
        pipeline.retainImages(effects.map { it.id }.toSet())
        pipeline.set3d(
            (map["effects"] as? List<*>).orEmpty().mapNotNull { raw ->
                val m = raw as? Map<*, *> ?: return@mapNotNull null
                if (m["kind"] != "model3d") return@mapNotNull null
                val model = m["model"] as? Map<*, *>
                fun f(k: String, d: Float = 0f) = (model?.get(k) as? Number)?.toFloat() ?: d
                Ar3dSpec(
                    id = m["id"] as? String ?: return@mapNotNull null,
                    anchor = m["anchor"] as? String ?: "eyes",
                    scale = (m["scale"] as? Number)?.toFloat() ?: 1f,
                    offsetX = (m["offsetX"] as? Number)?.toFloat() ?: 0f,
                    offsetY = (m["offsetY"] as? Number)?.toFloat() ?: 0f,
                    offsetZ = f("offsetZ"),
                    rotX = f("rotX"),
                    rotY = f("rotY"),
                    rotZ = f("rotZ"),
                )
            },
        )
        pipeline.setScene(
            ArScene(
                effects = effects,
                backgroundMode = (map["backgroundMode"] as? Number)?.toInt() ?: 0,
                blurSigma = (map["blurSigma"] as? Number)?.toFloat() ?: 14f,
                addYourself = map["addYourself"] == true,
                personOffsetX = (map["personOffsetX"] as? Number)?.toFloat() ?: 0f,
                personOffsetY = (map["personOffsetY"] as? Number)?.toFloat() ?: 0f,
                personScale = (map["personScale"] as? Number)?.toFloat() ?: 1f,
                outfit = (map["outfit"] as? List<*>)?.mapNotNull { (it as? Number)?.toFloat() }?.toFloatArray(),
                perPerson = map["perPerson"] == true,
            ),
        )
    }

    /** A downloaded glTF binary for a 3D effect; [done] gets null or an error. */
    fun putModel(id: String, path: String, done: (String?) -> Unit) {
        pipeline.putModel(id, path) { err -> main.post { done(err) } }
    }

    fun putImage(id: String, image: Map<*, *>) {
        pipeline.putImage(id, bitmapFrom(image) ?: return)
    }

    fun setBackgroundVideo(path: String?) {
        pipeline.setBackgroundVideo(path)
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

    // ── Dual camera ────────────────────────────────────────────────────────

    /** A front + back pair this phone can stream at the same time, or null. */
    private fun concurrentPair(p: ProcessCameraProvider): Pair<CameraInfo, CameraInfo>? {
        val combos = runCatching { p.availableConcurrentCameraInfos }.getOrNull() ?: return null
        for (combo in combos) {
            val f = combo.firstOrNull { it.lensFacing == CameraSelector.LENS_FACING_FRONT }
            val b = combo.firstOrNull { it.lensFacing == CameraSelector.LENS_FACING_BACK }
            if (f != null && b != null) return if (front) f to b else b to f
        }
        return null
    }

    fun dualSupported(): Boolean {
        val p = provider ?: return false
        return concurrentPair(p) != null
    }

    private fun bindDual(p: ProcessCameraProvider): Boolean {
        val (mainInfo, otherInfo) = concurrentPair(p) ?: return false
        val aspect = AspectRatioStrategy(AspectRatio.RATIO_16_9, AspectRatioStrategy.FALLBACK_RULE_AUTO)
        // Concurrent streams are limited to about 720p per camera.
        fun preview() = Preview.Builder()
            .setResolutionSelector(
                ResolutionSelector.Builder()
                    .setAspectRatioStrategy(aspect)
                    .setResolutionStrategy(ResolutionStrategy(Size(1280, 720), ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER))
                    .build(),
            )
            .build()
        val mainPreview = preview()
        mainPreview.setSurfaceProvider(pipeline.executor) { request -> pipeline.provideSurface(request) }
        val otherPreview = preview()
        val otherFront = otherInfo.lensFacing == CameraSelector.LENS_FACING_FRONT
        otherPreview.setSurfaceProvider(pipeline.executor) { request -> pipeline.provideSecondSurface(request, otherFront) }
        p.unbindAll()
        return try {
            val cc: ConcurrentCamera = p.bindToLifecycle(
                listOf(
                    ConcurrentCamera.SingleCameraConfig(
                        mainInfo.cameraSelector, UseCaseGroup.Builder().addUseCase(mainPreview).build(), owner,
                    ),
                    ConcurrentCamera.SingleCameraConfig(
                        otherInfo.cameraSelector, UseCaseGroup.Builder().addUseCase(otherPreview).build(), owner,
                    ),
                ),
            )
            camera = cc.cameras.getOrNull(0)
            secondCamera = cc.cameras.getOrNull(1)
            useCases = listOf(mainPreview, otherPreview)
            imageCapture = null
            tracker.needs = ArNeeds.NONE
            pipeline.clearTracking()
            Log.i(TAG, "Dual camera bound: main=${mainPreview.resolutionInfo?.resolution} second=${otherPreview.resolutionInfo?.resolution}")
            true
        } catch (e: Exception) {
            Log.w(TAG, "Concurrent cameras could not be bound", e)
            runCatching { p.unbindAll() }
            false
        }
    }

    /** Turns dual mode on or off; [done] gets null or an error code. */
    fun setDual(on: Boolean, layout: ArGlPipeline.DualLayout?, done: (String?) -> Unit) {
        val p = provider
        if (p == null) {
            done("not_open")
            return
        }
        if (on && concurrentPair(p) == null) {
            done("dual_unsupported")
            return
        }
        pipeline.setDual(if (on) layout else null)
        if (on == dualOn) {
            done(null)
            return
        }
        dualOn = on
        try {
            bind()
            if (on && !dualOn) done("dual_bind_failed") else done(null)
        } catch (e: Exception) {
            done(e.message ?: "bind_failed")
        }
    }

    fun setDualLayout(layout: ArGlPipeline.DualLayout) {
        if (dualOn) pipeline.setDual(layout)
    }

    // ── Focus & exposure ───────────────────────────────────────────────────

    /**
     * Focus and meter at ([x], [y]) in the upright, displayed preview (0..1,
     * already mirrored for the front camera). [lock] keeps AF/AE there until
     * [unlock] (long-press AE/AF lock); otherwise it returns to continuous
     * after a few seconds.
     */
    @SuppressLint("RestrictedApi")
    fun focusAt(x: Float, y: Float, lock: Boolean, done: (Boolean) -> Unit) {
        val c = camera ?: return done(false)
        val ux = (if (front) 1 - x else x).coerceIn(0f, 1f)
        val uy = y.coerceIn(0f, 1f)
        val rot = (imagePreviewRotation() % 360 + 360) % 360
        // Upright → sensor buffer: rotate back by the preview rotation.
        val (sx, sy) = when (rot) {
            90 -> uy to 1 - ux
            180 -> 1 - ux to 1 - uy
            270 -> 1 - uy to ux
            else -> ux to uy
        }
        val point = SurfaceOrientedMeteringPointFactory(1f, 1f).createPoint(sx, sy, 0.12f)
        val builder = FocusMeteringAction.Builder(
            point,
            FocusMeteringAction.FLAG_AF or FocusMeteringAction.FLAG_AE or FocusMeteringAction.FLAG_AWB,
        )
        if (lock) builder.disableAutoCancel() else builder.setAutoCancelDuration(4, TimeUnit.SECONDS)
        if (manual.focus != null) manual = manual.copy(focus = null).also { applyManual(it) }
        val future = c.cameraControl.startFocusAndMetering(builder.build())
        future.addListener({
            val ok = runCatching { future.get().isFocusSuccessful }.getOrDefault(false)
            if (lock) setAeLock(true)
            done(ok)
        }, ContextCompat.getMainExecutor(context))
        if (!lock && aeLocked) setAeLock(false)
    }

    private fun imagePreviewRotation(): Int =
        (useCases.firstOrNull { it is Preview } as? Preview)?.resolutionInfo?.rotationDegrees
            ?: camera?.cameraInfo?.sensorRotationDegrees ?: 90

    fun unlock() {
        camera?.cameraControl?.cancelFocusAndMetering()
        setAeLock(false)
    }

    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    private fun setAeLock(on: Boolean) {
        aeLocked = on
        applyManual(manual)
    }

    /** Exposure compensation range: {min, max, step (EV per index), index}. */
    fun exposureInfo(): Map<String, Any?> {
        val e = camera?.cameraInfo?.exposureState ?: return emptyMap()
        val step = e.exposureCompensationStep.toFloat()
        return mapOf(
            "supported" to e.isExposureCompensationSupported,
            "minEv" to e.exposureCompensationRange.lower * step,
            "maxEv" to e.exposureCompensationRange.upper * step,
            "stepEv" to step,
            "ev" to e.exposureCompensationIndex * step,
        )
    }

    /** Sets exposure compensation to the nearest step of [ev]; returns the applied EV. */
    fun setExposure(ev: Float): Float {
        val c = camera ?: return 0f
        val e = c.cameraInfo.exposureState
        if (!e.isExposureCompensationSupported) return 0f
        val step = e.exposureCompensationStep.toFloat()
        if (step <= 0f) return 0f
        val index = Math.round(ev / step).coerceIn(e.exposureCompensationRange.lower, e.exposureCompensationRange.upper)
        c.cameraControl.setExposureCompensationIndex(index)
        return index * step
    }

    /** What manual control this camera allows (Camera2 characteristics). */
    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    fun manualInfo(): Map<String, Any?> {
        val info = camera?.cameraInfo ?: return emptyMap()
        val c2 = Camera2CameraInfo.from(info)
        val caps = c2.getCameraCharacteristic(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: IntArray(0)
        val manualSensor = caps.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR)
        val iso = c2.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
        val exp = c2.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE)
        val minFocus = c2.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
        val awb = c2.getCameraCharacteristic(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES) ?: IntArray(0)
        return mapOf(
            "manualSensor" to (manualSensor && iso != null && exp != null),
            "isoMin" to iso?.lower,
            "isoMax" to iso?.upper,
            "exposureMinNs" to exp?.lower,
            "exposureMaxNs" to exp?.upper,
            "manualFocus" to (minFocus > 0f),
            "awbModes" to awb.toList(),
            "sceneModes" to (c2.getCameraCharacteristic(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES) ?: IntArray(0)).toList(),
        )
    }

    /**
     * Manual ISO + shutter (both needed: AE goes off), white balance preset
     * (CONTROL_AWB_MODE_*) and focus (0 = infinity .. 1 = closest). Null
     * values go back to automatic.
     */
    fun setManual(iso: Int?, exposureNs: Long?, awb: Int?, focus: Float?) {
        manual = ManualSettings(iso, exposureNs, awb, focus)
        applyManual(manual)
    }

    @androidx.annotation.OptIn(markerClass = [ExperimentalCamera2Interop::class])
    private fun applyManual(m: ManualSettings) {
        val c = camera ?: return
        val c2 = Camera2CameraControl.from(c.cameraControl)
        val b = CaptureRequestOptions.Builder()
        if (m.iso != null && m.exposureNs != null) {
            b.setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_OFF)
            b.setCaptureRequestOption(CaptureRequest.SENSOR_SENSITIVITY, m.iso)
            b.setCaptureRequestOption(CaptureRequest.SENSOR_EXPOSURE_TIME, m.exposureNs)
            // Keep the frame rate the shutter allows.
            b.setCaptureRequestOption(CaptureRequest.SENSOR_FRAME_DURATION, maxOf(m.exposureNs, 33_333_333L))
        } else {
            b.setCaptureRequestOption(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            b.setCaptureRequestOption(CaptureRequest.CONTROL_AE_LOCK, aeLocked)
        }
        b.setCaptureRequestOption(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, if (lowLight) Range(10, 30) else Range(24, 30))
        b.setCaptureRequestOption(CaptureRequest.CONTROL_AWB_MODE, m.awb ?: CaptureRequest.CONTROL_AWB_MODE_AUTO)
        if (m.awb == null) b.setCaptureRequestOption(CaptureRequest.CONTROL_AWB_LOCK, aeLocked)
        val scenes = Camera2CameraInfo.from(c.cameraInfo)
            .getCameraCharacteristic(CameraCharacteristics.CONTROL_AVAILABLE_SCENE_MODES) ?: IntArray(0)
        val scene = when (sceneMode) {
            "hdr" -> CameraMetadata.CONTROL_SCENE_MODE_HDR
            "night" -> CameraMetadata.CONTROL_SCENE_MODE_NIGHT
            else -> -1
        }
        if (scene >= 0 && scenes.contains(scene) && m.iso == null) {
            b.setCaptureRequestOption(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_USE_SCENE_MODE)
            b.setCaptureRequestOption(CaptureRequest.CONTROL_SCENE_MODE, scene)
        } else {
            b.setCaptureRequestOption(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
        }
        if (m.focus != null) {
            val minFocus = Camera2CameraInfo.from(c.cameraInfo)
                .getCameraCharacteristic(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
            b.setCaptureRequestOption(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_OFF)
            b.setCaptureRequestOption(CaptureRequest.LENS_FOCUS_DISTANCE, m.focus.coerceIn(0f, 1f) * minFocus)
        }
        c2.setCaptureRequestOptions(b.build())
    }

    /** Centre crop of an upright still to the preview's aspect (what the viewfinder framed). */
    private fun cropToPreview(b: Bitmap): Bitmap {
        val p = previewSize ?: return b
        val target = p.width.toFloat() / p.height
        val current = b.width.toFloat() / b.height
        if (kotlin.math.abs(current - target) < 0.01f) return b
        val (cw, ch) = if (current > target) {
            (b.height * target).toInt() to b.height
        } else {
            b.width to (b.width / target).toInt()
        }
        val out = Bitmap.createBitmap(b, (b.width - cw) / 2, (b.height - ch) / 2, cw, ch)
        if (out !== b) b.recycle()
        return out
    }

    /** Zoom range: {min, max, ratio}; min < 1 means an ultra-wide lens is available. */
    fun zoomInfo(): Map<String, Any?> {
        val z = camera?.cameraInfo?.zoomState?.value ?: return emptyMap()
        return mapOf("min" to z.minZoomRatio.toDouble(), "max" to z.maxZoomRatio.toDouble(), "ratio" to z.zoomRatio.toDouble())
    }

    /** Camera scene mode: "hdr" / "night" when the phone has them, else automatic. */
    private var sceneMode = "auto"

    fun setSceneMode(mode: String) {
        sceneMode = mode
        applyManual(manual)
    }

    fun takePicture(file: File, done: (String?, String?) -> Unit) {
        if (closed) return done(null, "closed")
        val capture = imageCapture
        if (capture == null) {
            pipeline.snapshot(file) { ok -> main.post { if (ok) done(file.absolutePath, null) else done(null, "snapshot_failed") } }
            return
        }
        // Fast path: nothing to grade and the still already has the preview's
        // aspect — CameraX writes the JPEG directly (EXIF carries rotation),
        // so the photo is ready almost at once.
        val previewAspect = previewSize?.let { it.width.toFloat() / it.height } ?: 0f
        val captureRes = capture.resolutionInfo?.resolution
        val stillAspect = captureRes?.let { minOf(it.width, it.height).toFloat() / maxOf(it.width, it.height) } ?: 0f
        val portraitPreview = previewAspect < 1f
        val sameAspect = kotlin.math.abs((if (portraitPreview) previewAspect else 1f / previewAspect) - stillAspect) < 0.02f
        // 3D effects are drawn by the GL pipeline: take the composited frame.
        if (pipeline.has3d) {
            pipeline.snapshot(file) { ok -> main.post { if (ok) done(file.absolutePath, null) else done(null, "snapshot_failed") } }
            return
        }
        if (!front && !pipeline.gradeActive && sameAspect) {
            capture.takePicture(
                ImageCapture.OutputFileOptions.Builder(file).build(),
                stillExecutor,
                object : ImageCapture.OnImageSavedCallback {
                    override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                        main.post { done(file.absolutePath, null) }
                    }

                    override fun onError(exception: ImageCaptureException) {
                        Log.w(TAG, "Direct still failed; using the preview frame", exception)
                        pipeline.snapshot(file) { ok ->
                            main.post { if (ok) done(file.absolutePath, null) else done(null, exception.message ?: "capture_failed") }
                        }
                    }
                },
            )
            return
        }
        // Decoded and written upright (and mirrored for the front camera, like
        // the preview) with no EXIF transform, so every reader sees the same pixels.
        capture.takePicture(stillExecutor, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                val upright = runCatching {
                    val src = image.toBitmap()
                    // Upright and mirrored for the front camera so the captured photo
                    // and any baked AR overlays match what the user saw in the viewfinder.
                    val m = android.graphics.Matrix().apply {
                        postRotate(image.imageInfo.rotationDegrees.toFloat())
                        if (front) postScale(-1f, 1f)
                    }
                    val rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true).also { if (it !== src) src.recycle() }
                    cropToPreview(rotated)
                }.onFailure { Log.w(TAG, "Could not decode the still", it) }.getOrNull()
                image.close()
                if (upright == null) {
                    main.post { done(null, "capture_failed") }
                    return
                }
                fun write(bmp: Bitmap) {
                    val ok = runCatching {
                        file.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 95, it) }
                    }.onFailure { Log.w(TAG, "Could not write the still", it) }.isSuccess
                    bmp.recycle()
                    main.post { if (ok) done(file.absolutePath, null) else done(null, "capture_failed") }
                }
                // The camera's filter is baked into the photo like the viewfinder.
                if (pipeline.gradeActive) {
                    pipeline.gradeStill(upright) { graded ->
                        if (graded !== upright) upright.recycle()
                        if (closed) graded.recycle() else runCatching { stillExecutor.execute { write(graded) } }.onFailure { write(graded) }
                    }
                } else {
                    write(upright)
                }
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
        if (audio) claimAudioFocus(exclusive = true)
        pipeline.startRecording(file, audio) { err -> main.post { done(err) } }
    }

    fun stopRecording(done: (Long) -> Unit) {
        pipeline.stopRecording { ms ->
            main.post {
                if (!closed) claimAudioFocus(exclusive = false)
                done(ms)
            }
        }
    }

    fun setGrade(look: com.oneova.camerakit.NativeLookData?, matrix: FloatArray?) = pipeline.setGrade(look, matrix)

    fun stats(): Map<String, Any?> = mapOf(
        "previewFps" to pipeline.previewFps,
        "trackFps" to trackingFps,
        "previewWidth" to previewSize?.width,
        "previewHeight" to previewSize?.height,
        "recording" to pipeline.isRecording,
        "micSilenced" to pipeline.micSilenced,
        "stillCapture" to (imageCapture != null),
        "dual" to dualOn,
        "graded" to pipeline.gradeActive,
    )

    fun close() {
        if (closed) return
        closed = true
        finishOpen(null, "closed")
        releaseAudioFocus()
        if (soundsLoaded) runCatching { sounds.release() }
        if (dualOn) runCatching { provider?.unbindAll() } else provider?.unbind(*useCases.toTypedArray())
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
