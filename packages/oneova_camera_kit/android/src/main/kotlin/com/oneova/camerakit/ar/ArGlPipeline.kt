package com.oneova.camerakit.ar

import android.graphics.Bitmap
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES30
import android.opengl.GLUtils
import android.opengl.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.camera.core.SurfaceRequest
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.roundToInt

/** What the recorded video composites over the camera (mirrors `LiveArState`). */
internal class ArScene(
    val effects: List<ArEffectSpec> = emptyList(),
    /** 0 none, 1 blur, 2 replace (same order as Dart `ArBackgroundMode`). */
    val backgroundMode: Int = 0,
    val blurSigma: Float = 14f,
    val addYourself: Boolean = false,
    val personOffsetX: Float = 0f,
    val personOffsetY: Float = 0f,
    val personScale: Float = 1f,
    /** Outfit colour [r, g, b, strength] (0..1), or null. */
    val outfit: FloatArray? = null,
    /** Each tracked person wears a different face effect. */
    val perPerson: Boolean = false,
)

/**
 * The AR camera's GL thread. CameraX renders the full-resolution Preview
 * stream into an OES texture here; every camera frame is then
 *
 *  1. drawn upright (rotated, mirrored for the front camera) into Flutter's
 *     [SurfaceProducer] texture — the Dart viewfinder paints the live
 *     effects over it, exactly as before; and
 *  2. while recording, composited with the person mask (blur / replace /
 *     "add yourself") and the effect overlay ([ArOverlayPainter]) into the
 *     video encoder's input surface, so the effects are baked into the file.
 *
 * All GL state lives on [handler]'s thread; other threads post to it.
 */
internal class ArGlPipeline(
    private val producer: io.flutter.view.TextureRegistry.SurfaceProducer,
    private val onPreviewSize: (Size) -> Unit,
) {
    private val thread = HandlerThread("OneovaArGl").apply { start() }
    /**
     * GL work never takes the app down: an EGL/GL error on this thread
     * (camera torn down mid-frame, display lost on resume) is logged and the
     * frame dropped instead of crashing (seen as eglMakeCurrent 0x3008).
     */
    val handler = object : Handler(thread.looper) {
        override fun dispatchMessage(msg: android.os.Message) {
            try {
                super.dispatchMessage(msg)
            } catch (e: RuntimeException) {
                Log.w(TAG, "GL task failed${if (released) " after release" else ""}", e)
            }
        }
    }
    val executor = Executor { handler.post(it) }

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var config: EGLConfig? = null
    private var pbuffer: EGLSurface = EGL14.EGL_NO_SURFACE
    private var previewSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var encoderSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    private class CameraInput(val tex: Int, val st: SurfaceTexture, val surface: Surface, val size: Size)
    private var input: CameraInput? = null
    private var rotation = 0
    private var transformKnown = false

    /**
     * -1 while drawing what is saved from the front camera: the preview is
     * mirrored like a selfie, saved photos/videos come out the right way round.
     */
    private var flipX = 1f
    private var crop: Rect? = null
    @Volatile var mirror = false

    /** Upright output size (the preview resolution, rotated). */
    var outWidth = 0
        private set
    var outHeight = 0
        private set

    private val texMatrix = FloatArray(16)
    private val camMap = FloatArray(9)

    // Second camera (dual mode, concurrent CameraX): its own OES input and transform.
    private class SecondInput(val tex: Int, val st: SurfaceTexture, val surface: Surface, val size: Size) {
        var rotation = 0
        var crop: Rect? = null
        var mirror = false
        val texMatrix = FloatArray(16)
        val camMap = FloatArray(9)
        var hasFrame = false
    }
    private var second: SecondInput? = null

    /**
     * Dual layout in upright output uv (top-left origin). mode 0: the second
     * camera in a rounded window at x/y/w/h; mode 1: split, second camera on
     * top. swap exchanges which camera fills the frame (or the top half).
     */
    class DualLayout(val mode: Int, val x: Float, val y: Float, val w: Float, val h: Float, val swap: Boolean)
    @Volatile private var dual: DualLayout? = null
    private var pipProgram = 0

    // Background video (replace mode): MediaPlayer → OES texture.
    private class BgVideo(val tex: Int, val st: SurfaceTexture, val surface: Surface, val player: android.media.MediaPlayer) {
        val mat = FloatArray(16)
        @Volatile var w = 0
        @Volatile var h = 0
        @Volatile var ready = false
    }
    private var bgVideo: BgVideo? = null

    /** Loops [path] (muted) behind the person while background replace is on; null stops it. */
    fun setBackgroundVideo(path: String?) = handler.post {
        releaseBgVideo()
        if (path == null || released) return@post
        try {
            makeCurrent(pbuffer)
            val tex = genOesTexture()
            val st = SurfaceTexture(tex)
            val surface = Surface(st)
            val player = android.media.MediaPlayer()
            val v = BgVideo(tex, st, surface, player)
            st.setOnFrameAvailableListener({
                if (bgVideo === v && !released) {
                    if (EGL14.eglGetCurrentContext() != context) makeCurrent(pbuffer)
                    st.updateTexImage()
                    st.getTransformMatrix(v.mat)
                    v.ready = true
                }
            }, handler)
            player.setDataSource(path)
            player.setSurface(surface)
            player.isLooping = true
            player.setVolume(0f, 0f)
            player.setOnVideoSizeChangedListener { _, w, h ->
                v.w = w
                v.h = h
            }
            player.setOnPreparedListener { it.start() }
            player.setOnErrorListener { _, what, extra ->
                Log.w(TAG, "Background video error $what/$extra")
                true
            }
            player.prepareAsync()
            bgVideo = v
        } catch (e: Exception) {
            Log.w(TAG, "Background video failed", e)
        }
    }

    private fun releaseBgVideo() {
        val v = bgVideo ?: return
        bgVideo = null
        runCatching { v.player.release() }
        runCatching { v.st.release() }
        runCatching { v.surface.release() }
        runCatching { GLES30.glDeleteTextures(1, intArrayOf(v.tex), 0) }
    }

    /** The filter / brightness / contrast baked into recordings and stills. */
    private val grade = ArGradePass()
    val gradeActive: Boolean get() = grade.active

    fun setGrade(look: com.oneova.camerakit.NativeLookData?, matrix: FloatArray?) = grade.set(look, matrix)

    /** Grades an upright still on the GL thread. */
    fun gradeStill(bitmap: Bitmap, done: (Bitmap) -> Unit) {
        val posted = handler.post {
            val out = try {
                if (released) bitmap else grade.gradeBitmap(bitmap)
            } catch (e: RuntimeException) {
                Log.w(TAG, "Still grade failed", e)
                bitmap
            }
            done(out)
        }
        if (!posted) done(bitmap)
    }

    private var blitProgram = 0
    private var compositeProgram = 0
    private var blurProgram = 0
    private var cameraToRgbProgram = 0
    private val quad: FloatBuffer = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply { put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)); position(0) }

    // Compositing inputs (recording only).
    private var maskTex = 0
    private var maskSize = Size(0, 0)
    private var overlayTex = 0
    private var overlayBitmap: Bitmap? = null
    private var overlayDirty = true
    private var bgTex = 0
    private var bgSize = Size(0, 0)
    private val blurChain = BlurChain()

    // Skin smoothing: a soft skin matte drawn with the overlay plus a light
    // half-size blur of the camera, mixed only where the matte is set.
    private val smoothChain = BlurChain()
    private var skinTex = 0
    private var skinBitmap: Bitmap? = null
    private var hasSkin = false

    /** Ping-pong textures for a separable gaussian at a fraction of the frame. */
    private class BlurChain {
        val tex = IntArray(2)
        val fbo = IntArray(2)
        var size = Size(0, 0)
    }

    private var scene = ArScene()
    private val images = HashMap<String, Bitmap>()
    private var world: Map<String, ArWorldSpec> = emptyMap()
    private var latest: ArResult? = null
    private var pendingMask: ArMask? = null

    private var recorder: ArVideoRecorder? = null
    private var recordStartNs = 0L
    private var clockOffsetNs: Long? = null
    private var pendingSnapshot: Pair<java.io.File, (Boolean) -> Unit>? = null

    // Stats.
    private var frames = 0
    private var fpsWindowStart = 0L
    @Volatile var previewFps = 0.0
        private set

    private var released = false

    // 3D effects layer: Filament renders into [layerSt]; composited over frames.
    private var r3d: Ar3dRenderer? = null
    private var layerTex = 0
    private var layerSt: SurfaceTexture? = null
    private var layerSurface: Surface? = null
    private val layerMat = FloatArray(16)
    @Volatile private var layerFresh = false
    @Volatile private var layerHasContent = false
    private var layerReady = false
    private var layerProgram = 0
    private var specs3d: List<Ar3dSpec> = emptyList()

    /** True while 3D effects are on (stills then come from the composited frame). */
    @Volatile var has3d = false
        private set

    init {
        handler.post { setUpEgl() }
        producer.setCallback(object : io.flutter.view.TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                handler.post { recreatePreviewSurface() }
            }

            override fun onSurfaceCleanup() {
                // The surface goes away when this returns: drop it on the GL thread first.
                val done = CountDownLatch(1)
                handler.post {
                    destroyPreviewSurface()
                    done.countDown()
                }
                done.await(500, TimeUnit.MILLISECONDS)
            }
        })
    }

    // ── Camera input ───────────────────────────────────────────────────────

    /** CameraX Preview's SurfaceProvider: hands it a fresh OES SurfaceTexture. */
    fun provideSurface(request: SurfaceRequest) {
        handler.post {
            if (released) {
                request.willNotProvideSurface()
                return@post
            }
            makeCurrent(pbuffer)
            val tex = genOesTexture()
            val st = SurfaceTexture(tex)
            val size = request.resolution
            st.setDefaultBufferSize(size.width, size.height)
            val surface = Surface(st)
            val next = CameraInput(tex, st, surface, size)
            st.setOnFrameAvailableListener({ onFrame(next) }, handler)
            input = next
            request.setTransformationInfoListener(executor) { info ->
                rotation = info.rotationDegrees
                crop = info.cropRect
                transformKnown = true
                updateOutputSize()
            }
            request.provideSurface(surface, executor) {
                // The camera is done with this surface. After release() the
                // EGL display is gone: just drop it (GL calls would throw).
                if (input === next) input = null
                releaseInput(next.st, next.surface, next.tex)
            }
            updateOutputSize()
        }
    }

    private fun releaseInput(st: SurfaceTexture, surface: Surface, tex: Int) {
        try {
            if (!released && display != EGL14.EGL_NO_DISPLAY) {
                makeCurrent(pbuffer)
                GLES30.glDeleteTextures(1, intArrayOf(tex), 0)
            }
        } catch (e: RuntimeException) {
            Log.w(TAG, "Camera surface release after GL teardown", e)
        }
        runCatching { st.release() }
        runCatching { surface.release() }
    }

    private fun updateOutputSize() {
        val inp = input ?: return
        // Wait for CameraX's transform: without its rotation the size would be
        // reported landscape for a portrait picture (squashed preview).
        if (!transformKnown) return
        val c = crop ?: Rect(0, 0, inp.size.width, inp.size.height)
        val upright = rotation == 90 || rotation == 270
        val w = if (upright) c.height() else c.width()
        val h = if (upright) c.width() else c.height()
        if (w == outWidth && h == outHeight) return
        outWidth = w
        outHeight = h
        producer.setSize(w, h)
        recreatePreviewSurface()
        onPreviewSize(Size(w, h))
    }

    private fun onFrame(frameInput: CameraInput) {
        if (released || frameInput !== input) return
        try {
            makeCurrent(if (previewSurface != EGL14.EGL_NO_SURFACE) previewSurface else pbuffer)
            frameInput.st.updateTexImage()
            frameInput.st.getTransformMatrix(texMatrix)
            computeCamMap(frameInput.size)
            val ts = frameInput.st.timestamp
            update3d()

            if (previewSurface != EGL14.EGL_NO_SURFACE) {
                GLES30.glViewport(0, 0, outWidth, outHeight)
                if (dualReady()) {
                    GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
                    drawDual(frameInput.tex, 1f, outWidth, outHeight, mainDrawn = false)
                } else {
                    drawBlit(frameInput.tex)
                    drawLayer(1f)
                }
                EGL14.eglSwapBuffers(display, previewSurface)
            }

            val rec = recorder
            if (rec != null) recordFrame(rec, frameInput.tex, ts)
            pendingSnapshot?.let {
                pendingSnapshot = null
                writeSnapshot(frameInput.tex, it.first, it.second)
            }
            countFrame()
        } catch (e: RuntimeException) {
            Log.w(TAG, "AR frame failed", e)
        }
    }

    private fun countFrame() {
        val now = SystemClock.elapsedRealtime()
        if (fpsWindowStart == 0L) fpsWindowStart = now
        frames++
        if (now - fpsWindowStart >= 1000) {
            previewFps = frames * 1000.0 / (now - fpsWindowStart)
            frames = 0
            fpsWindowStart = now
        }
    }

    /**
     * Upright output uv (top-left origin) → camera texture st, folded into
     * one affine 3×3: mirror, rotate into the sensor buffer, crop, flip to
     * GL's bottom-left origin, then the SurfaceTexture transform.
     */
    private fun computeCamMap(size: Size) = computeMap(size, crop, rotation, mirror, texMatrix, camMap)

    private fun computeMap(size: Size, crop: Rect?, reportedRotation: Int, mirror: Boolean, texMatrix: FloatArray, camMap: FloatArray) {
        val c = crop ?: Rect(0, 0, size.width, size.height)
        // Some camera HALs (e.g. TECNO, hasCameraTransform=true) already put
        // the sensor rotation into the SurfaceTexture matrix (it swaps s/t).
        // Rotating again turned the preview sideways, so only rotate when the
        // matrix does not.
        val matrixRotates = abs(texMatrix[1]) > abs(texMatrix[0])
        val rotation = if (matrixRotates && (reportedRotation == 90 || reportedRotation == 270)) 0 else reportedRotation
        // A standard un-mirrored SurfaceTexture flips t (2x2 determinant < 0).
        // If det > 0, the HAL already applied a horizontal mirror inside texMatrix.
        val halMirrored = (texMatrix[0] * texMatrix[5] - texMatrix[1] * texMatrix[4]) > 0f
        val effectiveMirror = mirror xor halMirrored
        fun map(u0: Float, v: Float): FloatArray {
            val u = if (effectiveMirror) 1 - u0 else u0
            val (bu, bv) = when (rotation) {
                90 -> v to 1 - u
                180 -> 1 - u to 1 - v
                270 -> 1 - v to u
                else -> u to v
            }
            val s = (c.left + bu * c.width()) / size.width
            val t = 1 - (c.top + bv * c.height()) / size.height
            val r = FloatArray(4)
            Matrix.multiplyMV(r, 0, texMatrix, 0, floatArrayOf(s, t, 0f, 1f), 0)
            return r
        }
        val o = map(0f, 0f)
        val x = map(1f, 0f)
        val y = map(0f, 1f)
        // Column-major mat3: columns are d/du, d/dv, origin.
        camMap[0] = x[0] - o[0]; camMap[1] = x[1] - o[1]; camMap[2] = 0f
        camMap[3] = y[0] - o[0]; camMap[4] = y[1] - o[1]; camMap[5] = 0f
        camMap[6] = o[0]; camMap[7] = o[1]; camMap[8] = 1f
    }

    // ── Scene + tracking (from other threads) ──────────────────────────────

    fun setScene(next: ArScene) = handler.post {
        scene = next
        overlayDirty = true
    }

    fun putImage(id: String, bitmap: Bitmap) = handler.post {
        images.put(id, bitmap)?.takeIf { it !== bitmap }?.recycle()
        overlayDirty = true
    }

    fun retainImages(ids: Set<String>) = handler.post {
        val gone = images.keys - ids
        for (id in gone) images.remove(id)?.recycle()
        if (gone.isNotEmpty()) overlayDirty = true
    }

    fun setBackground(bitmap: Bitmap?) = handler.post {
        makeCurrent(pbuffer)
        if (bitmap == null) {
            if (bgTex != 0) GLES30.glDeleteTextures(1, intArrayOf(bgTex), 0)
            bgTex = 0
            bgSize = Size(0, 0)
            return@post
        }
        if (bgTex == 0) bgTex = gen2dTexture()
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, bgTex)
        GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, bitmap, 0)
        bgSize = Size(bitmap.width, bitmap.height)
        bitmap.recycle()
    }

    fun setWorld(next: Map<String, ArWorldSpec>) = handler.post {
        world = next
        overlayDirty = true
    }

    /** The 3D effects to wear (empty turns the 3D layer off). */
    fun set3d(next: List<Ar3dSpec>) = handler.post {
        specs3d = next
        has3d = next.isNotEmpty()
        if (next.isNotEmpty()) ensure3d()
        r3d?.setSpecs(next)
        r3d?.retainModels(next.map { it.id }.toSet())
        if (next.isEmpty()) layerHasContent = false
    }

    /** Loads a downloaded .glb for 3D effect [id]; [done] gets null or an error. */
    fun putModel(id: String, path: String, done: (String?) -> Unit) = handler.post {
        val r = ensure3d()
        if (r == null) done("3d_unavailable") else r.putModel(id, path, done)
    }

    private fun ensure3d(): Ar3dRenderer? {
        r3d?.let { return it }
        if (released || display == EGL14.EGL_NO_DISPLAY) return null
        makeCurrent(pbuffer)
        val tex = genOesTexture()
        val st = SurfaceTexture(tex)
        val w = max(2, outWidth)
        val h = max(2, outHeight)
        st.setDefaultBufferSize(w, h)
        st.setOnFrameAvailableListener({ layerFresh = true }, handler)
        val surface = Surface(st)
        layerTex = tex
        layerSt = st
        layerSurface = surface
        if (layerProgram == 0) layerProgram = buildProgram(VERTEX, FRAGMENT_LAYER)
        val r = Ar3dRenderer(surface, w, h)
        r.onContent = { has -> layerHasContent = has }
        r3d = r
        return r
    }

    /** Asks for a 3D frame for the latest tracking and latches a finished one. */
    private fun update3d() {
        val r = r3d ?: return
        val st = layerSt ?: return
        if (specs3d.isNotEmpty()) {
            val res = latest
            if (outWidth > 0) st.setDefaultBufferSize(outWidth, outHeight)
            r.request(Ar3dRenderer.Frame(res?.faces ?: emptyList(), res?.light ?: 0.5f, res?.tint, outWidth, outHeight))
        }
        if (layerFresh) {
            layerFresh = false
            st.updateTexImage()
            st.getTransformMatrix(layerMat)
            layerReady = true
        }
    }

    /** Premultiplied 3D layer over whatever is bound (same flips as the camera quad). */
    private fun drawLayer(flip: Float) {
        if (!layerReady || !layerHasContent || specs3d.isEmpty() || layerProgram == 0) return
        val p = layerProgram
        GLES30.glUseProgram(p)
        bindQuad(p, flip)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, layerTex)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(p, "uLayer"), 0)
        GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(p, "uLayerMat"), 1, false, layerMat, 0)
        GLES30.glEnable(GLES30.GL_BLEND)
        GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        GLES30.glDisable(GLES30.GL_BLEND)
    }

    fun onTracking(result: ArResult) = handler.post {
        latest = result
        if (result.mask != null) pendingMask = result.mask
        overlayDirty = true
    }

    fun clearTracking() = handler.post {
        latest = null
        pendingMask = null
        maskSize = Size(0, 0)
        overlayDirty = true
    }

    // ── Recording ──────────────────────────────────────────────────────────

    /** Starts encoding composited frames; [onStarted] gets null or an error. */
    fun startRecording(file: java.io.File, withAudio: Boolean, onStarted: (String?) -> Unit) = handler.post {
        if (recorder != null) {
            onStarted("already_recording")
            return@post
        }
        if (outWidth == 0 || outHeight == 0) {
            onStarted("camera_not_ready")
            return@post
        }
        try {
            val size = encoderSize(outWidth, outHeight)
            recordStartNs = System.nanoTime()
            clockOffsetNs = null
            val rec = ArVideoRecorder(file, size.width, size.height, recordFps, withAudio, recordStartNs, orientationHint)
            encoderSurface = EGL14.eglCreateWindowSurface(display, config, rec.inputSurface, intArrayOf(EGL14.EGL_NONE), 0)
            recorder = rec
            overlayDirty = true
            onStarted(null)
        } catch (e: Exception) {
            Log.e(TAG, "Could not start recording", e)
            onStarted(e.message ?: "encoder_failed")
        }
    }

    /** Finishes the file; [onDone] gets the duration in ms (-1 on failure). */
    fun stopRecording(onDone: (Long) -> Unit) = handler.post {
        val rec = recorder
        if (rec == null) {
            onDone(-1)
            return@post
        }
        recorder = null
        makeCurrent(pbuffer)
        destroyEncoderSurface()
        val ms = rec.finish()
        onDone(ms)
    }

    val isRecording: Boolean get() = recorder != null

    /** Recording frame rate (30 or 60) and MP4 orientation (landscape saving). */
    @Volatile var recordFps = 30
    @Volatile var orientationHint = 0
    val micSilenced: Boolean get() = recorder?.micSilenced == true

    /** Saves the next upright preview frame as a JPEG (stills without ImageCapture). */
    fun snapshot(file: java.io.File, done: (Boolean) -> Unit) = handler.post {
        if (pendingSnapshot != null || outWidth == 0) done(false) else pendingSnapshot = file to done
    }

    private fun writeSnapshot(camTex: Int, file: java.io.File, done: (Boolean) -> Unit) {
        val w = outWidth
        val h = outHeight
        val fbo = IntArray(1)
        val tex = gen2dTexture()
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, w, h, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null)
        GLES30.glGenFramebuffers(1, fbo, 0)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fbo[0])
        GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, tex, 0)
        GLES30.glViewport(0, 0, w, h)
        GLES30.glUseProgram(blitProgram)
        // camMap already mirrors front-camera UV to match the viewfinder; keep flipX = 1f
        // so snapshots and recorded videos match the preview without flipping stickers/text.
        flipX = 1f
        bindQuad(blitProgram, flip = -1f)
        bindOes(blitProgram, camTex)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        if (dualReady()) drawDual(camTex, -1f, w, h, mainDrawn = false) else drawLayer(-1f)
        flipX = 1f
        val pixels = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())
        GLES30.glReadPixels(0, 0, w, h, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, pixels)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        GLES30.glDeleteFramebuffers(1, fbo, 0)
        GLES30.glDeleteTextures(1, intArrayOf(tex), 0)
        val raw = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        raw.copyPixelsFromBuffer(pixels.rewind())
        val graded = runCatching { grade.gradeBitmap(raw) }.getOrDefault(raw)
        if (graded !== raw) raw.recycle()
        Thread({
            val ok = runCatching {
                file.outputStream().use { graded.compress(Bitmap.CompressFormat.JPEG, 95, it) }
                graded.recycle()
            }.isSuccess
            done(ok)
        }, "OneovaArSnapshot").start()
    }

    private fun recordFrame(rec: ArVideoRecorder, camTex: Int, cameraTs: Long) {
        if (encoderSurface == EGL14.EGL_NO_SURFACE) return
        val mono = toMonotonic(cameraTs)
        if (mono < recordStartNs) return
        makeCurrent(encoderSurface)
        uploadPendingMask()
        val segmenting = scene.backgroundMode != 0 && maskSize.width > 0
        if (segmenting && scene.backgroundMode == 1) {
            renderBlur(camTex, blurChain, 4, (scene.blurSigma / 4f).coerceIn(0.5f, 12f))
        }
        val hasOverlay = updateOverlay(rec.width, rec.height)
        val smoothing = if (hasSkin) smoothingAmount() else 0f
        if (smoothing > 0f) renderBlur(camTex, smoothChain, 2, 2.2f)

        makeCurrent(encoderSurface)
        // Keep flipX = 1f because camMap, ArTracker, and ArOverlayPainter are all in
        // preview space (already mirrored on front camera). Flipping again inverted
        // front-camera recordings and reversed text/stickers/PiP relative to preview.
        flipX = 1f
        val graded = grade.active
        if (graded) {
            grade.beginScene(rec.width, rec.height)
        } else {
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
            GLES30.glViewport(0, 0, rec.width, rec.height)
        }
        val d = dual
        if (d != null && dualReady()) {
            // Effects stay on the main camera when it fills the frame.
            val full = d.mode == 0 && !d.swap
            if (full) drawComposite(camTex, segmenting, hasOverlay, smoothing, rec.width, rec.height)
            drawDual(camTex, 1f, rec.width, rec.height, mainDrawn = full)
            if (full) drawLayer(1f)
        } else {
            drawComposite(camTex, segmenting, hasOverlay, smoothing, rec.width, rec.height)
            drawLayer(1f)
        }
        if (graded) grade.finish(0)
        flipX = 1f
        EGLExt.eglPresentationTimeANDROID(display, encoderSurface, mono - recordStartNs)
        EGL14.eglSwapBuffers(display, encoderSurface)
        rec.drainVideo(false)
    }

    /**
     * Camera timestamps use the sensor's clock (often elapsedRealtime);
     * the audio track uses System.nanoTime. Pick whichever the frame matches.
     */
    private fun toMonotonic(ts: Long): Long {
        val offset = clockOffsetNs ?: run {
            val mono = System.nanoTime()
            val boot = SystemClock.elapsedRealtimeNanos()
            (if (abs(ts - boot) < abs(ts - mono)) boot - mono else 0L).also { clockOffsetNs = it }
        }
        return ts - offset
    }

    /** Largest even size ≤ the preview the AVC encoder takes (falls back to 720p). */
    private fun encoderSize(w: Int, h: Int): Size {
        val caps = runCatching {
            android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS).codecInfos
                .firstOrNull { it.isEncoder && it.supportedTypes.any { t -> t.equals("video/avc", true) } }
                ?.getCapabilitiesForType("video/avc")?.videoCapabilities
        }.getOrNull()
        val ew = w and 1.inv()
        val eh = h and 1.inv()
        if (caps == null || caps.isSizeSupported(ew, eh)) return Size(ew, eh)
        val scale = 1280f / max(ew, eh)
        return Size(((ew * scale).roundToInt()) and 1.inv(), ((eh * scale).roundToInt()) and 1.inv())
    }

    // ── Dual camera ────────────────────────────────────────────────────────

    /** SurfaceProvider for the second camera's Preview (dual mode). */
    fun provideSecondSurface(request: SurfaceRequest, mirrored: Boolean) {
        handler.post {
            if (released) {
                request.willNotProvideSurface()
                return@post
            }
            makeCurrent(pbuffer)
            val tex = genOesTexture()
            val st = SurfaceTexture(tex)
            val size = request.resolution
            st.setDefaultBufferSize(size.width, size.height)
            val surface = Surface(st)
            val next = SecondInput(tex, st, surface, size).apply { mirror = mirrored }
            st.setOnFrameAvailableListener({ onSecondFrame(next) }, handler)
            second = next
            request.setTransformationInfoListener(executor) { info ->
                next.rotation = info.rotationDegrees
                next.crop = info.cropRect
            }
            request.provideSurface(surface, executor) {
                if (second === next) second = null
                releaseInput(next.st, next.surface, next.tex)
            }
        }
    }

    private fun onSecondFrame(s: SecondInput) {
        if (released || s !== second) return
        try {
            if (EGL14.eglGetCurrentContext() != context) makeCurrent(pbuffer)
            s.st.updateTexImage()
            s.st.getTransformMatrix(s.texMatrix)
            computeMap(s.size, s.crop, s.rotation, s.mirror, s.texMatrix, s.camMap)
            s.hasFrame = true
        } catch (e: RuntimeException) {
            Log.w(TAG, "Second camera frame failed", e)
        }
    }

    /** Null turns dual drawing off (the second camera may keep running). */
    fun setDual(layout: DualLayout?) {
        dual = layout
    }

    private fun dualReady(): Boolean = dual != null && second?.hasFrame == true

    private fun uprightSize(size: Size, crop: Rect?, rotation: Int): Size {
        val c = crop ?: Rect(0, 0, size.width, size.height)
        return if (rotation == 90 || rotation == 270) Size(c.height(), c.width()) else Size(c.width(), c.height())
    }

    /** Both cameras into the bound target ([w]×[h]); [mainDrawn] skips the full-frame main pass. */
    private fun drawDual(mainTex: Int, flip: Float, w: Int, h: Int, mainDrawn: Boolean) {
        val d = dual ?: return
        val s = second ?: return
        val mainSize = Size(outWidth, outHeight)
        val secondSize = uprightSize(s.size, s.crop, s.rotation)
        val radius = 0.035f * minOf(w, h)
        val border = maxOf(2f, 0.004f * minOf(w, h))
        fun main(x: Float, y: Float, rw: Float, rh: Float, r: Float, b: Float) =
            drawCamRect(mainTex, camMap, mainSize, x, y, rw, rh, flip, w, h, r, b)
        fun sec(x: Float, y: Float, rw: Float, rh: Float, r: Float, b: Float) =
            drawCamRect(s.tex, s.camMap, secondSize, x, y, rw, rh, flip, w, h, r, b)
        if (d.mode == 1) {
            if (d.swap) {
                main(0f, 0f, 1f, 0.5f, 0f, 0f)
                sec(0f, 0.5f, 1f, 0.5f, 0f, 0f)
            } else {
                sec(0f, 0f, 1f, 0.5f, 0f, 0f)
                main(0f, 0.5f, 1f, 0.5f, 0f, 0f)
            }
            return
        }
        if (d.swap) {
            sec(0f, 0f, 1f, 1f, 0f, 0f)
            main(d.x, d.y, d.w, d.h, radius, border)
        } else {
            if (!mainDrawn) main(0f, 0f, 1f, 1f, 0f, 0f)
            sec(d.x, d.y, d.w, d.h, radius, border)
        }
    }

    /** One camera into a rect of the target, cropped to cover it (BoxFit.cover). */
    private fun drawCamRect(
        tex: Int, map: FloatArray, src: Size,
        x: Float, y: Float, rw: Float, rh: Float,
        flip: Float, w: Int, h: Int, radius: Float, border: Float,
    ) {
        if (src.width <= 0 || src.height <= 0) return
        val p = pipProgram
        GLES30.glUseProgram(p)
        bindQuad(p, flip)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(p, "uCam"), 0)
        GLES30.glUniformMatrix3fv(GLES30.glGetUniformLocation(p, "uCamMap"), 1, false, map, 0)
        val rectAspect = (rw * w) / (rh * h)
        val srcAspect = src.width.toFloat() / src.height
        var sx = 1f
        var sy = 1f
        if (srcAspect > rectAspect) sx = rectAspect / srcAspect else sy = srcAspect / rectAspect
        GLES30.glUniform4f(GLES30.glGetUniformLocation(p, "uRect"), x, y, rw, rh)
        GLES30.glUniform4f(GLES30.glGetUniformLocation(p, "uSrc"), (1 - sx) / 2, (1 - sy) / 2, sx, sy)
        GLES30.glUniform2f(GLES30.glGetUniformLocation(p, "uRes"), w.toFloat(), h.toFloat())
        GLES30.glUniform1f(GLES30.glGetUniformLocation(p, "uRadius"), radius)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(p, "uBorder"), border)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    }

    // ── Compositing ────────────────────────────────────────────────────────

    private fun uploadPendingMask() {
        val m = pendingMask ?: return
        pendingMask = null
        if (maskTex == 0) maskTex = gen2dTexture()
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, maskTex)
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 1)
        GLES30.glTexImage2D(
            GLES30.GL_TEXTURE_2D, 0, GLES30.GL_R8, m.width, m.height, 0,
            GLES30.GL_RED, GLES30.GL_UNSIGNED_BYTE, ByteBuffer.wrap(m.alpha),
        )
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 4)
        maskSize = Size(m.width, m.height)
    }

    /** Redraws the sprite/makeup overlay when tracking or the scene changed. */
    private fun updateOverlay(recW: Int, recH: Int): Boolean {
        val drawsSomething = scene.effects.any { it.kind == "makeup" || it.kind == "vfx" || images.containsKey(it.id) }
        if (!drawsSomething) {
            hasSkin = false
            return false
        }
        // Two thirds of the video size keeps the canvas cheap; sprites are soft anyway.
        val ow = (recW * 2 / 3).coerceAtLeast(2)
        val oh = (recH * 2 / 3).coerceAtLeast(2)
        var bmp = overlayBitmap
        if (bmp == null || bmp.width != ow || bmp.height != oh) {
            bmp?.recycle()
            bmp = Bitmap.createBitmap(ow, oh, Bitmap.Config.ARGB_8888)
            overlayBitmap = bmp
            overlayDirty = true
        }
        if (!overlayDirty) return true
        overlayDirty = false
        bmp!!.eraseColor(0)
        ArOverlayPainter.paint(Canvas(bmp), ow.toFloat(), oh.toFloat(), latest, scene.effects, images, world, scene.perPerson)
        if (overlayTex == 0) overlayTex = gen2dTexture()
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, overlayTex)
        GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, bmp, 0)
        updateSkin(ow / 2, oh / 2)
        return true
    }

    /** Strongest skin smoothing among the active makeup effects. */
    private fun smoothingAmount(): Float =
        scene.effects.filter { it.kind == "makeup" }.maxOfOrNull { it.makeup.smoothing } ?: 0f

    /** Paints the soft skin matte for smoothing (same faces as the overlay). */
    private fun updateSkin(sw: Int, sh: Int) {
        val faces = latest?.faces ?: emptyList()
        if (smoothingAmount() <= 0f || faces.isEmpty()) {
            hasSkin = false
            return
        }
        val w = sw.coerceAtLeast(2)
        val h = sh.coerceAtLeast(2)
        var bmp = skinBitmap
        if (bmp == null || bmp.width != w || bmp.height != h) {
            bmp?.recycle()
            bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            skinBitmap = bmp
        }
        bmp!!.eraseColor(0)
        val canvas = Canvas(bmp)
        for (f in faces) {
            val path = ArOverlayPainter.skinPath(f, w.toFloat(), h.toFloat()) ?: continue
            val refW = f.width * w
            canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = 0xFFFFFFFF.toInt()
                if (refW * 0.03f >= 0.5f) maskFilter = BlurMaskFilter(refW * 0.03f, BlurMaskFilter.Blur.NORMAL)
            })
        }
        if (skinTex == 0) skinTex = gen2dTexture()
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, skinTex)
        GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, bmp, 0)
        hasSkin = true
    }

    /** Camera at 1/[divisor] size, then a separable gaussian (two passes) into [chain].tex[0]. */
    private fun renderBlur(camTex: Int, chain: BlurChain, divisor: Int, sigma: Float) {
        val bw = (outWidth / divisor).coerceAtLeast(2)
        val bh = (outHeight / divisor).coerceAtLeast(2)
        if (chain.size.width != bw || chain.size.height != bh) {
            if (chain.tex[0] != 0) {
                GLES30.glDeleteTextures(2, chain.tex, 0)
                GLES30.glDeleteFramebuffers(2, chain.fbo, 0)
            }
            GLES30.glGenFramebuffers(2, chain.fbo, 0)
            for (i in 0..1) {
                chain.tex[i] = gen2dTexture()
                GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, chain.tex[i])
                GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, bw, bh, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null)
                GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, chain.fbo[i])
                GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, chain.tex[i], 0)
            }
            chain.size = Size(bw, bh)
        }
        GLES30.glViewport(0, 0, bw, bh)
        // Camera → tex[0].
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, chain.fbo[0])
        GLES30.glUseProgram(cameraToRgbProgram)
        bindQuad(cameraToRgbProgram, flip = -1f)
        bindOes(cameraToRgbProgram, camTex)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        blurPass(chain.tex[0], chain.fbo[1], 1f / bw, 0f, sigma)
        blurPass(chain.tex[1], chain.fbo[0], 0f, 1f / bh, sigma)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
    }

    private fun blurPass(src: Int, dstFbo: Int, dx: Float, dy: Float, sigma: Float) {
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, dstFbo)
        GLES30.glUseProgram(blurProgram)
        bindQuad(blurProgram, flip = -1f)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, src)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(blurProgram, "uSrc"), 0)
        // 9 taps spaced so they span ±2.4σ; weights from the gaussian.
        val step = max(1f, sigma * 0.6f)
        val weights = FloatArray(5) { exp(-(it * step) * (it * step) / (2 * sigma * sigma)) }
        val total = weights[0] + 2 * (weights[1] + weights[2] + weights[3] + weights[4])
        for (i in 0..4) weights[i] /= total
        GLES30.glUniform2f(GLES30.glGetUniformLocation(blurProgram, "uStep"), dx * step, dy * step)
        GLES30.glUniform1fv(GLES30.glGetUniformLocation(blurProgram, "uWeights"), 5, weights, 0)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    }

    /** Where clothes start, from the latest tracking (same rule as Dart `neckLine`). */
    private fun neckLine(): Float {
        val r = latest ?: return 0.38f
        r.body?.let { return minOf(it.leftShoulder.y, it.rightShoulder.y) - 0.03f }
        r.faces.firstOrNull()?.let { return it.chin.y + 0.04f }
        return 0.38f
    }

    private fun drawComposite(camTex: Int, segmenting: Boolean, hasOverlay: Boolean, smoothing: Float, w: Int, h: Int) {
        val p = compositeProgram
        GLES30.glUseProgram(p)
        bindQuad(p, flip = 1f)
        bindOes(p, camTex)
        fun loc(n: String) = GLES30.glGetUniformLocation(p, n)
        fun tex(unit: Int, id: Int, name: String) {
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + unit)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, id)
            GLES30.glUniform1i(loc(name), unit)
        }
        val video = bgVideo?.takeIf { it.ready && it.w > 0 && it.h > 0 && scene.backgroundMode == 2 }
        val mode = if (!segmenting) 0 else if (scene.backgroundMode == 2 && bgTex == 0 && video == null) 3 else scene.backgroundMode
        GLES30.glUniform1i(loc("uMode"), mode)
        val outfit = scene.outfit?.takeIf { it.size >= 4 && it[3] > 0f && maskSize.width > 0 }
        tex(1, if (segmenting || outfit != null) maskTex else 0, "uMask")
        GLES30.glUniform4f(loc("uOutfit"), outfit?.get(0) ?: 0f, outfit?.get(1) ?: 0f, outfit?.get(2) ?: 0f, outfit?.get(3) ?: 0f)
        GLES30.glUniform1f(loc("uNeckY"), neckLine())
        GLES30.glUniform2f(loc("uMaskTexel"), 1f / maxOf(1, maskSize.width), 1f / maxOf(1, maskSize.height))
        tex(2, if (mode == 1) blurChain.tex[0] else 0, "uBlur")
        tex(3, if (mode == 2) bgTex else 0, "uBg")
        tex(4, if (hasOverlay) overlayTex else 0, "uOverlay")
        GLES30.glUniform1i(loc("uHasOverlay"), if (hasOverlay) 1 else 0)
        tex(5, if (smoothing > 0f) smoothChain.tex[0] else 0, "uSkinBlur")
        tex(6, if (smoothing > 0f) skinTex else 0, "uSkin")
        GLES30.glUniform1f(loc("uSmooth"), smoothing)
        GLES30.glUniform1i(loc("uBgVideoOn"), if (mode == 2 && video != null) 1 else 0)
        if (mode == 2 && video != null) {
            GLES30.glActiveTexture(GLES30.GL_TEXTURE7)
            GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, video.tex)
            GLES30.glUniform1i(loc("uBgVideo"), 7)
            GLES30.glUniformMatrix4fv(loc("uBgVideoMat"), 1, false, video.mat, 0)
            val s = max(w.toFloat() / video.w, h.toFloat() / video.h)
            GLES30.glUniform2f(loc("uBgScale"), w / (video.w * s), h / (video.h * s))
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        } else if (mode == 2) {
            // BoxFit.cover of the scene image over the frame.
            val s = max(w.toFloat() / bgSize.width, h.toFloat() / bgSize.height)
            GLES30.glUniform2f(loc("uBgScale"), w / (bgSize.width * s), h / (bgSize.height * s))
        }
        val person = segmenting && scene.addYourself
        GLES30.glUniform3f(
            loc("uPerson"),
            if (person) scene.personOffsetX else 0f,
            if (person) scene.personOffsetY else 0f,
            if (person) scene.personScale.coerceAtLeast(0.05f) else 1f,
        )
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun drawBlit(camTex: Int) {
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        GLES30.glUseProgram(blitProgram)
        bindQuad(blitProgram, flip = 1f)
        bindOes(blitProgram, camTex)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun bindQuad(program: Int, flip: Float) {
        val pos = GLES30.glGetAttribLocation(program, "aPos")
        GLES30.glEnableVertexAttribArray(pos)
        GLES30.glVertexAttribPointer(pos, 2, GLES30.GL_FLOAT, false, 0, quad)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uFlip"), flip)
        GLES30.glUniform1f(GLES30.glGetUniformLocation(program, "uFlipX"), flipX)
    }

    private fun bindOes(program: Int, camTex: Int) {
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, camTex)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uCam"), 0)
        GLES30.glUniformMatrix3fv(GLES30.glGetUniformLocation(program, "uCamMap"), 1, false, camMap, 0)
    }

    // ── EGL ────────────────────────────────────────────────────────────────

    private fun setUpEgl() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }
        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES3_BIT_KHR,
            EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT or EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        check(EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, count, 0) && count[0] > 0) { "No EGL config" }
        config = configs[0]
        context = EGL14.eglCreateContext(
            display, config, EGL14.EGL_NO_CONTEXT, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE), 0,
        )
        check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }
        pbuffer = EGL14.eglCreatePbufferSurface(display, config, intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE), 0)
        makeCurrent(pbuffer)
        blitProgram = buildProgram(VERTEX, FRAGMENT_BLIT)
        cameraToRgbProgram = blitProgram
        compositeProgram = buildProgram(VERTEX, FRAGMENT_COMPOSITE)
        blurProgram = buildProgram(VERTEX, FRAGMENT_BLUR)
        pipProgram = buildProgram(VERTEX, FRAGMENT_PIP)
    }

    private fun makeCurrent(surface: EGLSurface) {
        if (!EGL14.eglMakeCurrent(display, surface, surface, context)) {
            throw RuntimeException("eglMakeCurrent failed: 0x${Integer.toHexString(EGL14.eglGetError())}")
        }
    }

    private fun recreatePreviewSurface() {
        if (released || display == EGL14.EGL_NO_DISPLAY) return
        destroyPreviewSurface()
        val surface = producer.surface ?: return
        if (!surface.isValid) return
        previewSurface = EGL14.eglCreateWindowSurface(display, config, surface, intArrayOf(EGL14.EGL_NONE), 0)
        if (previewSurface == EGL14.EGL_NO_SURFACE) {
            Log.w(TAG, "Could not attach the Flutter texture: 0x${Integer.toHexString(EGL14.eglGetError())}")
        }
    }

    private fun destroyPreviewSurface() {
        if (previewSurface == EGL14.EGL_NO_SURFACE) return
        makeCurrent(pbuffer)
        EGL14.eglDestroySurface(display, previewSurface)
        previewSurface = EGL14.EGL_NO_SURFACE
    }

    private fun destroyEncoderSurface() {
        if (encoderSurface == EGL14.EGL_NO_SURFACE) return
        EGL14.eglDestroySurface(display, encoderSurface)
        encoderSurface = EGL14.EGL_NO_SURFACE
    }

    /** Releases everything; an unfinished recording is dropped. */
    fun release() {
        val done = CountDownLatch(1)
        handler.post {
            released = true
            try {
                makeCurrent(pbuffer)
                recorder?.let {
                    destroyEncoderSurface()
                    it.abandon()
                }
                recorder = null
                destroyPreviewSurface()
                input?.let {
                    it.st.release()
                    it.surface.release()
                }
                input = null
                second?.let {
                    it.st.release()
                    it.surface.release()
                }
                second = null
                grade.release()
                releaseBgVideo()
                r3d?.let { r ->
                    r.release()
                    r.awaitIdle()
                }
                r3d = null
                runCatching { layerSt?.release() }
                runCatching { layerSurface?.release() }
                layerSt = null
                layerSurface = null
                images.values.forEach { it.recycle() }
                images.clear()
                overlayBitmap?.recycle()
                overlayBitmap = null
                skinBitmap?.recycle()
                skinBitmap = null
                EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                EGL14.eglDestroySurface(display, pbuffer)
                EGL14.eglDestroyContext(display, context)
                // No eglTerminate: the display is process-wide and the 3D
                // engine (Filament) keeps its own context on it.
            } catch (e: RuntimeException) {
                Log.w(TAG, "GL release failed", e)
            } finally {
                done.countDown()
            }
        }
        done.await(1, TimeUnit.SECONDS)
        producer.setCallback(null)
        thread.quitSafely()
    }

    private fun genOesTexture(): Int {
        val t = IntArray(1)
        GLES30.glGenTextures(1, t, 0)
        GLES30.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, t[0])
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
        return t[0]
    }

    private fun gen2dTexture(): Int {
        val t = IntArray(1)
        GLES30.glGenTextures(1, t, 0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, t[0])
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
        return t[0]
    }

    private fun buildProgram(vs: String, fs: String): Int {
        fun compile(type: Int, src: String): Int {
            val s = GLES30.glCreateShader(type)
            GLES30.glShaderSource(s, src)
            GLES30.glCompileShader(s)
            val ok = IntArray(1)
            GLES30.glGetShaderiv(s, GLES30.GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) {
                val log = GLES30.glGetShaderInfoLog(s)
                GLES30.glDeleteShader(s)
                throw RuntimeException("Shader compile failed: $log")
            }
            return s
        }
        val p = GLES30.glCreateProgram()
        GLES30.glAttachShader(p, compile(GLES30.GL_VERTEX_SHADER, vs))
        GLES30.glAttachShader(p, compile(GLES30.GL_FRAGMENT_SHADER, fs))
        GLES30.glLinkProgram(p)
        val ok = IntArray(1)
        GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, ok, 0)
        if (ok[0] == 0) throw RuntimeException("Program link failed: ${GLES30.glGetProgramInfoLog(p)}")
        return p
    }

    companion object {
        private const val TAG = "OneovaArGl"
        private const val EGL_RECORDABLE_ANDROID = 0x3142

        /** vUv has a top-left origin; uFlip = -1 renders into FBOs row-0-first. */
        private const val VERTEX = """#version 300 es
in vec2 aPos;
uniform float uFlip;
uniform float uFlipX;
out vec2 vUv;
void main() {
  vUv = vec2(aPos.x * 0.5 + 0.5, 0.5 - aPos.y * 0.5);
  gl_Position = vec4(aPos.x * uFlipX, aPos.y * uFlip, 0.0, 1.0);
}
"""

        private const val CAMERA = """#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision mediump float;
uniform samplerExternalOES uCam;
uniform mat3 uCamMap;
in vec2 vUv;
out vec4 outColor;
vec4 cam(vec2 uv) { return texture(uCam, (uCamMap * vec3(uv, 1.0)).xy); }
"""

        private const val FRAGMENT_BLIT = CAMERA + """
void main() { outColor = vec4(cam(vUv).rgb, 1.0); }
"""

        /** The 3D layer (premultiplied RGBA from Filament's swap chain). */
        private const val FRAGMENT_LAYER = """#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision mediump float;
uniform samplerExternalOES uLayer;
uniform mat4 uLayerMat;
in vec2 vUv;
out vec4 outColor;
void main() { outColor = texture(uLayer, (uLayerMat * vec4(vUv.x, 1.0 - vUv.y, 0.0, 1.0)).xy); }
"""

        private const val FRAGMENT_BLUR = """#version 300 es
precision mediump float;
uniform sampler2D uSrc;
uniform vec2 uStep;
uniform float uWeights[5];
in vec2 vUv;
out vec4 outColor;
void main() {
  vec4 c = texture(uSrc, vUv) * uWeights[0];
  for (int i = 1; i < 5; i++) {
    vec2 o = uStep * float(i);
    c += (texture(uSrc, vUv + o) + texture(uSrc, vUv - o)) * uWeights[i];
  }
  outColor = c;
}
"""

        /** One camera inside a rounded rect of the target; discards outside it. */
        private const val FRAGMENT_PIP = CAMERA + """
precision highp float;
uniform vec4 uRect;
uniform vec4 uSrc;
uniform vec2 uRes;
uniform float uRadius;
uniform float uBorder;
void main() {
  vec2 l = (vUv - uRect.xy) / uRect.zw;
  if (l.x < 0.0 || l.y < 0.0 || l.x > 1.0 || l.y > 1.0) discard;
  vec2 size = uRect.zw * uRes;
  vec2 q = abs(l * size - size * 0.5) - (size * 0.5 - vec2(uRadius));
  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - uRadius;
  if (d > 0.0) discard;
  vec3 c = cam(uSrc.xy + l * uSrc.zw).rgb;
  if (uBorder > 0.0 && d > -uBorder) c = vec3(1.0);
  outColor = vec4(c, 1.0);
}
"""

        /**
         * Same layering as the Dart ArViewfinder: background (blurred camera,
         * scene image or camera) under the masked person, effects overlay on
         * the person; "add yourself" moves and scales the person layer.
         * uMode: 0 no segmentation, 1 blur, 2 replace, 3 replace without image.
         */
        private const val FRAGMENT_COMPOSITE = CAMERA + """
uniform int uMode;
uniform sampler2D uMask;
uniform sampler2D uBlur;
uniform sampler2D uBg;
uniform sampler2D uOverlay;
uniform int uHasOverlay;
uniform vec2 uBgScale;
uniform vec3 uPerson;
uniform sampler2D uSkinBlur;
uniform sampler2D uSkin;
uniform float uSmooth;
uniform vec4 uOutfit;
uniform float uNeckY;
uniform vec2 uMaskTexel;
uniform samplerExternalOES uBgVideo;
uniform int uBgVideoOn;
uniform mat4 uBgVideoMat;
// Edge-aware matte: in the soft band of the mask, neighbours whose camera
// colour matches this pixel vote more, so the edge snaps to real edges
// (hair, fingers) instead of the blurry low-res mask. Same as
// shaders/person_matte.frag in the preview.
float matte(vec2 p) {
  float a = texture(uMask, p).r;
  if (a <= 0.02 || a >= 0.98) return a;
  vec3 c0 = cam(p).rgb;
  float sum = a;
  float wsum = 1.0;
  for (int i = 0; i < 8; i++) {
    float ang = float(i) * 0.785398;
    vec2 o = vec2(cos(ang), sin(ang)) * uMaskTexel * 1.6;
    vec3 ci = cam(p + o).rgb;
    vec3 d = ci - c0;
    float w = exp(-dot(d, d) * 40.0);
    sum += texture(uMask, p + o).r * w;
    wsum += w;
  }
  return smoothstep(0.08, 0.92, sum / wsum);
}
vec3 toYcc(vec3 c) {
  float y = dot(c, vec3(0.299, 0.587, 0.114));
  return vec3(y, (c.b - y) * 0.564, (c.r - y) * 0.713);
}
vec3 fromYcc(vec3 q) {
  float r = q.x + 1.403 * q.z;
  float b = q.x + 1.773 * q.y;
  float g = (q.x - 0.299 * r - 0.114 * b) / 0.587;
  return vec3(r, g, b);
}
// Outfit colour: same maths as shaders/outfit_recolor.frag (preview).
vec3 outfit(vec3 c, vec2 uv) {
  if (uOutfit.a <= 0.0) return c;
  float person = texture(uMask, uv).r;
  float below = smoothstep(uNeckY - 0.02, uNeckY + 0.04, uv.y);
  vec3 s = toYcc(c);
  float skin = step(-0.2, s.y) * step(s.y, 0.0) * step(0.02, s.z) * step(s.z, 0.18);
  float w = person * below * (1.0 - skin) * uOutfit.a;
  vec3 t = toYcc(uOutfit.rgb);
  vec3 rec = clamp(fromYcc(vec3(s.x * 0.7 + t.x * 0.3, t.y, t.z)), 0.0, 1.0);
  return mix(c, rec, w);
}
// Skin smoothing: blend toward the blurred camera where the skin matte is set.
vec3 person(vec2 uv) {
  vec3 c = cam(uv).rgb;
  if (uSmooth > 0.0) {
    float k = texture(uSkin, uv).a * uSmooth * 0.75;
    c = mix(c, texture(uSkinBlur, uv).rgb, k);
  }
  return outfit(c, uv);
}
vec3 overlay(vec3 base, vec2 uv) {
  if (uHasOverlay == 0) return base;
  vec4 o = texture(uOverlay, uv);
  return o.rgb + base * (1.0 - o.a);
}
void main() {
  if (uMode == 0) {
    outColor = vec4(overlay(person(vUv), vUv), 1.0);
    return;
  }
  vec3 bg;
  if (uMode == 1) bg = texture(uBlur, vUv).rgb;
  else if (uMode == 2) {
    vec2 q = vec2(0.5) + (vUv - vec2(0.5)) * uBgScale;
    if (uBgVideoOn == 1) bg = texture(uBgVideo, (uBgVideoMat * vec4(q.x, 1.0 - q.y, 0.0, 1.0)).xy).rgb;
    else bg = texture(uBg, q).rgb;
  }
  else bg = cam(vUv).rgb;
  vec2 p = vec2(0.5) + (vUv - vec2(0.5) - uPerson.xy) / uPerson.z;
  if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0) {
    outColor = vec4(bg, 1.0);
    return;
  }
  float a = matte(p);
  vec3 c = mix(bg, person(p), a);
  outColor = vec4(overlay(c, p), 1.0);
}
"""
    }
}
