package com.oneova.camerakit.ar

import android.graphics.Bitmap
import android.graphics.Canvas
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
    val handler = Handler(thread.looper)
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
    private var crop: Rect? = null
    @Volatile var mirror = false

    /** Upright output size (the preview resolution, rotated). */
    var outWidth = 0
        private set
    var outHeight = 0
        private set

    private val texMatrix = FloatArray(16)
    private val camMap = FloatArray(9)

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
    private val blurTex = IntArray(2)
    private val blurFbo = IntArray(2)
    private var blurSize = Size(0, 0)

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
                updateOutputSize()
            }
            request.provideSurface(surface, executor) {
                // The camera is done with this surface.
                if (input === next) input = null
                makeCurrent(pbuffer)
                next.st.release()
                next.surface.release()
                GLES30.glDeleteTextures(1, intArrayOf(next.tex), 0)
            }
            updateOutputSize()
        }
    }

    private fun updateOutputSize() {
        val inp = input ?: return
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

            if (previewSurface != EGL14.EGL_NO_SURFACE) {
                GLES30.glViewport(0, 0, outWidth, outHeight)
                drawBlit(frameInput.tex)
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
    private fun computeCamMap(size: Size) {
        val c = crop ?: Rect(0, 0, size.width, size.height)
        fun map(u0: Float, v: Float): FloatArray {
            val u = if (mirror) 1 - u0 else u0
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
            val rec = ArVideoRecorder(file, size.width, size.height, 30, withAudio, recordStartNs)
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
        bindQuad(blitProgram, flip = -1f)
        bindOes(blitProgram, camTex)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        val pixels = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())
        GLES30.glReadPixels(0, 0, w, h, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, pixels)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        GLES30.glDeleteFramebuffers(1, fbo, 0)
        GLES30.glDeleteTextures(1, intArrayOf(tex), 0)
        Thread({
            val ok = runCatching {
                val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                bmp.copyPixelsFromBuffer(pixels.rewind())
                file.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 95, it) }
                bmp.recycle()
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
        if (segmenting && scene.backgroundMode == 1) renderBlur(camTex)
        val hasOverlay = updateOverlay(rec.width, rec.height)

        makeCurrent(encoderSurface)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        GLES30.glViewport(0, 0, rec.width, rec.height)
        drawComposite(camTex, segmenting, hasOverlay, rec.width, rec.height)
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
        val drawsSomething = scene.effects.any { it.kind == "makeup" || images.containsKey(it.id) }
        if (!drawsSomething) return false
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
        ArOverlayPainter.paint(Canvas(bmp), ow.toFloat(), oh.toFloat(), latest, scene.effects, images, world)
        if (overlayTex == 0) overlayTex = gen2dTexture()
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, overlayTex)
        GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, bmp, 0)
        return true
    }

    /** Quarter-size camera, then a separable gaussian (two passes). */
    private fun renderBlur(camTex: Int) {
        val bw = (outWidth / 4).coerceAtLeast(2)
        val bh = (outHeight / 4).coerceAtLeast(2)
        if (blurSize.width != bw || blurSize.height != bh) {
            if (blurTex[0] != 0) {
                GLES30.glDeleteTextures(2, blurTex, 0)
                GLES30.glDeleteFramebuffers(2, blurFbo, 0)
            }
            GLES30.glGenFramebuffers(2, blurFbo, 0)
            for (i in 0..1) {
                blurTex[i] = gen2dTexture()
                GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, blurTex[i])
                GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, bw, bh, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null)
                GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, blurFbo[i])
                GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, blurTex[i], 0)
            }
            blurSize = Size(bw, bh)
        }
        GLES30.glViewport(0, 0, bw, bh)
        // Camera → blurTex[0].
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, blurFbo[0])
        GLES30.glUseProgram(cameraToRgbProgram)
        bindQuad(cameraToRgbProgram, flip = -1f)
        bindOes(cameraToRgbProgram, camTex)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        // Sigma is in preview pixels (the Dart viewfinder's box); the blur runs at 1/4.
        val sigma = (scene.blurSigma / 4f).coerceIn(0.5f, 12f)
        blurPass(blurTex[0], blurFbo[1], 1f / bw, 0f, sigma)
        blurPass(blurTex[1], blurFbo[0], 0f, 1f / bh, sigma)
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

    private fun drawComposite(camTex: Int, segmenting: Boolean, hasOverlay: Boolean, w: Int, h: Int) {
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
        val mode = if (!segmenting) 0 else if (scene.backgroundMode == 2 && bgTex == 0) 3 else scene.backgroundMode
        GLES30.glUniform1i(loc("uMode"), mode)
        tex(1, if (segmenting) maskTex else 0, "uMask")
        tex(2, if (mode == 1) blurTex[0] else 0, "uBlur")
        tex(3, if (mode == 2) bgTex else 0, "uBg")
        tex(4, if (hasOverlay) overlayTex else 0, "uOverlay")
        GLES30.glUniform1i(loc("uHasOverlay"), if (hasOverlay) 1 else 0)
        if (mode == 2) {
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
                images.values.forEach { it.recycle() }
                images.clear()
                overlayBitmap?.recycle()
                overlayBitmap = null
                EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                EGL14.eglDestroySurface(display, pbuffer)
                EGL14.eglDestroyContext(display, context)
                EGL14.eglTerminate(display)
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
out vec2 vUv;
void main() {
  vUv = vec2(aPos.x * 0.5 + 0.5, 0.5 - aPos.y * 0.5);
  gl_Position = vec4(aPos.x, aPos.y * uFlip, 0.0, 1.0);
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
vec3 overlay(vec3 base, vec2 uv) {
  if (uHasOverlay == 0) return base;
  vec4 o = texture(uOverlay, uv);
  return o.rgb + base * (1.0 - o.a);
}
void main() {
  if (uMode == 0) {
    outColor = vec4(overlay(cam(vUv).rgb, vUv), 1.0);
    return;
  }
  vec3 bg;
  if (uMode == 1) bg = texture(uBlur, vUv).rgb;
  else if (uMode == 2) bg = texture(uBg, vec2(0.5) + (vUv - vec2(0.5)) * uBgScale).rgb;
  else bg = cam(vUv).rgb;
  vec2 p = vec2(0.5) + (vUv - vec2(0.5) - uPerson.xy) / uPerson.z;
  if (p.x < 0.0 || p.y < 0.0 || p.x > 1.0 || p.y > 1.0) {
    outColor = vec4(bg, 1.0);
    return;
  }
  float a = texture(uMask, p).r;
  vec3 c = mix(bg, cam(p).rgb, a);
  outColor = vec4(overlay(c, p), 1.0);
}
"""
    }
}
