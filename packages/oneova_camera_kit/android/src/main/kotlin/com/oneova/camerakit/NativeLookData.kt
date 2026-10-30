package com.oneova.camerakit

/** A compiled look as sent by `NativeLook.toMap()` on the Dart side. */
internal class NativeLookData(
    val id: String,
    val uniforms: FloatArray,
    val lutAtlas: ByteArray,
    val lutSize: Int,
    val curves: ByteArray,
) {
    companion object {
        const val CURVES_WIDTH = 256
        const val CURVES_HEIGHT = 2

        fun fromMap(map: Map<*, *>): NativeLookData {
            val id = map["id"] as? String ?: throw IllegalArgumentException("look.id missing")
            val uniforms = map["uniforms"] as? FloatArray
                ?: (map["uniforms"] as? DoubleArray)?.let { d -> FloatArray(d.size) { d[it].toFloat() } }
                ?: throw IllegalArgumentException("look.uniforms missing")
            val lut = map["lutAtlas"] as? ByteArray ?: throw IllegalArgumentException("look.lutAtlas missing")
            val lutSize = (map["lutSize"] as? Number)?.toInt() ?: throw IllegalArgumentException("look.lutSize missing")
            val curves = map["curves"] as? ByteArray ?: throw IllegalArgumentException("look.curves missing")
            require(uniforms.size == LookEngineShader.FLOAT_COUNT) {
                "look.uniforms has ${uniforms.size} floats, shader expects ${LookEngineShader.FLOAT_COUNT}"
            }
            require(lutSize >= 2 && lut.size == lutSize * lutSize * lutSize * 4) { "look.lutAtlas size mismatch" }
            require(curves.size == CURVES_WIDTH * CURVES_HEIGHT * 4) { "look.curves size mismatch" }
            return NativeLookData(id, uniforms, lut, lutSize, curves)
        }
    }
}

/** A look switch requested from the platform thread, applied on the GL thread. */
internal class LookRequest(val look: NativeLookData?, val crossFadeMs: Int)
