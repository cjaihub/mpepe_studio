package com.oneova.mediaengine

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Movie
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Build
import android.view.Surface
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Encodes bitmaps into an H.264 MP4 at a fixed frame rate (no audio). Used to
 * turn animated GIFs into video and to build reversed clips.
 */
internal class SequenceEncoder(private val out: String, width: Int, height: Int, private val fps: Int, bitrate: Int) {
    private val w = width / 2 * 2
    private val h = height / 2 * 2
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    private val surface: Surface
    private val muxer = MediaMuxer(out, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
    private var track = -1
    private var written = 0L
    private val info = MediaCodec.BufferInfo()
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)

    init {
        File(out).parentFile?.mkdirs()
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        surface = codec.createInputSurface()
        codec.start()
    }

    /** Draws [bmp] letterboxed into the frame and encodes it. */
    fun add(bmp: Bitmap) {
        val canvas: Canvas = if (Build.VERSION.SDK_INT >= 23) surface.lockHardwareCanvas() else surface.lockCanvas(null)
        canvas.drawColor(Color.BLACK)
        val s = min(w.toFloat() / bmp.width, h.toFloat() / bmp.height)
        val dw = bmp.width * s
        val dh = bmp.height * s
        canvas.drawBitmap(bmp, Rect(0, 0, bmp.width, bmp.height), RectF((w - dw) / 2, (h - dh) / 2, (w + dw) / 2, (h + dh) / 2), paint)
        surface.unlockCanvasAndPost(canvas)
        drain(false)
    }

    private fun drain(end: Boolean) {
        val frameUs = 1_000_000L / fps
        while (true) {
            val idx = codec.dequeueOutputBuffer(info, if (end) 10_000 else 2_000)
            when {
                idx == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!end) return
                idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                }
                idx >= 0 -> {
                    val buf = codec.getOutputBuffer(idx)!!
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && track >= 0) {
                        // Canvas frames carry wall-clock times; re-time them at a steady rate.
                        info.presentationTimeUs = written * frameUs
                        written++
                        buf.position(info.offset)
                        buf.limit(info.offset + info.size)
                        muxer.writeSampleData(track, buf, info)
                    }
                    codec.releaseOutputBuffer(idx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    fun finish(): String {
        codec.signalEndOfInputStream()
        drain(true)
        codec.stop()
        codec.release()
        surface.release()
        if (track >= 0) muxer.stop()
        muxer.release()
        if (written == 0L) throw IllegalStateException("No frames were encoded.")
        return out
    }

    fun abort() {
        try {
            codec.release()
            surface.release()
            muxer.release()
        } catch (_: Exception) {
        }
        File(out).delete()
    }
}

internal object StudioMediaTools {
    /** Animated GIF -> MP4 (first loop), at most [maxSide] px. Returns (path, width, height, durationMs). */
    @Suppress("DEPRECATION")
    fun gifToVideo(path: String, out: String, maxSide: Int, onProgress: (Double) -> Unit): Map<String, Any> {
        val movie = Movie.decodeFile(path) ?: throw IllegalStateException("This GIF can't be read.")
        // Single-frame GIFs report no duration: the caller opens them as a photo.
        val duration = movie.duration().takeIf { it > 0 } ?: throw IllegalStateException("static")
        val scale = min(1f, maxSide.toFloat() / max(movie.width(), movie.height()))
        val w = max(2, (movie.width() * scale).toInt())
        val h = max(2, (movie.height() * scale).toInt())
        val fps = 30
        val frame = Bitmap.createBitmap(movie.width(), movie.height(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(frame)
        val enc = SequenceEncoder(out, w, h, fps, 4_000_000)
        try {
            val count = max(1, duration * fps / 1000)
            for (i in 0 until count) {
                frame.eraseColor(Color.BLACK)
                movie.setTime(i * 1000 / fps)
                movie.draw(canvas, 0f, 0f)
                enc.add(frame)
                onProgress(i.toDouble() / count)
            }
            enc.finish()
        } catch (e: Exception) {
            enc.abort()
            throw e
        } finally {
            frame.recycle()
        }
        return mapOf("path" to out, "width" to (w / 2 * 2), "height" to (h / 2 * 2), "durationMs" to duration)
    }

    /** [startMs, endMs] played backwards, picture and sound. */
    fun reverse(path: String, out: String, startMs: Long, endMs: Long, fps: Int, maxSide: Int, onProgress: (Double) -> Unit): String {
        val videoOnly = "$out.video.mp4"
        reverseVideo(path, videoOnly, startMs, endMs, fps, maxSide) { onProgress(it * 0.85) }
        val audio = try {
            reversedAacSamples(path, startMs, endMs)
        } catch (e: Exception) {
            null
        }
        if (audio == null) {
            File(videoOnly).renameTo(File(out))
            return out
        }
        try {
            muxWithAudio(videoOnly, audio, out)
        } finally {
            File(videoOnly).delete()
        }
        onProgress(1.0)
        return out
    }

    private class EncodedAudio(val format: MediaFormat, val samples: List<Pair<ByteArray, MediaCodec.BufferInfo>>)

    /** Decodes the audio of [startMs, endMs] to PCM, reverses it, re-encodes AAC. Null if there is no sound. */
    private fun reversedAacSamples(path: String, startMs: Long, endMs: Long): EncodedAudio? {
        val ex = MediaExtractor()
        ex.setDataSource(path)
        var idx = -1
        for (i in 0 until ex.trackCount) {
            if (ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) { idx = i; break }
        }
        if (idx < 0) { ex.release(); return null }
        val inFormat = ex.getTrackFormat(idx)
        ex.selectTrack(idx)
        ex.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        val dec = MediaCodec.createDecoderByType(inFormat.getString(MediaFormat.KEY_MIME)!!)
        dec.configure(inFormat, null, null, 0)
        dec.start()
        var rate = inFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = inFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val pcm = java.io.ByteArrayOutputStream()
        val info = MediaCodec.BufferInfo()
        var inDone = false
        var outDone = false
        try {
            while (!outDone) {
                if (!inDone) {
                    val ii = dec.dequeueInputBuffer(5000)
                    if (ii >= 0) {
                        val size = ex.readSampleData(dec.getInputBuffer(ii)!!, 0)
                        if (size < 0 || ex.sampleTime > endMs * 1000 + 200_000) {
                            dec.queueInputBuffer(ii, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inDone = true
                        } else {
                            dec.queueInputBuffer(ii, 0, size, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val oi = dec.dequeueOutputBuffer(info, 5000)
                if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    rate = dec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = dec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                } else if (oi >= 0) {
                    val buf = dec.getOutputBuffer(oi)!!
                    val frameBytes = 2 * channels
                    val t = info.presentationTimeUs
                    // Keep only the samples inside the range (whole frames).
                    val bytesPerUs = rate * frameBytes / 1_000_000.0
                    var from = 0
                    var to = info.size
                    if (t < startMs * 1000) from = (((startMs * 1000 - t) * bytesPerUs).toInt() / frameBytes * frameBytes).coerceAtMost(info.size)
                    val endUs = endMs * 1000
                    if (t + info.size / bytesPerUs > endUs) to = (((endUs - t) * bytesPerUs).toInt() / frameBytes * frameBytes).coerceIn(from, info.size)
                    if (to > from) {
                        val chunk = ByteArray(to - from)
                        buf.position(info.offset + from)
                        buf.get(chunk)
                        pcm.write(chunk)
                    }
                    dec.releaseOutputBuffer(oi, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outDone = true
                }
            }
        } finally {
            dec.stop(); dec.release(); ex.release()
        }
        val raw = pcm.toByteArray()
        val frameBytes = 2 * channels
        val frames = raw.size / frameBytes
        if (frames == 0) return null
        val rev = ByteArray(frames * frameBytes)
        for (f in 0 until frames) System.arraycopy(raw, (frames - 1 - f) * frameBytes, rev, f * frameBytes, frameBytes)

        val outFormat = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, channels).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        val enc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        enc.configure(outFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        enc.start()
        val samples = ArrayList<Pair<ByteArray, MediaCodec.BufferInfo>>()
        var encFormat: MediaFormat? = null
        var pos = 0
        var eosSent = false
        try {
            while (true) {
                if (!eosSent) {
                    val ii = enc.dequeueInputBuffer(5000)
                    if (ii >= 0) {
                        val ib = enc.getInputBuffer(ii)!!
                        val n = min(ib.capacity() / frameBytes * frameBytes, rev.size - pos)
                        val pts = (pos / frameBytes) * 1_000_000L / rate
                        if (n <= 0) {
                            enc.queueInputBuffer(ii, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            eosSent = true
                        } else {
                            ib.clear(); ib.put(rev, pos, n)
                            enc.queueInputBuffer(ii, 0, n, pts, 0)
                            pos += n
                        }
                    }
                }
                val oi = enc.dequeueOutputBuffer(info, 5000)
                if (oi == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    encFormat = enc.outputFormat
                } else if (oi >= 0) {
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 && info.size > 0) {
                        val b = ByteArray(info.size)
                        val ob = enc.getOutputBuffer(oi)!!
                        ob.position(info.offset); ob.get(b)
                        samples.add(b to MediaCodec.BufferInfo().apply { set(0, b.size, info.presentationTimeUs, info.flags) })
                    }
                    enc.releaseOutputBuffer(oi, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            enc.stop(); enc.release()
        }
        return encFormat?.let { EncodedAudio(it, samples) }
    }

    private fun muxWithAudio(videoPath: String, audio: EncodedAudio, out: String) {
        val ex = MediaExtractor()
        ex.setDataSource(videoPath)
        ex.selectTrack(0)
        val muxer = MediaMuxer(out, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        try {
            val v = muxer.addTrack(ex.getTrackFormat(0))
            val a = muxer.addTrack(audio.format)
            muxer.start()
            val buf = ByteBuffer.allocate(4 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val n = ex.readSampleData(buf, 0)
                if (n < 0) break
                info.set(0, n, ex.sampleTime, if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
                muxer.writeSampleData(v, buf, info)
                ex.advance()
            }
            for ((bytes, bi) in audio.samples) muxer.writeSampleData(a, ByteBuffer.wrap(bytes), bi)
            muxer.stop()
        } finally {
            muxer.release(); ex.release()
        }
    }

    private fun reverseVideo(path: String, out: String, startMs: Long, endMs: Long, fps: Int, maxSide: Int, onProgress: (Double) -> Unit): String {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            val step = 1000.0 / fps
            val count = max(1, ((endMs - startMs) / step).toInt())
            var enc: SequenceEncoder? = null
            try {
                for (i in 0 until count) {
                    val t = (endMs - i * step).toLong().coerceAtLeast(startMs)
                    val bmp = (if (Build.VERSION.SDK_INT >= 27) {
                        r.getScaledFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST, maxSide, maxSide)
                    } else {
                        r.getFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST)
                    }) ?: continue
                    if (enc == null) enc = SequenceEncoder(out, bmp.width, bmp.height, fps, 8_000_000)
                    enc.add(bmp)
                    bmp.recycle()
                    onProgress(i.toDouble() / count)
                }
                return (enc ?: throw IllegalStateException("No frames could be read.")).finish()
            } catch (e: Exception) {
                enc?.abort()
                throw e
            }
        } finally {
            r.release()
        }
    }

    /**
     * Camera path for Stabilize: frames every 1000/[fps] ms of [startMs, endMs]
     * at 160 px, global shift between neighbours by block matching, summed.
     * Returns times (source ms) and cumulative x/y as fractions of the frame.
     */
    fun motion(path: String, startMs: Long, endMs: Long, fps: Int, onProgress: (Double) -> Unit): Map<String, Any> {
        val r = MediaMetadataRetriever()
        val times = ArrayList<Long>()
        val xs = ArrayList<Double>()
        val ys = ArrayList<Double>()
        try {
            r.setDataSource(path)
            val step = 1000L / fps.coerceIn(2, 15)
            val count = ((endMs - startMs) / step).toInt().coerceIn(1, 450)
            val stride = max(step, (endMs - startMs) / count)
            var prev: IntArray? = null
            var pw = 0
            var ph = 0
            var cx = 0.0
            var cy = 0.0
            var t = startMs
            var i = 0
            while (t <= endMs) {
                val bmp = (if (Build.VERSION.SDK_INT >= 27) {
                    r.getScaledFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST, 160, 160)
                } else {
                    r.getFrameAtTime(t * 1000, MediaMetadataRetriever.OPTION_CLOSEST)?.let { Bitmap.createScaledBitmap(it, 160, max(1, 160 * it.height / it.width), true) }
                })
                if (bmp != null) {
                    val w = bmp.width
                    val h = bmp.height
                    val px = IntArray(w * h)
                    bmp.getPixels(px, 0, w, 0, 0, w, h)
                    bmp.recycle()
                    val luma = IntArray(w * h) { k -> val c = px[k]; ((c shr 16 and 255) * 77 + (c shr 8 and 255) * 150 + (c and 255) * 29) shr 8 }
                    val p = prev
                    if (p != null && pw == w && ph == h) {
                        val (dx, dy) = shift(p, luma, w, h)
                        cx += dx.toDouble() / w
                        cy += dy.toDouble() / h
                    }
                    prev = luma; pw = w; ph = h
                    times.add(t); xs.add(cx); ys.add(cy)
                }
                i++
                onProgress(i.toDouble() / (count + 1))
                t += stride
            }
        } finally {
            r.release()
        }
        return mapOf("timesMs" to times, "x" to xs, "y" to ys)
    }

    /** Shift of [b] relative to [a] (pixels) that best lines them up. */
    private fun shift(a: IntArray, b: IntArray, w: Int, h: Int): Pair<Int, Int> {
        val range = 10
        var best = Long.MAX_VALUE
        var bx = 0
        var by = 0
        for (dy in -range..range) {
            for (dx in -range..range) {
                var sad = 0L
                var y = range
                while (y < h - range) {
                    var x = range
                    val row = y * w
                    val row2 = (y + dy) * w
                    while (x < w - range) {
                        sad += abs(a[row + x] - b[row2 + x + dx])
                        x += 2
                    }
                    y += 2
                }
                if (sad < best) { best = sad; bx = dx; by = dy }
            }
        }
        return bx to by
    }

    /**
     * Beat times (ms) in an audio or video file: decoded mono energy, onset
     * strength with an adaptive threshold, at least 250 ms apart.
     */
    fun beats(path: String, maxMs: Long): Map<String, Any> {
        val ex = MediaExtractor()
        ex.setDataSource(path)
        var trackIdx = -1
        var format: MediaFormat? = null
        for (i in 0 until ex.trackCount) {
            val f = ex.getTrackFormat(i)
            if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                trackIdx = i; format = f; break
            }
        }
        if (trackIdx < 0 || format == null) {
            ex.release()
            throw IllegalStateException("No sound to find beats in.")
        }
        ex.selectTrack(trackIdx)
        val dec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        dec.configure(format, null, null, 0)
        dec.start()
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val hop = 1024
        val energies = ArrayList<Float>()
        var acc = 0.0
        var n = 0
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        var decodedMs = 0L
        try {
            while (!outputDone && decodedMs < maxMs) {
                if (!inputDone) {
                    val inIdx = dec.dequeueInputBuffer(5000)
                    if (inIdx >= 0) {
                        val size = ex.readSampleData(dec.getInputBuffer(inIdx)!!, 0)
                        if (size < 0) {
                            dec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            dec.queueInputBuffer(inIdx, 0, size, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val outIdx = dec.dequeueOutputBuffer(info, 5000)
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    rate = dec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = dec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                } else if (outIdx >= 0) {
                    val buf = dec.getOutputBuffer(outIdx)!!.order(ByteOrder.nativeOrder())
                    buf.position(info.offset)
                    buf.limit(info.offset + info.size)
                    val s = buf.asShortBuffer()
                    while (s.remaining() >= channels) {
                        var m = 0.0
                        for (c in 0 until channels) m += s.get() / 32768.0
                        m /= channels
                        acc += m * m
                        n++
                        if (n == hop) {
                            energies.add(sqrt(acc / hop).toFloat())
                            acc = 0.0; n = 0
                        }
                    }
                    decodedMs = info.presentationTimeUs / 1000
                    dec.releaseOutputBuffer(outIdx, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
        } finally {
            dec.stop(); dec.release(); ex.release()
        }
        val hopMs = hop * 1000.0 / rate
        // Onset strength: positive change in log energy.
        val onset = FloatArray(energies.size)
        for (i in 1 until energies.size) {
            val a = log10(energies[i - 1] + 1e-6f)
            val b = log10(energies[i] + 1e-6f)
            onset[i] = max(0f, b - a)
        }
        val win = max(4, (1000 / hopMs).toInt() / 2)
        val beats = ArrayList<Long>()
        var last = -1_000_000.0
        for (i in 1 until onset.size - 1) {
            val lo = max(0, i - win)
            val hi = min(onset.size, i + win)
            var mean = 0.0
            var sq = 0.0
            for (j in lo until hi) { mean += onset[j]; sq += onset[j] * onset[j] }
            mean /= (hi - lo)
            val sd = sqrt(max(0.0, sq / (hi - lo) - mean * mean))
            val t = i * hopMs
            if (onset[i] > mean + 1.4 * sd && onset[i] >= onset[i - 1] && onset[i] >= onset[i + 1] && onset[i] > 0.02 && t - last >= 250) {
                beats.add(t.toLong())
                last = t
            }
        }
        // Tempo from the median gap.
        val gaps = beats.zipWithNext { a, b -> (b - a).toDouble() }.filter { it in 250.0..1500.0 }.sorted()
        val bpm = if (gaps.isEmpty()) 0.0 else 60000.0 / gaps[gaps.size / 2]
        return mapOf("beatsMs" to beats, "bpm" to bpm)
    }
}

/**
 * Voice clean-up for clip sound: rumble high-pass, gentle noise gate,
 * presence lift and a compressor with make-up gain. [amount] 0..1.
 */
internal class VoiceCleanProcessor(private val amount: Float) : BaseAudioProcessor() {
    private var channels = 1
    private var rate = 44100
    private lateinit var hp: Array<Biquad>
    private lateinit var presence: Array<Biquad>
    private var env = 0f
    private var gain = 1f

    private class Biquad(var b0: Float, var b1: Float, var b2: Float, var a1: Float, var a2: Float) {
        var x1 = 0f; var x2 = 0f; var y1 = 0f; var y2 = 0f
        fun run(x: Float): Float {
            val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private fun highPass(f: Double): Biquad {
        val w = 2 * Math.PI * f / rate
        val q = 0.707
        val alpha = sin(w) / (2 * q)
        val c = cos(w)
        val a0 = 1 + alpha
        return Biquad(((1 + c) / 2 / a0).toFloat(), (-(1 + c) / a0).toFloat(), ((1 + c) / 2 / a0).toFloat(), (-2 * c / a0).toFloat(), ((1 - alpha) / a0).toFloat())
    }

    private fun peak(f: Double, db: Double, q: Double): Biquad {
        val a = 10.0.pow(db / 40)
        val w = 2 * Math.PI * f / rate
        val alpha = sin(w) / (2 * q)
        val c = cos(w)
        val a0 = 1 + alpha / a
        return Biquad(((1 + alpha * a) / a0).toFloat(), (-2 * c / a0).toFloat(), ((1 - alpha * a) / a0).toFloat(), (-2 * c / a0).toFloat(), ((1 - alpha / a) / a0).toFloat())
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        channels = inputAudioFormat.channelCount
        rate = inputAudioFormat.sampleRate
        hp = Array(channels) { highPass(90.0) }
        presence = Array(channels) { peak(3200.0, 3.0 * amount, 0.9) }
        return inputAudioFormat
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val frames = inputBuffer.remaining() / (2 * channels)
        val out = replaceOutputBuffer(frames * 2 * channels)
        val attack = exp(-1.0 / (0.005 * rate)).toFloat()
        val release = exp(-1.0 / (0.12 * rate)).toFloat()
        val gateDb = -50f + 10f * amount
        val threshDb = -22f
        val ratio = 1f + 2.5f * amount
        val makeup = 10f.pow((3f * amount) / 20f)
        val sample = FloatArray(channels)
        for (i in 0 until frames) {
            var peakAbs = 0f
            for (c in 0 until channels) {
                var x = inputBuffer.short / 32768f
                x = presence[c].run(hp[c].run(x))
                sample[c] = x
                peakAbs = max(peakAbs, abs(x))
            }
            env = if (peakAbs > env) attack * env + (1 - attack) * peakAbs else release * env + (1 - release) * peakAbs
            val db = 20f * log10(env + 1e-6f)
            var target = 1f
            if (db < gateDb) target = 10f.pow(max(-24f, (db - gateDb) * 1.5f) / 20f)
            if (db > threshDb) target *= 10f.pow(((threshDb + (db - threshDb) / ratio) - db) / 20f)
            target *= makeup
            gain = 0.995f * gain + 0.005f * target
            for (c in 0 until channels) {
                val y = (sample[c] * gain).coerceIn(-1f, 1f)
                out.putShort((y * 32767f).toInt().toShort())
            }
        }
        out.flip()
    }

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        env = 0f
        gain = 1f
    }
}


/**
 * Stabilize: zoom in and shift each frame by the keyframed correction
 * (clip-local output ms; x/y are fractions of the frame, y down).
 */
internal class StabilizeTransformation(
    private val zoom: Float,
    private val keysMs: LongArray,
    private val xs: FloatArray,
    private val ys: FloatArray,
) : androidx.media3.effect.MatrixTransformation {
    private var baseUs = Long.MIN_VALUE

    override fun getMatrix(presentationTimeUs: Long): android.graphics.Matrix {
        if (baseUs == Long.MIN_VALUE) baseUs = presentationTimeUs
        val ms = (presentationTimeUs - baseUs) / 1000
        var dx = 0f
        var dy = 0f
        if (keysMs.isNotEmpty()) {
            var i = 0
            while (i < keysMs.size - 1 && keysMs[i + 1] <= ms) i++
            val j = (i + 1).coerceAtMost(keysMs.size - 1)
            val span = (keysMs[j] - keysMs[i]).toFloat()
            val k = if (j == i || span <= 0f) 0f else ((ms - keysMs[i]) / span).coerceIn(0f, 1f)
            dx = xs[i] + (xs[j] - xs[i]) * k
            dy = ys[i] + (ys[j] - ys[i]) * k
        }
        // NDC spans 2 units, y up.
        return android.graphics.Matrix().apply {
            postScale(zoom, zoom)
            postTranslate(dx * 2f * zoom, -dy * 2f * zoom)
        }
    }

    companion object {
        fun fromMap(m: Map<String, Any?>?): StabilizeTransformation? {
            if (m == null) return null
            fun fl(v: Any?): FloatArray = when (v) {
                is FloatArray -> v
                is DoubleArray -> FloatArray(v.size) { v[it].toFloat() }
                is List<*> -> v.map { (it as Number).toFloat() }.toFloatArray()
                else -> FloatArray(0)
            }
            val keys = (m["keysMs"] as? List<*>)?.map { (it as Number).toLong() }?.toLongArray() ?: return null
            val xs = fl(m["x"])
            val ys = fl(m["y"])
            if (xs.size != keys.size || ys.size != keys.size) return null
            val zoom = (m["zoom"] as? Number)?.toFloat() ?: 1.1f
            return StabilizeTransformation(zoom, keys, xs, ys)
        }
    }
}
