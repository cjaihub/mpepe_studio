package com.oneova.mediaengine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Flutter bridge for on-device media work:
 *  - probe / thumbnails / frame extraction (MediaMetadataRetriever)
 *  - inspect (container + per-track decoder support) and image normalizing
 *    (HEIC/HEIF/AVIF/GIF/BMP/huge photos -> upright JPEG or PNG)
 *  - export of an edited timeline ([TimelineExporter], Media3 Transformer)
 */
class OneovaMediaEnginePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private var progressSink: EventChannel.EventSink? = null
    private val io = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private var exporter: TimelineExporter? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "oneova_media_engine")
        channel.setMethodCallHandler(this)
        progressChannel = EventChannel(binding.binaryMessenger, "oneova_media_engine/progress")
        progressChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressSink = events
            }

            override fun onCancel(arguments: Any?) {
                progressSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        progressChannel.setStreamHandler(null)
        exporter?.cancel()
        exporter = null
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> background(result) { probe(call.argument<String>("path")!!) }
            "thumbnails" -> background(result) {
                thumbnails(
                    path = call.argument<String>("path")!!,
                    count = call.argument<Int>("count") ?: 8,
                    startMs = (call.argument<Number>("startMs") ?: 0).toLong(),
                    endMs = (call.argument<Number>("endMs") ?: 0).toLong(),
                    height = call.argument<Int>("height") ?: 120,
                    outDir = call.argument<String>("outDir")!!,
                )
            }
            "frame" -> background(result) {
                frame(
                    path = call.argument<String>("path")!!,
                    ms = (call.argument<Number>("ms") ?: 0).toLong(),
                    out = call.argument<String>("out")!!,
                    maxSide = call.argument<Int>("maxSide") ?: 1920,
                )
            }
            "capabilities" -> background(result) { capabilities() }
            "frames" -> background(result) {
                frames(
                    path = call.argument<String>("path")!!,
                    times = (call.argument<List<Number>>("times") ?: emptyList()).map { it.toLong() },
                    outDir = call.argument<String>("outDir")!!,
                    maxSide = call.argument<Int>("maxSide") ?: 480,
                )
            }
            "inspect" -> background(result) { inspect(call.argument<String>("path")!!) }
            "gifToVideo" -> background(result) {
                StudioMediaTools.gifToVideo(
                    call.argument<String>("path")!!,
                    call.argument<String>("out")!!,
                    call.argument<Int>("maxSide") ?: 1080,
                    ::postProgress,
                )
            }
            "reverse" -> background(result) {
                StudioMediaTools.reverse(
                    path = call.argument<String>("path")!!,
                    out = call.argument<String>("out")!!,
                    startMs = (call.argument<Number>("startMs") ?: 0).toLong(),
                    endMs = (call.argument<Number>("endMs") ?: 0).toLong(),
                    fps = call.argument<Int>("fps") ?: 30,
                    maxSide = call.argument<Int>("maxSide") ?: 1280,
                    onProgress = ::postProgress,
                )
            }
            "beats" -> background(result) {
                StudioMediaTools.beats(call.argument<String>("path")!!, (call.argument<Number>("maxMs") ?: 600000).toLong())
            }
            "normalizeImage" -> background(result) {
                normalizeImage(
                    path = call.argument<String>("path")!!,
                    out = call.argument<String>("out")!!,
                    maxSide = call.argument<Int>("maxSide") ?: 4096,
                )
            }
            "export" -> startExport(call, result)
            "cancel" -> {
                exporter?.cancel()
                exporter = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun postProgress(p: Double) {
        main.post { progressSink?.success(mapOf("progress" to p)) }
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (t: Throwable) {
                main.post { result.error("media_engine", t.message ?: t.javaClass.simpleName, null) }
            }
        }
    }

    private fun probe(path: String): Map<String, Any?> {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val hasVideo = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val hasAudio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            var width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {
                val t = width; width = height; height = t
            }
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toLongOrNull() ?: 0L
            return mapOf(
                "width" to width,
                "height" to height,
                "durationMs" to durationMs,
                "bitrate" to bitrate,
                "fps" to frameRate(path),
                "hasVideo" to hasVideo,
                "hasAudio" to hasAudio,
                "sizeBytes" to File(path).length(),
            )
        } finally {
            retriever.release()
        }
    }

    /** Container and track facts, with whether this phone has a decoder for each track. */
    private fun inspect(path: String): Map<String, Any?> {
        val extractor = MediaExtractor()
        return try {
            extractor.setDataSource(path)
            val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            val tracks = ArrayList<Map<String, Any?>>()
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                val kind = when {
                    mime.startsWith("video/") -> "video"
                    mime.startsWith("audio/") -> "audio"
                    mime.startsWith("image/") -> "image"
                    else -> "other"
                }
                val decodable = if (kind == "video" || kind == "audio") {
                    try {
                        format.setString(MediaFormat.KEY_FRAME_RATE, null)
                    } catch (_: Exception) {
                    }
                    try {
                        codecs.findDecoderForFormat(format) != null
                    } catch (_: Exception) {
                        false
                    }
                } else {
                    true
                }
                tracks.add(
                    mapOf(
                        "mime" to mime,
                        "kind" to kind,
                        "decodable" to decodable,
                        "width" to if (format.containsKey(MediaFormat.KEY_WIDTH)) format.getInteger(MediaFormat.KEY_WIDTH) else 0,
                        "height" to if (format.containsKey(MediaFormat.KEY_HEIGHT)) format.getInteger(MediaFormat.KEY_HEIGHT) else 0,
                    ),
                )
            }
            mapOf("readable" to true, "tracks" to tracks, "sizeBytes" to File(path).length())
        } catch (e: Exception) {
            mapOf("readable" to false, "error" to (e.message ?: e.javaClass.simpleName), "tracks" to emptyList<Any>())
        } finally {
            extractor.release()
        }
    }

    /** Decodes any image the phone supports, upright and at most [maxSide], to JPEG (PNG if it has alpha). */
    private fun normalizeImage(path: String, out: String, maxSide: Int): Map<String, Any?> {
        val bitmap: Bitmap = if (Build.VERSION.SDK_INT >= 28) {
            val source = ImageDecoder.createSource(File(path))
            ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > maxSide) {
                    val f = maxSide.toFloat() / longest
                    decoder.setTargetSize((info.size.width * f).toInt().coerceAtLeast(1), (info.size.height * f).toInt().coerceAtLeast(1))
                }
            }
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / sample > maxSide * 2) sample *= 2
            val decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
                ?: throw IllegalStateException("This phone can't decode that image.")
            val degrees = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            val longest = maxOf(decoded.width, decoded.height)
            val scale = if (longest > maxSide) maxSide.toFloat() / longest else 1f
            if (degrees != 0f || scale != 1f) {
                val m = Matrix().apply { postScale(scale, scale); postRotate(degrees) }
                Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, m, true).also {
                    if (it !== decoded) decoded.recycle()
                }
            } else {
                decoded
            }
        }
        val png = bitmap.hasAlpha()
        val target = if (png) out.substringBeforeLast('.') + ".png" else out
        File(target).parentFile?.mkdirs()
        FileOutputStream(target).use {
            bitmap.compress(if (png) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, 95, it)
        }
        val result = mapOf("path" to target, "width" to bitmap.width, "height" to bitmap.height)
        bitmap.recycle()
        return result
    }

    private fun frameRate(path: String): Double {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/") && format.containsKey(MediaFormat.KEY_FRAME_RATE)) {
                    return try {
                        format.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                    } catch (_: ClassCastException) {
                        format.getFloat(MediaFormat.KEY_FRAME_RATE).toDouble()
                    }
                }
            }
        } catch (_: Exception) {
        } finally {
            extractor.release()
        }
        return 0.0
    }

    private fun thumbnails(path: String, count: Int, startMs: Long, endMs: Long, height: Int, outDir: String): List<String> {
        val dir = File(outDir).apply { mkdirs() }
        val retriever = MediaMetadataRetriever()
        val out = ArrayList<String>()
        try {
            retriever.setDataSource(path)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val end = if (endMs > startMs) endMs else duration
            val n = count.coerceIn(1, 60)
            val step = if (n == 1) 0L else (end - startMs) / n
            val key = (path.hashCode().toLong() and 0xffffffffL).toString(16)
            for (i in 0 until n) {
                val t = startMs + step * i + step / 2
                val file = File(dir, "${key}_${t}_$height.jpg")
                if (!file.exists()) {
                    val bmp = retriever.getFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) ?: continue
                    val scaled = scaleToHeight(bmp, height)
                    FileOutputStream(file).use { scaled.compress(Bitmap.CompressFormat.JPEG, 80, it) }
                    if (scaled !== bmp) scaled.recycle()
                    bmp.recycle()
                }
                out.add(file.absolutePath)
            }
        } finally {
            retriever.release()
        }
        return out
    }

    private fun frame(path: String, ms: Long, out: String, maxSide: Int): String {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            val bmp = retriever.getFrameAtTime(ms * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
                ?: throw IllegalStateException("No frame at ${ms}ms")
            val longest = maxOf(bmp.width, bmp.height)
            val scaled = if (longest > maxSide) {
                val f = maxSide.toFloat() / longest
                Bitmap.createScaledBitmap(bmp, (bmp.width * f).toInt(), (bmp.height * f).toInt(), true)
            } else bmp
            File(out).parentFile?.mkdirs()
            FileOutputStream(out).use { scaled.compress(Bitmap.CompressFormat.JPEG, 92, it) }
            if (scaled !== bmp) scaled.recycle()
            bmp.recycle()
            return out
        } finally {
            retriever.release()
        }
    }

    /** Exact frames at [times] (ms) as small JPEGs, one retriever for all; "" where none. */
    private fun frames(path: String, times: List<Long>, outDir: String, maxSide: Int): List<String> {
        val dir = File(outDir).apply { mkdirs() }
        val retriever = MediaMetadataRetriever()
        val out = ArrayList<String>()
        val key = (path.hashCode().toLong() and 0xffffffffL).toString(16)
        try {
            retriever.setDataSource(path)
            for (t in times) {
                val file = File(dir, "${key}_f${t}_$maxSide.jpg")
                if (!file.exists()) {
                    val bmp = try {
                        if (Build.VERSION.SDK_INT >= 27) {
                            retriever.getScaledFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST, maxSide, maxSide)
                        } else {
                            retriever.getFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
                        }
                    } catch (_: Exception) {
                        null
                    }
                    if (bmp == null) {
                        out.add("")
                        continue
                    }
                    FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.JPEG, 85, it) }
                    bmp.recycle()
                }
                out.add(file.absolutePath)
            }
        } finally {
            retriever.release()
        }
        return out
    }

    private fun scaleToHeight(bmp: Bitmap, height: Int): Bitmap {
        if (bmp.height <= height) return bmp
        val w = (bmp.width * height.toFloat() / bmp.height).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bmp, w, height, true)
    }

    /** Largest H.264 encode size the device advertises (either orientation). */
    private fun capabilities(): Map<String, Any> {
        var maxW = 1920
        var maxH = 1080
        var maxFps = 30
        val list = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        for (info in list.codecInfos) {
            if (!info.isEncoder) continue
            if (!info.supportedTypes.any { it.equals(MediaFormat.MIMETYPE_VIDEO_AVC, true) }) continue
            val caps = info.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).videoCapabilities ?: continue
            val w = caps.supportedWidths.upper
            val h = caps.supportedHeights.upper
            if (w * h > maxW * maxH) {
                maxW = w; maxH = h
            }
            maxFps = maxOf(maxFps, caps.supportedFrameRates.upper.coerceAtMost(240))
        }
        return mapOf("maxWidth" to maxW, "maxHeight" to maxH, "maxFps" to maxFps)
    }

    private fun startExport(call: MethodCall, result: MethodChannel.Result) {
        if (exporter != null) {
            result.error("busy", "An export is already running.", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val spec = call.arguments as Map<String, Any?>
        val job = TimelineExporter(context, spec,
            onProgress = { p -> progressSink?.success(p) },
            onDone = { path ->
                exporter = null
                result.success(path)
            },
            onError = { code, message ->
                exporter = null
                result.error(code, message, null)
            })
        exporter = job
        try {
            job.start()
        } catch (t: Throwable) {
            exporter = null
            result.error("export_setup", t.message ?: t.javaClass.simpleName, null)
        }
    }
}
