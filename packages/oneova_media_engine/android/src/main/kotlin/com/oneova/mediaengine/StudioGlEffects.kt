package com.oneova.mediaengine

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** A compiled Oneova Look (same uniforms/textures as the Flutter preview). */
internal class LookSpec(
    val uniforms: FloatArray,
    val lut: ByteArray,
    val lutSize: Int,
    val curves: ByteArray,
) {
    companion object {
        fun fromMap(m: Map<String, Any?>?): LookSpec? {
            if (m == null) return null
            val uniforms = (m["uniforms"] as? List<*>)?.map { (it as Number).toFloat() }?.toFloatArray()
                ?: (m["uniforms"] as? FloatArray)
                ?: (m["uniforms"] as? DoubleArray)?.let { d -> FloatArray(d.size) { d[it].toFloat() } }
                ?: return null
            val lut = m["lut"] as? ByteArray ?: return null
            val lutSize = (m["lutSize"] as? Number)?.toInt() ?: return null
            val curves = m["curves"] as? ByteArray ?: return null
            if (uniforms.size != StudioLookShader.FLOAT_COUNT) return null
            if (lut.size != lutSize * lutSize * lutSize * 4 || curves.size != 256 * 2 * 4) return null
            return LookSpec(uniforms, lut, lutSize, curves)
        }
    }
}

/** Runs the Oneova Look engine on every frame of a clip. */
internal class LookGlEffect(private val spec: LookSpec) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram = LookProgram(spec)
}

private fun uploadRgba(width: Int, height: Int, data: ByteArray): Int {
    val ids = IntArray(1)
    GLES20.glGenTextures(1, ids, 0)
    GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, ids[0])
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
    GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
    val buf = ByteBuffer.allocateDirect(data.size).order(ByteOrder.nativeOrder()).put(data)
    buf.position(0)
    GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 1)
    GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height, 0, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buf)
    GlUtil.checkGlError()
    return ids[0]
}

private class LookProgram(private val spec: LookSpec) : BaseGlShaderProgram(false, 1) {
    private var program: GlProgram? = null
    private var lutTex = 0
    private var curvesTex = 0
    private var width = 0
    private var height = 0

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth
        height = inputHeight
        if (program == null) {
            try {
                val p = GlProgram(StudioLookShader.VERTEX, StudioLookShader.FRAGMENT)
                p.setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE)
                program = p
                val n = spec.lutSize
                lutTex = uploadRgba(n * n, n, spec.lut)
                curvesTex = uploadRgba(256, 2, spec.curves)
            } catch (e: GlUtil.GlException) {
                throw VideoFrameProcessingException(e)
            }
        }
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        val p = program ?: return
        try {
            p.use()
            p.setSamplerTexIdUniform("uTexture", inputTexId, 0)
            p.setSamplerTexIdUniform("uLut", lutTex, 1)
            p.setSamplerTexIdUniform("uCurves", curvesTex, 2)
            for (u in StudioLookShader.UNIFORMS) {
                val v = if (u.name == "uSize") {
                    floatArrayOf(width.toFloat(), height.toFloat())
                } else {
                    spec.uniforms.copyOfRange(u.offset, u.offset + u.components)
                }
                p.setFloatsUniformIfPresent(u.name, v)
            }
            p.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try {
            program?.delete()
            if (lutTex != 0) GlUtil.deleteTexture(lutTex)
            if (curvesTex != 0) GlUtil.deleteTexture(curvesTex)
        } catch (_: GlUtil.GlException) {
        }
    }
}

/** One timed Studio effect, in clip-local output time. */
internal class FxWindow(
    val type: Float,
    val amount: Float,
    val startUs: Long,
    val endUs: Long,
    /** Effect time (seconds) at the window start, so effects split across clips continue smoothly. */
    val timeOffsetS: Float,
    /** Length of the whole effect layer in µs (for uProgress). */
    val layerUs: Long,
    /** µs of the layer already played before this clip's window starts. */
    val layerOffsetUs: Long,
)

/** Applies [windows] (at most one active at a time per pass) to a clip. */
internal class FxGlEffect(private val windows: List<FxWindow>) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram = FxProgram(windows)
}

private class FxProgram(private val windows: List<FxWindow>) : BaseGlShaderProgram(false, 1) {
    private var program: GlProgram? = null
    private var width = 0
    private var height = 0
    private var baseUs = Long.MIN_VALUE

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth
        height = inputHeight
        if (program == null) {
            try {
                val p = GlProgram(StudioLookShader.VERTEX, StudioFxShader.FRAGMENT)
                p.setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE)
                program = p
            } catch (e: GlUtil.GlException) {
                throw VideoFrameProcessingException(e)
            }
        }
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        val p = program ?: return
        if (baseUs == Long.MIN_VALUE) baseUs = presentationTimeUs
        val local = presentationTimeUs - baseUs
        val w = windows.firstOrNull { local >= it.startUs && local < it.endUs }
        try {
            p.use()
            p.setSamplerTexIdUniform("uTexture", inputTexId, 0)
            p.setFloatsUniformIfPresent("uSize", floatArrayOf(width.toFloat(), height.toFloat()))
            if (w == null) {
                p.setFloatsUniformIfPresent("uType", floatArrayOf(0f))
                p.setFloatsUniformIfPresent("uAmount", floatArrayOf(0f))
                p.setFloatsUniformIfPresent("uTime", floatArrayOf(0f))
                p.setFloatsUniformIfPresent("uProgress", floatArrayOf(0f))
            } else {
                val inLayerUs = local - w.startUs + w.layerOffsetUs
                p.setFloatsUniformIfPresent("uType", floatArrayOf(w.type))
                p.setFloatsUniformIfPresent("uAmount", floatArrayOf(w.amount))
                p.setFloatsUniformIfPresent("uTime", floatArrayOf(w.timeOffsetS + (local - w.startUs) / 1_000_000f))
                val progress = if (w.layerUs > 0) (inLayerUs.toFloat() / w.layerUs).coerceIn(0f, 1f) else 0f
                p.setFloatsUniformIfPresent("uProgress", floatArrayOf(progress))
            }
            p.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try {
            program?.delete()
        } catch (_: GlUtil.GlException) {
        }
    }
}

/**
 * Face & skin retouch for one clip. [params] = smooth, even, bright, warm,
 * eyes, teeth, slim, bigEyes, nose, chin. Faces are keyframed in clip-local
 * output time: [keysMs][i] has 32 floats in [faces] (two faces x 4 vec4).
 */
internal class RetouchSpec(val params: FloatArray, val keysMs: LongArray, val faces: FloatArray) {
    companion object {
        private fun floats(v: Any?): FloatArray? = when (v) {
            is FloatArray -> v
            is DoubleArray -> FloatArray(v.size) { v[it].toFloat() }
            is List<*> -> v.map { (it as Number).toFloat() }.toFloatArray()
            else -> null
        }

        fun fromMap(m: Map<String, Any?>?): RetouchSpec? {
            if (m == null) return null
            val params = floats(m["params"]) ?: return null
            if (params.size < 10) return null
            val keys = when (val k = m["keysMs"]) {
                is LongArray -> k
                is IntArray -> LongArray(k.size) { k[it].toLong() }
                is List<*> -> k.map { (it as Number).toLong() }.toLongArray()
                else -> LongArray(0)
            }
            val faces = floats(m["faces"]) ?: FloatArray(0)
            if (faces.size != keys.size * 32) return RetouchSpec(params, LongArray(0), FloatArray(0))
            return RetouchSpec(params, keys, faces)
        }
    }
}

internal class RetouchGlEffect(private val spec: RetouchSpec) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram = RetouchProgram(spec)
}

private class RetouchProgram(private val spec: RetouchSpec) : BaseGlShaderProgram(false, 1) {
    private var program: GlProgram? = null
    private var width = 0
    private var height = 0
    private var baseUs = Long.MIN_VALUE
    private val face = FloatArray(32)

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth
        height = inputHeight
        if (program == null) {
            try {
                val p = GlProgram(StudioLookShader.VERTEX, StudioRetouchShader.FRAGMENT)
                p.setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), GlUtil.HOMOGENEOUS_COORDINATE_VECTOR_SIZE)
                program = p
            } catch (e: GlUtil.GlException) {
                throw VideoFrameProcessingException(e)
            }
        }
        return Size(inputWidth, inputHeight)
    }

    /** Faces at [ms]: linear between keyframes; a face missing on either side switches off. */
    private fun facesAt(ms: Long) {
        val keys = spec.keysMs
        face.fill(0f)
        if (keys.isEmpty()) return
        var i = 0
        while (i < keys.size - 1 && keys[i + 1] <= ms) i++
        val j = (i + 1).coerceAtMost(keys.size - 1)
        val span = (keys[j] - keys[i]).toFloat()
        val k = if (j == i || span <= 0f) 0f else ((ms - keys[i]) / span).coerceIn(0f, 1f)
        for (f in 0 until 2) {
            val a = i * 32 + f * 16
            val b = j * 32 + f * 16
            val va = spec.faces[a]
            val vb = spec.faces[b]
            if (va < 0.5f && vb < 0.5f) continue
            val src = if (va < 0.5f) b else if (vb < 0.5f) a else -1
            for (n in 0 until 16) {
                face[f * 16 + n] = if (src >= 0) spec.faces[src + n] else spec.faces[a + n] + (spec.faces[b + n] - spec.faces[a + n]) * k
            }
            face[f * 16] = 1f
        }
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        val p = program ?: return
        if (baseUs == Long.MIN_VALUE) baseUs = presentationTimeUs
        facesAt((presentationTimeUs - baseUs) / 1000)
        val q = spec.params
        try {
            p.use()
            p.setSamplerTexIdUniform("uTexture", inputTexId, 0)
            p.setFloatsUniformIfPresent("uSize", floatArrayOf(width.toFloat(), height.toFloat()))
            p.setFloatsUniformIfPresent("uP0", floatArrayOf(q[0], q[1], q[2], q[3]))
            p.setFloatsUniformIfPresent("uP1", floatArrayOf(q[4], q[5], q[6], q[7]))
            p.setFloatsUniformIfPresent("uP2", floatArrayOf(q[8], q[9], 0f, 0f))
            val names = StudioRetouchShader.UNIFORMS
            for (n in 0 until 8) p.setFloatsUniformIfPresent(names[3 + n], face.copyOfRange(n * 4, n * 4 + 4))
            p.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try {
            program?.delete()
        } catch (_: GlUtil.GlException) {
        }
    }
}
