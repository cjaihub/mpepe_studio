package com.oneova.mediaengine

import android.content.Context
import android.graphics.Bitmap
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
            "export" -> startExport(call, result)
            "cancel" -> {
                exporter?.cancel()
                exporter = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
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
