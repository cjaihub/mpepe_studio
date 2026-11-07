package com.oneova.mediaengine

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.SpeedParameters
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.ChannelMixingAudioProcessor
import androidx.media3.common.audio.ChannelMixingMatrix
import androidx.media3.common.audio.SonicAudioProcessor
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.Crop
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.RgbMatrix
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import java.io.File

/**
 * Renders an edited timeline (spec built by the Dart `StudioProject`) into an
 * H.264/AAC MP4 with Media3 Transformer. Everything the editor previews is
 * applied here: trims, speed, volume/mute, color matrix, crop, rotate/flip,
 * zoom, letterboxed output size, frame-rate cap, bitrate, the Oneova Look
 * engine, timed Studio effects, keyframed bitmap overlays (animated text,
 * stickers, captions) and extra audio tracks.
 *
 * Special modes:
 *  - `width`/`height` 0: keep the source size (used to convert files the
 *    preview player can't read into H.264/AAC MP4).
 *  - `audioOnly`: write the timeline's clip audio (trims and speed applied)
 *    as mono 16 kHz AAC, for speech-to-text.
 */
internal class TimelineExporter(
    private val context: Context,
    private val spec: Map<String, Any?>,
    private val onProgress: (Map<String, Any>) -> Unit,
    private val onDone: (String) -> Unit,
    private val onError: (String, String) -> Unit,
) {
    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var finished = false
    private val progressHolder = ProgressHolder()

    private val poll = object : Runnable {
        override fun run() {
            val t = transformer ?: return
            if (finished) return
            val state = t.getProgress(progressHolder)
            if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                onProgress(mapOf("progress" to progressHolder.progress / 100.0))
            }
            main.postDelayed(this, 250)
        }
    }

    fun start() {
        val output = spec.str("output")
        val width = spec.int("width")
        val height = spec.int("height")
        val fps = spec.int("fps")
        val bitrate = spec.int("bitrate")
        File(output).parentFile?.mkdirs()
        File(output).delete()

        val clips = spec.list("clips")
        require(clips.isNotEmpty()) { "Nothing to export." }
        val audioOnly = spec["audioOnly"] == true
        val sequences = if (audioOnly) {
            mutableListOf(speechSequence(clips))
        } else {
            val items = clips.map { buildClip(it, width, height, fps) }
            val videoSequence = EditedMediaItemSequence.Builder(items)
                .experimentalSetForceAudioTrack(true)
                .build()
            mutableListOf(videoSequence).also { list ->
                audioSequence(spec.list("audio"))?.let { list.add(it) }
            }
        }

        val composition = Composition.Builder(sequences)
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            .build()

        val encoderSettings = VideoEncoderSettings.Builder().apply {
            if (bitrate > 0) setBitrate(bitrate)
        }.build()
        val encoderFactory = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(encoderSettings)
            .setEnableFallback(true)
            .build()

        val t = Transformer.Builder(context)
            .apply { if (!audioOnly) setVideoMimeType(MimeTypes.VIDEO_H264) }
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoderFactory)
            .setPortraitEncodingEnabled(true)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    if (finished) return
                    finished = true
                    onProgress(mapOf("progress" to 1.0))
                    onDone(output)
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    if (finished) return
                    finished = true
                    File(output).delete()
                    onError(exportException.errorCodeName, exportException.message ?: exportException.errorCodeName)
                }
            })
            .build()
        transformer = t
        t.start(composition, output)
        main.postDelayed(poll, 250)
    }

    fun cancel() {
        if (finished) return
        finished = true
        transformer?.cancel()
        File(spec.str("output")).delete()
        onError("cancelled", "Export cancelled.")
    }

    private fun buildClip(clip: Map<String, Any?>, width: Int, height: Int, fps: Int): EditedMediaItem {
        val path = clip.str("path")
        val isImage = clip["image"] == true
        val mediaItem = MediaItem.Builder().setUri(android.net.Uri.fromFile(File(path))).apply {
            if (isImage) {
                setImageDurationMs(clip.long("durationMs").coerceAtLeast(500))
                imageMime(path)?.let { setMimeType(it) }
            } else {
                val start = clip.long("startMs")
                val end = clip.long("endMs")
                setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(start)
                        .apply { if (end > start) setEndPositionMs(end) }
                        .build(),
                )
            }
        }.build()

        val video = ArrayList<Effect>()
        val crop = clip.map("crop")
        if (crop != null) {
            // Normalized 0..1 (top-left origin) -> NDC (-1..1, y up).
            val l = crop.dbl("l"); val t = crop.dbl("t"); val r = crop.dbl("r"); val b = crop.dbl("b")
            if (l > 0.001 || t > 0.001 || r < 0.999 || b < 0.999) {
                video.add(Crop((l * 2 - 1).toFloat(), (r * 2 - 1).toFloat(), (1 - b * 2).toFloat(), (1 - t * 2).toFloat()))
            }
        }
        val rotation = clip.dbl("rotation")
        val flipH = clip["flipH"] == true
        val flipV = clip["flipV"] == true
        if (rotation != 0.0 || flipH || flipV) {
            video.add(
                ScaleAndRotateTransformation.Builder()
                    .setScale(if (flipH) -1f else 1f, if (flipV) -1f else 1f)
                    .setRotationDegrees(-rotation.toFloat())
                    .build(),
            )
        }
        RetouchSpec.fromMap(clip.map("retouch"))?.let { video.add(RetouchGlEffect(it)) }
        val matrix = clip.floats("matrix")
        if (matrix != null && matrix.size == 20) {
            video.add(colorMatrix(matrix))
        }
        LookSpec.fromMap(clip.map("look"))?.let { video.add(LookGlEffect(it)) }
        if (width > 0 && height > 0) {
            // Fill (crop) or fit (letterbox) into the project canvas.
            val fill = clip["fill"] == true
            video.add(
                Presentation.createForWidthAndHeight(
                    width, height,
                    if (fill) Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP else Presentation.LAYOUT_SCALE_TO_FIT,
                ),
            )
            val zoom = clip.dbl("zoom")
            if (zoom > 1.001) {
                video.add(ScaleAndRotateTransformation.Builder().setScale(zoom.toFloat(), zoom.toFloat()).build())
                video.add(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP))
            }
        }
        for (pass in clip.rawList("fxPasses")) {
            @Suppress("UNCHECKED_CAST")
            val windows = (pass as? List<Map<String, Any?>>).orEmpty().map {
                FxWindow(
                    type = it.dbl("type").toFloat(),
                    amount = it.dbl("amount").toFloat(),
                    startUs = it.long("startMs") * 1000,
                    endUs = it.long("endMs") * 1000,
                    timeOffsetS = (it.long("layerOffsetMs") / 1000.0).toFloat(),
                    layerUs = it.long("layerMs") * 1000,
                    layerOffsetUs = it.long("layerOffsetMs") * 1000,
                )
            }
            if (windows.isNotEmpty()) video.add(FxGlEffect(windows))
        }
        if (fps > 0) video.add(FrameDropEffect.createDefaultFrameDropEffect(fps.toFloat()))
        val overlays = clip.list("overlays").mapNotNull { timedOverlay(it) }
        if (overlays.isNotEmpty()) video.add(OverlayEffect(overlays))

        val audio = ArrayList<AudioProcessor>()
        val voice = clip.dbl("voiceClean").toFloat()
        if (!isImage && voice > 0f) audio.add(VoiceCleanProcessor(voice.coerceIn(0f, 1f)))
        val volume = if (clip.containsKey("volume")) clip.dbl("volume").toFloat() else 1f
        if (!isImage && volume != 1f) audio.add(volumeProcessor(volume))

        val builder = EditedMediaItem.Builder(mediaItem)
            .setEffects(Effects(audio, video))
            .setRemoveAudio(isImage || clip["mute"] == true)
        if (isImage) builder.setFrameRate(if (fps > 0) fps else 30)
        val speed = clip.dbl("speed")
        if (!isImage && speed > 0 && speed != 1.0) {
            builder.setSpeed(SpeedParameters(constantSpeed(speed.toFloat()), true))
        }
        return builder.build()
    }

    private fun audioSequence(tracks: List<Map<String, Any?>>): EditedMediaItemSequence? {
        if (tracks.isEmpty()) return null
        val sorted = tracks.sortedBy { it.long("offsetMs") }
        val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
        var cursorMs = 0L
        for (track in sorted) {
            val offset = track.long("offsetMs")
            if (offset > cursorMs) {
                builder.addGap((offset - cursorMs) * 1000)
                cursorMs = offset
            }
            val start = track.long("startMs")
            val end = track.long("endMs")
            val item = MediaItem.Builder()
                .setUri(android.net.Uri.fromFile(File(track.str("path"))))
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(start)
                        .apply { if (end > start) setEndPositionMs(end) }
                        .build(),
                )
                .build()
            val volume = if (track.containsKey("volume")) track.dbl("volume").toFloat() else 1f
            val processors = if (volume != 1f) listOf<AudioProcessor>(volumeProcessor(volume)) else emptyList()
            builder.addItem(
                EditedMediaItem.Builder(item)
                    .setRemoveVideo(true)
                    .setEffects(Effects(processors, emptyList()))
                    .build(),
            )
            cursorMs += (end - start).coerceAtLeast(0)
        }
        return builder.build()
    }

    /** Clip audio only (trim + speed), mono 16 kHz, silence for photos and silent clips. */
    private fun speechSequence(clips: List<Map<String, Any?>>): EditedMediaItemSequence {
        val builder = EditedMediaItemSequence.Builder(setOf(C.TRACK_TYPE_AUDIO))
        for (clip in clips) {
            val isImage = clip["image"] == true
            val speed = clip.dbl("speed").takeIf { it > 0 } ?: 1.0
            val start = clip.long("startMs")
            val end = clip.long("endMs")
            if (isImage || clip["hasAudio"] == false) {
                val ms = if (isImage) clip.long("durationMs") else ((end - start) / speed).toLong()
                builder.addGap(ms.coerceAtLeast(1) * 1000)
                continue
            }
            val item = MediaItem.Builder()
                .setUri(android.net.Uri.fromFile(File(clip.str("path"))))
                .setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setStartPositionMs(start)
                        .apply { if (end > start) setEndPositionMs(end) }
                        .build(),
                )
                .build()
            val mono = ChannelMixingAudioProcessor().apply {
                // Any layout up to 7.1 folds down to one channel.
                for (n in 1..8) putChannelMixingMatrix(ChannelMixingMatrix(n, 1, FloatArray(n) { 1f / n }))
            }
            val resample = SonicAudioProcessor().apply { setOutputSampleRateHz(16000) }
            val edited = EditedMediaItem.Builder(item)
                .setRemoveVideo(true)
                .setEffects(Effects(listOf<AudioProcessor>(mono, resample), emptyList()))
            if (speed != 1.0) edited.setSpeed(SpeedParameters(constantSpeed(speed.toFloat()), true))
            builder.addItem(edited.build())
        }
        return builder.build()
    }

    private fun volumeProcessor(volume: Float): AudioProcessor {
        val p = ChannelMixingAudioProcessor()
        for (channels in 1..2) {
            p.putChannelMixingMatrix(ChannelMixingMatrix.createForConstantGain(channels, channels).scaleBy(volume))
        }
        return p
    }

    private fun constantSpeed(speed: Float) = object : SpeedProvider {
        override fun getSpeed(timeUs: Long): Float = speed
        override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
    }

    /**
     * Flutter's ColorFilter.matrix is a row-major 4x5 matrix with offsets in
     * 0..255. Media3's RgbMatrix is a column-major 4x4 applied to (r,g,b,1),
     * so the offset column folds into the alpha column.
     */
    private fun colorMatrix(m: FloatArray): RgbMatrix {
        val out = FloatArray(16)
        for (row in 0 until 3) {
            for (col in 0 until 3) out[col * 4 + row] = m[row * 5 + col]
            out[3 * 4 + row] = m[row * 5 + 4] / 255f
        }
        out[15] = 1f
        return RgbMatrix { _, _ -> out }
    }

    /**
     * PNG frames drawn by Flutter at output resolution, shown between startMs
     * and endMs of this clip's output time. Animated layers carry keyframes
     * sampled in Dart from the same curves the preview uses:
     * `samples` = [alpha, scaleX, scaleY, dx, dy, rotationDeg, frame] per
     * `sampleMs` of layer time (dx/dy in NDC, rotation clockwise). Frame
     * timestamps are measured from the first frame the overlay sees, so the
     * window is clip-relative whatever offset the sequence applies.
     */
    private fun timedOverlay(o: Map<String, Any?>): TextureOverlay? {
        val frames = ((o["frames"] as? List<*>)?.mapNotNull { it as? String } ?: listOfNotNull(o["png"] as? String))
            .filter { File(it).exists() }
        if (frames.isEmpty()) return null
        val first = BitmapFactory.decodeFile(frames[0]) ?: return null
        val startUs = o.long("startMs") * 1000
        val endUs = o.long("endMs") * 1000
        val baseX = o.dbl("x").toFloat()
        val baseY = o.dbl("y").toFloat()
        val layerOffsetMs = o.long("layerOffsetMs")
        val sampleMs = o.dbl("sampleMs").takeIf { it > 0 } ?: 0.0
        val samples = o.floats("samples")
        val stride = 7
        val count = if (samples != null && sampleMs > 0) samples.size / stride else 0

        return object : BitmapOverlay() {
            private var baseUs = Long.MIN_VALUE
            private var frameIndex = 0
            private var bitmap: Bitmap = first
            private val state = FloatArray(stride).also { it[0] = 1f; it[1] = 1f; it[2] = 1f }

            private fun localUs(presentationTimeUs: Long): Long {
                if (baseUs == Long.MIN_VALUE) baseUs = presentationTimeUs
                return presentationTimeUs - baseUs
            }

            private fun evaluate(local: Long) {
                if (count == 0) return
                val layerMs = local / 1000.0 + layerOffsetMs
                val f = (layerMs / sampleMs).coerceIn(0.0, (count - 1).toDouble())
                val i0 = f.toInt()
                val i1 = (i0 + 1).coerceAtMost(count - 1)
                val k = (f - i0).toFloat()
                for (j in 0 until 6) {
                    val a = samples!![i0 * stride + j]
                    val b = samples[i1 * stride + j]
                    state[j] = a + (b - a) * k
                }
                state[6] = samples!![i0 * stride + 6]
            }

            override fun getBitmap(presentationTimeUs: Long): Bitmap {
                evaluate(localUs(presentationTimeUs))
                val want = state[6].toInt().coerceIn(0, frames.size - 1)
                if (want != frameIndex) {
                    BitmapFactory.decodeFile(frames[want])?.let { bitmap = it }
                    frameIndex = want
                }
                return bitmap
            }

            override fun getOverlaySettings(presentationTimeUs: Long): StaticOverlaySettings {
                val local = localUs(presentationTimeUs)
                evaluate(local)
                val active = local >= startUs && (endUs <= 0 || local < endUs)
                return StaticOverlaySettings.Builder()
                    .setAlphaScale(if (active) state[0].coerceIn(0f, 1f) else 0f)
                    .setScale(state[1].coerceAtLeast(0.001f), state[2].coerceAtLeast(0.001f))
                    .setRotationDegrees(-state[5])
                    .setBackgroundFrameAnchor(baseX + state[3], baseY + state[4])
                    .build()
            }
        }
    }
}

private fun imageMime(path: String): String? = when (path.substringAfterLast('.').lowercase()) {
    "jpg", "jpeg" -> MimeTypes.IMAGE_JPEG
    "png" -> MimeTypes.IMAGE_PNG
    "webp" -> MimeTypes.IMAGE_WEBP
    "heic", "heif" -> MimeTypes.IMAGE_HEIF
    else -> null
}

private fun Map<String, Any?>.str(key: String) = this[key] as String
private fun Map<String, Any?>.int(key: String) = (this[key] as? Number)?.toInt() ?: 0
private fun Map<String, Any?>.long(key: String) = (this[key] as? Number)?.toLong() ?: 0L
private fun Map<String, Any?>.dbl(key: String) = (this[key] as? Number)?.toDouble() ?: 0.0

@Suppress("UNCHECKED_CAST")
private fun Map<String, Any?>.map(key: String) = this[key] as? Map<String, Any?>

@Suppress("UNCHECKED_CAST")
private fun Map<String, Any?>.list(key: String) = (this[key] as? List<Map<String, Any?>>) ?: emptyList()

private fun Map<String, Any?>.rawList(key: String) = (this[key] as? List<*>) ?: emptyList<Any?>()

private fun Map<String, Any?>.floats(key: String): FloatArray? = when (val v = this[key]) {
    is FloatArray -> v
    is DoubleArray -> FloatArray(v.size) { v[it].toFloat() }
    is List<*> -> v.map { (it as Number).toFloat() }.toFloatArray()
    else -> null
}
