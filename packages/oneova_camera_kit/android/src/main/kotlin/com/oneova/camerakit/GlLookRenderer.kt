package com.oneova.camerakit

import android.graphics.Matrix
import android.opengl.EGL14
import android.opengl.EGLContext
import android.opengl.GLES11Ext
import android.opengl.GLES30
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.webrtc.RendererCommon
import org.webrtc.TextureBufferImpl
import org.webrtc.VideoFrame
import org.webrtc.YuvConverter
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Grades WebRTC texture frames with the generated Look shader. Every method
 * except [requestLook] runs on the capturer's GL thread (the
 * SurfaceTextureHelper thread, whose EGL context is current).
 *
 * Passes per frame: source (OES or RGB, with its transform matrix) → RGBA
 * texture, then the Look shader → a pooled output texture handed to WebRTC as
 * an RGB [TextureBufferImpl]. During a cross-fade the old look is drawn first
 * and the new one is blended over it with a constant alpha.
 */
internal class GlLookRenderer(private val maxInFlight: Int, private val stats: FrameStats) {
    private class GpuLook(val data: NativeLookData, val lutTex: Int, val curvesTex: Int)

    private class Output(val tex: Int, val fbo: Int, val width: Int, val height: Int) {
        @Volatile var inUse = false
        @Volatile var retired = false
    }

    @Volatile private var pending: LookRequest? = null

    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var handler: Handler? = null
    private var yuvConverter: YuvConverter? = null

    private var oesProgram = 0
    private var rgbProgram = 0
    private var lookProgram = 0
    private var lookLocations = IntArray(0)
    private var lookSamplers = IntArray(0)

    private var srcTex = 0
    private var srcFbo = 0
    private var srcWidth = 0
    private var srcHeight = 0

    private val pool = ArrayList<Output>()
    private var current: GpuLook? = null
    private var fadeFrom: GpuLook? = null
    private var fading = false
    private var fadeStartNs = 0L
    private var fadeDurationNs = 0L

    /** Our previous output frame; released once WebRTC has consumed it. */
    private var lastOutput: VideoFrame? = null
    private var disposed = false
    private var loggedError = false

    private val quad: FloatBuffer = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply { put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)); position(0) }

    /** Called from any thread; picked up on the next frame. */
    fun requestLook(request: LookRequest) {
        pending = request
    }

    /** Returns the graded frame, or [frame] itself when it cannot be graded. */
    fun process(frame: VideoFrame): VideoFrame {
        // WebRTC's sink consumed the previous output synchronously.
        lastOutput?.release()
        lastOutput = null

        val buffer = frame.buffer as? VideoFrame.TextureBuffer
            ?: return passThrough(frame, "cpu_buffer")
        val ctx = EGL14.eglGetCurrentContext()
        val looper = Looper.myLooper()
        if (ctx == EGL14.EGL_NO_CONTEXT || looper == null) return passThrough(frame, "no_gl_context")

        return try {
            if (ctx != context) setUp(ctx, looper)
            applyPending()
            if (current == null && !fading) return passThrough(frame, "no_look")

            val w = buffer.width
            val h = buffer.height
            val start = System.nanoTime()
            val out = acquireOutput(w, h) ?: return passThrough(frame, "output_pool_exhausted")
            drawSource(buffer, w, h)

            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, out.fbo)
            GLES30.glViewport(0, 0, w, h)
            if (fading) {
                val t = ((System.nanoTime() - fadeStartNs).toDouble() / fadeDurationNs).coerceIn(0.0, 1.0)
                drawLookOrSource(fadeFrom, w, h)
                GLES30.glEnable(GLES30.GL_BLEND)
                GLES30.glBlendColor(0f, 0f, 0f, t.toFloat())
                GLES30.glBlendFunc(GLES30.GL_CONSTANT_ALPHA, GLES30.GL_ONE_MINUS_CONSTANT_ALPHA)
                drawLookOrSource(current, w, h)
                GLES30.glDisable(GLES30.GL_BLEND)
                if (t >= 1.0) endFade()
            } else {
                drawLookOrSource(current, w, h)
            }
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
            // The encoder and renderers read this texture from other shared
            // contexts, so the frame must be complete before it is handed on.
            GLES30.glFinish()
            checkGl("frame")

            out.inUse = true
            val graded = TextureBufferImpl(
                w, h, VideoFrame.TextureBuffer.Type.RGB, out.tex, Matrix(), handler, yuvConverter,
            ) { onOutputReleased(out) }
            val result = VideoFrame(graded, frame.rotation, frame.timestampNs)
            lastOutput = result
            stats.graded((System.nanoTime() - start) / 1e6, w, h, current?.data?.id)
            result
        } catch (e: RuntimeException) {
            if (!loggedError) {
                Log.e(TAG, "Look render failed; sending original frames", e)
                loggedError = true
            }
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
            GLES30.glDisable(GLES30.GL_BLEND)
            passThrough(frame, "render_error")
        }
    }

    /** Frees GPU resources on the GL thread; in-flight outputs go when released. */
    fun dispose() {
        val h = handler
        if (h == null) {
            disposed = true
            return
        }
        h.post {
            disposed = true
            lastOutput?.release()
            lastOutput = null
            if (context == EGL14.eglGetCurrentContext()) {
                deleteLook(current)
                deleteLook(fadeFrom)
                current = null
                fadeFrom = null
                deletePrograms()
                deleteSource()
                for (o in pool.toList()) {
                    o.retired = true
                    if (!o.inUse) deleteOutput(o)
                }
            }
            releaseConverterIfIdle()
        }
    }

    private fun passThrough(frame: VideoFrame, reason: String): VideoFrame {
        stats.passedThrough(reason)
        return frame
    }

    private fun setUp(ctx: EGLContext, looper: Looper) {
        if (context != EGL14.EGL_NO_CONTEXT) {
            // The capturer restarted with a new context: rebuild everything there.
            Log.w(TAG, "GL context changed; rebuilding look resources")
            pool.clear()
            srcTex = 0
            srcFbo = 0
            srcWidth = 0
            srcHeight = 0
            val keep = current?.data
            current = null
            fadeFrom = null
            fading = false
            if (pending == null && keep != null) pending = LookRequest(keep, 0)
        }
        context = ctx
        handler = Handler(looper)
        if (yuvConverter == null) yuvConverter = YuvConverter()

        oesProgram = buildProgram(SOURCE_VERTEX, SOURCE_FRAGMENT_OES)
        rgbProgram = buildProgram(SOURCE_VERTEX, SOURCE_FRAGMENT_RGB)
        lookProgram = buildProgram(LOOK_VERTEX, LookEngineShader.FRAGMENT)
        lookLocations = IntArray(LookEngineShader.UNIFORMS.size) {
            GLES30.glGetUniformLocation(lookProgram, LookEngineShader.UNIFORMS[it].name)
        }
        lookSamplers = IntArray(LookEngineShader.SAMPLERS.size) {
            GLES30.glGetUniformLocation(lookProgram, LookEngineShader.SAMPLERS[it])
        }
    }

    private fun applyPending() {
        val req = pending ?: return
        pending = null
        if (fading) endFade()
        val next = req.look?.let { uploadLook(it) }
        if (current == null && next == null) return
        fadeFrom = current
        current = next
        if (req.crossFadeMs > 0) {
            fading = true
            fadeStartNs = System.nanoTime()
            fadeDurationNs = req.crossFadeMs * 1_000_000L
        } else {
            deleteLook(fadeFrom)
            fadeFrom = null
        }
    }

    private fun endFade() {
        fading = false
        deleteLook(fadeFrom)
        fadeFrom = null
    }

    private fun uploadLook(data: NativeLookData): GpuLook {
        val lut = createTexture(data.lutSize * data.lutSize, data.lutSize, ByteBuffer.wrap(data.lutAtlas))
        val curves = createTexture(
            NativeLookData.CURVES_WIDTH, NativeLookData.CURVES_HEIGHT, ByteBuffer.wrap(data.curves),
        )
        checkGl("upload look")
        return GpuLook(data, lut, curves)
    }

    private fun deleteLook(look: GpuLook?) {
        look ?: return
        GLES30.glDeleteTextures(2, intArrayOf(look.lutTex, look.curvesTex), 0)
    }

    private fun drawSource(buffer: VideoFrame.TextureBuffer, w: Int, h: Int) {
        if (w != srcWidth || h != srcHeight) {
            deleteSource()
            srcTex = createTexture(w, h, null)
            srcFbo = createFramebuffer(srcTex)
            srcWidth = w
            srcHeight = h
        }
        val oes = buffer.type == VideoFrame.TextureBuffer.Type.OES
        val program = if (oes) oesProgram else rgbProgram
        val matrix = RendererCommon.convertMatrixFromAndroidGraphicsMatrix(buffer.transformMatrix)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, srcFbo)
        GLES30.glViewport(0, 0, w, h)
        drawCopy(program, if (oes) GLES11Ext.GL_TEXTURE_EXTERNAL_OES else GLES30.GL_TEXTURE_2D, buffer.textureId, matrix)
    }

    /** Draws [look], or the ungraded source when [look] is null. */
    private fun drawLookOrSource(look: GpuLook?, w: Int, h: Int) {
        if (look == null) {
            drawCopy(rgbProgram, GLES30.GL_TEXTURE_2D, srcTex, IDENTITY)
            return
        }
        GLES30.glUseProgram(lookProgram)
        val u = look.data.uniforms
        LookEngineShader.UNIFORMS.forEachIndexed { i, uniform ->
            val loc = lookLocations[i]
            if (loc < 0) return@forEachIndexed
            if (uniform.name == "uSize") {
                GLES30.glUniform2f(loc, w.toFloat(), h.toFloat())
                return@forEachIndexed
            }
            when (uniform.components) {
                1 -> GLES30.glUniform1fv(loc, 1, u, uniform.offset)
                2 -> GLES30.glUniform2fv(loc, 1, u, uniform.offset)
                3 -> GLES30.glUniform3fv(loc, 1, u, uniform.offset)
                else -> GLES30.glUniform4fv(loc, 1, u, uniform.offset)
            }
        }
        val textures = intArrayOf(srcTex, look.lutTex, look.curvesTex)
        for (unit in textures.indices) {
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + unit)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textures[unit])
            if (lookSamplers[unit] >= 0) GLES30.glUniform1i(lookSamplers[unit], unit)
        }
        drawQuad(lookProgram)
        for (unit in textures.indices.reversed()) {
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + unit)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, 0)
        }
        GLES30.glUseProgram(0)
    }

    private fun drawCopy(program: Int, target: Int, texture: Int, matrix: FloatArray) {
        GLES30.glUseProgram(program)
        GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(program, "uTexMatrix"), 1, false, matrix, 0)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(target, texture)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(program, "uSource"), 0)
        drawQuad(program)
        GLES30.glBindTexture(target, 0)
        GLES30.glUseProgram(0)
    }

    private fun drawQuad(program: Int) {
        val pos = GLES30.glGetAttribLocation(program, "aPosition")
        GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, 0)
        GLES30.glEnableVertexAttribArray(pos)
        GLES30.glVertexAttribPointer(pos, 2, GLES30.GL_FLOAT, false, 0, quad)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        GLES30.glDisableVertexAttribArray(pos)
    }

    private fun acquireOutput(w: Int, h: Int): Output? {
        for (o in pool.toList()) {
            if (o.width != w || o.height != h) {
                o.retired = true
                if (!o.inUse) deleteOutput(o)
            }
        }
        pool.firstOrNull { !it.inUse && !it.retired }?.let { return it }
        if (pool.count { !it.retired } >= maxInFlight) return null
        val tex = createTexture(w, h, null)
        return Output(tex, createFramebuffer(tex), w, h).also { pool.add(it) }
    }

    /** Runs on whichever thread drops the last reference to the frame. */
    private fun onOutputReleased(out: Output) {
        out.inUse = false
        if (out.retired || disposed) {
            handler?.post {
                if (!out.inUse && context == EGL14.eglGetCurrentContext()) deleteOutput(out)
                if (disposed) releaseConverterIfIdle()
            }
        }
    }

    private fun releaseConverterIfIdle() {
        if (pool.none { it.inUse }) {
            yuvConverter?.release()
            yuvConverter = null
        }
    }

    private fun deleteOutput(o: Output) {
        if (!pool.remove(o)) return
        GLES30.glDeleteFramebuffers(1, intArrayOf(o.fbo), 0)
        GLES30.glDeleteTextures(1, intArrayOf(o.tex), 0)
    }

    private fun deleteSource() {
        if (srcFbo != 0) GLES30.glDeleteFramebuffers(1, intArrayOf(srcFbo), 0)
        if (srcTex != 0) GLES30.glDeleteTextures(1, intArrayOf(srcTex), 0)
        srcFbo = 0
        srcTex = 0
        srcWidth = 0
        srcHeight = 0
    }

    private fun deletePrograms() {
        for (p in intArrayOf(oesProgram, rgbProgram, lookProgram)) if (p != 0) GLES30.glDeleteProgram(p)
        oesProgram = 0
        rgbProgram = 0
        lookProgram = 0
    }

    private fun createTexture(w: Int, h: Int, pixels: ByteBuffer?): Int {
        val ids = IntArray(1)
        GLES30.glGenTextures(1, ids, 0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, ids[0])
        // LUT/curve lookups address texel centres, so nearest is exact; the
        // source copy samples at matching resolution.
        val filter = if (pixels != null) GLES30.GL_NEAREST else GLES30.GL_LINEAR
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, filter)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, filter)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glPixelStorei(GLES30.GL_UNPACK_ALIGNMENT, 1)
        GLES30.glTexImage2D(
            GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, w, h, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, pixels,
        )
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, 0)
        return ids[0]
    }

    private fun createFramebuffer(tex: Int): Int {
        val ids = IntArray(1)
        GLES30.glGenFramebuffers(1, ids, 0)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, ids[0])
        GLES30.glFramebufferTexture2D(
            GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, tex, 0,
        )
        val status = GLES30.glCheckFramebufferStatus(GLES30.GL_FRAMEBUFFER)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        check(status == GLES30.GL_FRAMEBUFFER_COMPLETE) { "Framebuffer incomplete: $status" }
        return ids[0]
    }

    private fun buildProgram(vertex: String, fragment: String): Int {
        val vs = compile(GLES30.GL_VERTEX_SHADER, vertex)
        val fs = compile(GLES30.GL_FRAGMENT_SHADER, fragment)
        val program = GLES30.glCreateProgram()
        GLES30.glAttachShader(program, vs)
        GLES30.glAttachShader(program, fs)
        GLES30.glLinkProgram(program)
        GLES30.glDeleteShader(vs)
        GLES30.glDeleteShader(fs)
        val status = IntArray(1)
        GLES30.glGetProgramiv(program, GLES30.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES30.glGetProgramInfoLog(program)
            GLES30.glDeleteProgram(program)
            throw IllegalStateException("Look program link failed: $log")
        }
        return program
    }

    private fun compile(type: Int, source: String): Int {
        val shader = GLES30.glCreateShader(type)
        GLES30.glShaderSource(shader, source)
        GLES30.glCompileShader(shader)
        val status = IntArray(1)
        GLES30.glGetShaderiv(shader, GLES30.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES30.glGetShaderInfoLog(shader)
            GLES30.glDeleteShader(shader)
            throw IllegalStateException("Look shader compile failed: $log")
        }
        return shader
    }

    private fun checkGl(op: String) {
        val err = GLES30.glGetError()
        check(err == GLES30.GL_NO_ERROR) { "GL error 0x${Integer.toHexString(err)} in $op" }
    }

    private companion object {
        const val TAG = "OneovaLookRenderer"

        val IDENTITY = floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f)

        const val SOURCE_VERTEX = """#version 300 es
in vec2 aPosition;
uniform mat4 uTexMatrix;
out vec2 vUv;
void main() {
    vUv = (uTexMatrix * vec4(aPosition * 0.5 + 0.5, 0.0, 1.0)).xy;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
"""

        const val SOURCE_FRAGMENT_OES = """#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision highp float;
uniform samplerExternalOES uSource;
in vec2 vUv;
out vec4 fragColor;
void main() { fragColor = vec4(texture(uSource, vUv).rgb, 1.0); }
"""

        const val SOURCE_FRAGMENT_RGB = """#version 300 es
precision highp float;
uniform sampler2D uSource;
in vec2 vUv;
out vec4 fragColor;
void main() { fragColor = vec4(texture(uSource, vUv).rgb, 1.0); }
"""

        // Feeds the Look shader's FlutterFragCoord equivalent: pixel centres
        // of the source frame, in the same orientation as the source texture.
        val LOOK_VERTEX = """#version 300 es
in vec2 aPosition;
uniform highp vec2 uSize;
out highp vec2 ${LookEngineShader.FRAG_COORD_VARYING};
void main() {
    ${LookEngineShader.FRAG_COORD_VARYING} = (aPosition * 0.5 + 0.5) * uSize;
    gl_Position = vec4(aPosition, 0.0, 1.0);
}
"""
    }
}
