package com.oneova.camerakit.ar

import android.graphics.Bitmap
import android.opengl.GLES30
import android.opengl.GLUtils
import android.util.Log
import com.oneova.camerakit.LookEngineShader
import com.oneova.camerakit.NativeLookData
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * The camera's colour grade baked into what is captured: an optional
 * brightness/contrast colour matrix (Flutter `ColorFilter.matrix` layout)
 * followed by the Oneova Look (same generated shader, LUT atlas and curves as
 * the Flutter preview, Studio and Live), so photos and videos come out of the
 * camera already graded exactly like the viewfinder.
 *
 * GL thread only. The scene is first drawn into [beginScene]'s framebuffer,
 * then [finish] grades it into the target.
 */
internal class ArGradePass {
    private var look: NativeLookData? = null
    private var matrix: FloatArray? = null
    private var dirty = false

    private var lookProgram = 0
    private var matrixProgram = 0
    private var lookLocs = IntArray(0)
    private var lookSamplers = IntArray(0)
    private var lutTex = 0
    private var curvesTex = 0

    private val tex = IntArray(2)
    private val fbo = IntArray(2)
    private var w = 0
    private var h = 0

    private val quad: FloatBuffer = ByteBuffer.allocateDirect(8 * 4).order(ByteOrder.nativeOrder())
        .asFloatBuffer().apply { put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f)); position(0) }

    @Volatile var active = false
        private set

    /** Any thread: the grade to bake from the next frame on (nulls = none). */
    @Synchronized
    fun set(next: NativeLookData?, colorMatrix: FloatArray?) {
        look = next
        matrix = colorMatrix?.takeIf { it.size == 20 && !isIdentity(it) }
        dirty = true
        active = look != null || matrix != null
    }

    private fun isIdentity(m: FloatArray): Boolean {
        val id = floatArrayOf(1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f)
        return m.indices.all { kotlin.math.abs(m[it] - id[it]) < 1e-4f }
    }

    @Synchronized
    private fun sync() {
        if (lookProgram == 0) build()
        if (!dirty) return
        dirty = false
        if (lutTex != 0) GLES30.glDeleteTextures(2, intArrayOf(lutTex, curvesTex), 0)
        lutTex = 0
        curvesTex = 0
        val l = look ?: return
        lutTex = texture(l.lutSize * l.lutSize, l.lutSize, ByteBuffer.wrap(l.lutAtlas))
        curvesTex = texture(NativeLookData.CURVES_WIDTH, NativeLookData.CURVES_HEIGHT, ByteBuffer.wrap(l.curves))
    }

    private fun build() {
        lookProgram = program(LOOK_VERTEX, LookEngineShader.FRAGMENT)
        matrixProgram = program(COPY_VERTEX, MATRIX_FRAGMENT)
        lookLocs = IntArray(LookEngineShader.UNIFORMS.size) { GLES30.glGetUniformLocation(lookProgram, LookEngineShader.UNIFORMS[it].name) }
        lookSamplers = IntArray(LookEngineShader.SAMPLERS.size) { GLES30.glGetUniformLocation(lookProgram, LookEngineShader.SAMPLERS[it]) }
    }

    private fun ensureTargets(width: Int, height: Int) {
        if (width == w && height == h && tex[0] != 0) return
        releaseTargets()
        GLES30.glGenTextures(2, tex, 0)
        GLES30.glGenFramebuffers(2, fbo, 0)
        for (i in 0..1) {
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, tex[i])
            params()
            GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, width, height, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null)
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fbo[i])
            GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, tex[i], 0)
        }
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        w = width
        h = height
    }

    /** Binds an offscreen target of [width]×[height] for the scene. */
    fun beginScene(width: Int, height: Int) {
        sync()
        ensureTargets(width, height)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fbo[0])
        GLES30.glViewport(0, 0, width, height)
    }

    /** Grades the scene into [targetFbo] (0 = the current window surface). */
    fun finish(targetFbo: Int) {
        var src = tex[0]
        val m = matrix
        val l = look
        if (m != null) {
            val out = if (l == null) targetFbo else fbo[1]
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, out)
            GLES30.glViewport(0, 0, w, h)
            drawMatrix(src, m)
            src = tex[1]
        }
        if (l != null && lutTex != 0) {
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, targetFbo)
            GLES30.glViewport(0, 0, w, h)
            drawLook(src, l)
        } else if (m == null) {
            // Nothing to grade (look still uploading): copy through.
            GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, targetFbo)
            GLES30.glViewport(0, 0, w, h)
            drawMatrix(src, IDENTITY_MATRIX)
        }
    }

    /** Grades an upright still; returns a new bitmap (or the input when nothing to do). */
    fun gradeBitmap(src: Bitmap): Bitmap {
        if (!active) return src
        sync()
        val inTex = IntArray(1)
        GLES30.glGenTextures(1, inTex, 0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, inTex[0])
        params()
        GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, src, 0)
        ensureTargets(src.width, src.height)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, fbo[0])
        GLES30.glViewport(0, 0, w, h)
        drawMatrix(inTex[0], IDENTITY_MATRIX)
        // Ping-pong: grade fbo[0] → fbo[1] via a temporary third target.
        val outTex = IntArray(1)
        val outFbo = IntArray(1)
        GLES30.glGenTextures(1, outTex, 0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, outTex[0])
        params()
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, w, h, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, null)
        GLES30.glGenFramebuffers(1, outFbo, 0)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, outFbo[0])
        GLES30.glFramebufferTexture2D(GLES30.GL_FRAMEBUFFER, GLES30.GL_COLOR_ATTACHMENT0, GLES30.GL_TEXTURE_2D, outTex[0], 0)
        finish(outFbo[0])
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, outFbo[0])
        val pixels = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())
        GLES30.glReadPixels(0, 0, w, h, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, pixels)
        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, 0)
        GLES30.glDeleteFramebuffers(1, outFbo, 0)
        GLES30.glDeleteTextures(2, intArrayOf(outTex[0], inTex[0]), 0)
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        out.copyPixelsFromBuffer(pixels.rewind())
        return out
    }

    private fun drawMatrix(src: Int, m: FloatArray) {
        val p = matrixProgram
        GLES30.glUseProgram(p)
        // Row-major 4×5 → column-major mat4 + offset (0..255 like Flutter).
        val mat = FloatArray(16)
        for (r in 0..3) for (c in 0..3) mat[c * 4 + r] = m[r * 5 + c]
        GLES30.glUniformMatrix4fv(GLES30.glGetUniformLocation(p, "uM"), 1, false, mat, 0)
        GLES30.glUniform4f(GLES30.glGetUniformLocation(p, "uOff"), m[4] / 255f, m[9] / 255f, m[14] / 255f, m[19] / 255f)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, src)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(p, "uSrc"), 0)
        drawQuad(p)
    }

    private fun drawLook(src: Int, l: NativeLookData) {
        val p = lookProgram
        GLES30.glUseProgram(p)
        val u = l.uniforms
        LookEngineShader.UNIFORMS.forEachIndexed { i, uniform ->
            val loc = lookLocs[i]
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
        val textures = intArrayOf(src, lutTex, curvesTex)
        for (unit in textures.indices) {
            GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + unit)
            GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textures[unit])
            if (lookSamplers[unit] >= 0) GLES30.glUniform1i(lookSamplers[unit], unit)
        }
        drawQuad(p)
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
    }

    private fun drawQuad(program: Int) {
        val pos = GLES30.glGetAttribLocation(program, "aPosition")
        GLES30.glEnableVertexAttribArray(pos)
        GLES30.glVertexAttribPointer(pos, 2, GLES30.GL_FLOAT, false, 0, quad)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
        GLES30.glDisableVertexAttribArray(pos)
    }

    private fun params() {
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MIN_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_MAG_FILTER, GLES30.GL_LINEAR)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_S, GLES30.GL_CLAMP_TO_EDGE)
        GLES30.glTexParameteri(GLES30.GL_TEXTURE_2D, GLES30.GL_TEXTURE_WRAP_T, GLES30.GL_CLAMP_TO_EDGE)
    }

    private fun texture(width: Int, height: Int, pixels: ByteBuffer): Int {
        val t = IntArray(1)
        GLES30.glGenTextures(1, t, 0)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, t[0])
        params()
        GLES30.glTexImage2D(GLES30.GL_TEXTURE_2D, 0, GLES30.GL_RGBA8, width, height, 0, GLES30.GL_RGBA, GLES30.GL_UNSIGNED_BYTE, pixels)
        return t[0]
    }

    private fun program(vs: String, fs: String): Int {
        fun compile(type: Int, src: String): Int {
            val s = GLES30.glCreateShader(type)
            GLES30.glShaderSource(s, src)
            GLES30.glCompileShader(s)
            val ok = IntArray(1)
            GLES30.glGetShaderiv(s, GLES30.GL_COMPILE_STATUS, ok, 0)
            if (ok[0] == 0) {
                val log = GLES30.glGetShaderInfoLog(s)
                GLES30.glDeleteShader(s)
                throw RuntimeException("Grade shader: $log")
            }
            return s
        }
        val p = GLES30.glCreateProgram()
        GLES30.glAttachShader(p, compile(GLES30.GL_VERTEX_SHADER, vs))
        GLES30.glAttachShader(p, compile(GLES30.GL_FRAGMENT_SHADER, fs))
        GLES30.glLinkProgram(p)
        return p
    }

    private fun releaseTargets() {
        if (tex[0] != 0) GLES30.glDeleteTextures(2, tex, 0)
        if (fbo[0] != 0) GLES30.glDeleteFramebuffers(2, fbo, 0)
        tex.fill(0)
        fbo.fill(0)
        w = 0
        h = 0
    }

    fun release() {
        try {
            releaseTargets()
            if (lutTex != 0) GLES30.glDeleteTextures(2, intArrayOf(lutTex, curvesTex), 0)
            if (lookProgram != 0) GLES30.glDeleteProgram(lookProgram)
            if (matrixProgram != 0) GLES30.glDeleteProgram(matrixProgram)
        } catch (e: RuntimeException) {
            Log.w("OneovaArGrade", "Grade release failed", e)
        }
        lookProgram = 0
        matrixProgram = 0
        lutTex = 0
        curvesTex = 0
    }

    private companion object {
        val IDENTITY_MATRIX = floatArrayOf(1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f)

        const val COPY_VERTEX = """#version 300 es
in vec2 aPosition;
out vec2 vUv;
void main() {
  vUv = aPosition * 0.5 + 0.5;
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
"""

        const val MATRIX_FRAGMENT = """#version 300 es
precision highp float;
uniform sampler2D uSrc;
uniform mat4 uM;
uniform vec4 uOff;
in vec2 vUv;
out vec4 outColor;
void main() {
  vec4 c = texture(uSrc, vUv);
  outColor = vec4(clamp((uM * vec4(c.rgb, 1.0) + uOff).rgb, 0.0, 1.0), 1.0);
}
"""

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
