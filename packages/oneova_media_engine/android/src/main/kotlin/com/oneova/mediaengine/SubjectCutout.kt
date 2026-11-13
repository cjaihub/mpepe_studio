package com.oneova.mediaengine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Photo background removal for the Studio editor.
 *
 * ML Kit Subject Segmentation (on-device, every person and main subject in
 * the photo, clean hair edges) writes a PNG whose background is transparent.
 * If that model is not available yet (Play services downloads it on first
 * use), the bundled selfie segmenter is used instead.
 */
internal object SubjectCutout {
    private const val TAG = "OneovaCutout"

    fun cutout(context: Context, path: String, out: String, maxSide: Int): Map<String, Any> {
        val bmp = decodeUpright(path, maxSide)
        val w = bmp.width
        val h = bmp.height
        val image = InputImage.fromBitmap(bmp, 0)
        var method = "subject"
        val mask: FloatArray = try {
            val client = SubjectSegmentation.getClient(
                SubjectSegmenterOptions.Builder().enableForegroundConfidenceMask().build(),
            )
            try {
                val r = Tasks.await(client.process(image), 40, TimeUnit.SECONDS)
                val buf = r.foregroundConfidenceMask ?: throw IllegalStateException("no mask")
                FloatArray(w * h).also { buf.rewind(); buf.get(it) }
            } finally {
                client.close()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Subject segmentation unavailable, using the selfie model", e)
            method = "selfie"
            selfieMask(image, w, h)
        }

        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        for (i in px.indices) {
            val c = mask[i]
            val t = ((c - 0.3f) / 0.4f).coerceIn(0f, 1f)
            val a = (t * t * (3 - 2 * t) * 255f).roundToInt()
            px[i] = (a shl 24) or (px[i] and 0x00FFFFFF)
        }
        val outBmp = Bitmap.createBitmap(px, w, h, Bitmap.Config.ARGB_8888)
        File(out).outputStream().use { outBmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        outBmp.recycle()
        bmp.recycle()
        return mapOf("path" to out, "width" to w, "height" to h, "method" to method)
    }

    private fun selfieMask(image: InputImage, w: Int, h: Int): FloatArray {
        val seg = Segmentation.getClient(
            SelfieSegmenterOptions.Builder()
                .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
                .enableRawSizeMask()
                .build(),
        )
        try {
            val m = Tasks.await(seg.process(image), 30, TimeUnit.SECONDS)
            val src = m.buffer.apply { rewind() }.order(ByteOrder.nativeOrder()).asFloatBuffer()
            val mw = m.width
            val mh = m.height
            val outMask = FloatArray(w * h)
            for (y in 0 until h) {
                val sy = ((y + 0.5f) * mh / h).toInt().coerceIn(0, mh - 1)
                for (x in 0 until w) {
                    val sx = ((x + 0.5f) * mw / w).toInt().coerceIn(0, mw - 1)
                    outMask[y * w + x] = src.get(sy * mw + sx)
                }
            }
            return outMask
        } finally {
            seg.close()
        }
    }

    private fun decodeUpright(path: String, maxSide: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val raw = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: throw IllegalArgumentException("Could not read that photo")
        val rotation = runCatching {
            when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        }.getOrDefault(0)
        val scale = minOf(1f, maxSide.toFloat() / max(raw.width, raw.height))
        if (rotation == 0 && scale >= 1f) return raw.copy(Bitmap.Config.ARGB_8888, false).also { if (it !== raw) raw.recycle() }
        val m = Matrix().apply {
            postScale(scale, scale)
            postRotate(rotation.toFloat())
        }
        return Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, m, true).copy(Bitmap.Config.ARGB_8888, false)
            .also { raw.recycle() }
    }
}
