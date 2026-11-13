package com.oneova.camerakit.ar

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer

/**
 * Records the composited AR frames: an H.264 encoder fed through its input
 * [Surface] (the GL pipeline renders into it) plus AAC audio from the mic,
 * muxed into an MP4.
 *
 * Timestamps are in the monotonic clock, relative to [startNs], for both
 * tracks, so audio and video line up. Samples that arrive before the muxer
 * has both track formats are held and written once it starts.
 *
 * Video methods run on the GL thread; audio runs on its own thread.
 */
internal class ArVideoRecorder(
    val file: File,
    val width: Int,
    val height: Int,
    fps: Int,
    withAudio: Boolean,
    val startNs: Long,
    /** Degrees players rotate the video by (landscape takes). */
    orientationHint: Int = 0,
) {
    private class Sample(val track: Int, val data: ByteBuffer, val info: MediaCodec.BufferInfo)

    private val muxer = MediaMuxer(file.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4).apply {
        if (orientationHint != 0) setOrientationHint(orientationHint)
    }
    private val video: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    val inputSurface: Surface

    private val lock = Object()
    private var videoTrack = -1
    private var audioTrack = -1
    private var expectedTracks = 1
    private var muxerStarted = false
    private val held = ArrayList<Sample>()
    private var videoSamples = 0
    private var lastVideoUs = 0L

    private var audioRecord: AudioRecord? = null

    /**
     * True when Android silenced our microphone (another app holds it), or
     * there was no microphone: the video records without sound.
     */
    val micSilenced: Boolean
        get() {
            val r = audioRecord ?: return wantedAudio
            if (android.os.Build.VERSION.SDK_INT < 29) return false
            return runCatching { r.activeRecordingConfiguration?.isClientSilenced == true }.getOrDefault(false)
        }
    private var wantedAudio = false
    private var audioCodec: MediaCodec? = null
    private var audioThread: Thread? = null
    @Volatile private var audioRunning = false

    private val videoInfo = MediaCodec.BufferInfo()

    init {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, (width.toLong() * height * fps / 5).coerceIn(4_000_000, 40_000_000).toInt())
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        video.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        inputSurface = video.createInputSurface()
        video.start()
        if (withAudio) startAudio()
    }

    /** Pulls encoded video out; with [endOfStream] waits for the encoder to finish. */
    fun drainVideo(endOfStream: Boolean) {
        if (endOfStream) video.signalEndOfInputStream()
        var idleSpins = 0
        while (true) {
            val index = video.dequeueOutputBuffer(videoInfo, if (endOfStream) 10_000L else 0L)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream || ++idleSpins > 200) return
                }
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> synchronized(lock) {
                    videoTrack = muxer.addTrack(video.outputFormat)
                    maybeStartMuxer()
                }
                index >= 0 -> {
                    val buf = video.getOutputBuffer(index)
                    if (buf != null && videoInfo.size > 0 &&
                        videoInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                    ) {
                        // Muxer tracks must not go backwards.
                        if (videoInfo.presentationTimeUs <= lastVideoUs && videoSamples > 0) {
                            videoInfo.presentationTimeUs = lastVideoUs + 1
                        }
                        lastVideoUs = videoInfo.presentationTimeUs
                        write(true, buf, videoInfo)
                        videoSamples++
                    }
                    video.releaseOutputBuffer(index, false)
                    if (videoInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    /**
     * Ends both tracks and closes the file (GL thread, after the last frame).
     * Returns the duration in milliseconds, or -1 when nothing was recorded.
     */
    fun finish(): Long {
        try {
            drainVideo(true)
        } catch (e: IllegalStateException) {
            Log.w(TAG, "Video drain failed", e)
        }
        stopAudio()
        val ok = synchronized(lock) {
            try {
                // The mic never produced a format: keep the video on its own.
                if (!muxerStarted && videoTrack >= 0) {
                    expectedTracks = 1
                    maybeStartMuxer()
                }
                if (muxerStarted && videoSamples > 0) {
                    muxer.stop()
                    true
                } else {
                    false
                }
            } catch (e: IllegalStateException) {
                Log.w(TAG, "Muxer stop failed", e)
                false
            }
        }
        release()
        if (!ok) {
            file.delete()
            return -1
        }
        return lastVideoUs / 1000
    }

    /** Drops the recording (camera closed mid-take). */
    fun abandon() {
        stopAudio()
        release()
        file.delete()
    }

    private fun release() {
        runCatching { video.stop() }
        runCatching { video.release() }
        runCatching { inputSurface.release() }
        runCatching { muxer.release() }
    }

    private fun write(isVideo: Boolean, buf: ByteBuffer, info: MediaCodec.BufferInfo) {
        synchronized(lock) {
            val track = if (isVideo) videoTrack else audioTrack
            if (muxerStarted) {
                buf.position(info.offset)
                buf.limit(info.offset + info.size)
                muxer.writeSampleData(track, buf, info)
                return
            }
            // Held until the other track's format arrives.
            val copy = ByteBuffer.allocateDirect(info.size)
            buf.position(info.offset)
            buf.limit(info.offset + info.size)
            copy.put(buf)
            copy.flip()
            val i = MediaCodec.BufferInfo().apply { set(0, info.size, info.presentationTimeUs, info.flags) }
            held.add(Sample(if (isVideo) -1 else -2, copy, i))
        }
    }

    private fun maybeStartMuxer() {
        val tracks = (if (videoTrack >= 0) 1 else 0) + (if (audioTrack >= 0) 1 else 0)
        if (muxerStarted || tracks < expectedTracks) return
        muxer.start()
        muxerStarted = true
        for (s in held) {
            val track = if (s.track == -1) videoTrack else audioTrack
            if (track >= 0) muxer.writeSampleData(track, s.data, s.info)
        }
        held.clear()
    }

    // ── Audio ──────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission") // Checked by the camera screen; failure → silent video.
    private fun startAudio() {
        wantedAudio = true
        val rate = 44_100
        val minBuf = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minBuf <= 0) return
        val sources = intArrayOf(
            MediaRecorder.AudioSource.CAMCORDER,
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.DEFAULT,
        )
        var record: AudioRecord? = null
        for (src in sources) {
            val candidate = runCatching {
                AudioRecord(src, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, minBuf * 4)
            }.getOrNull() ?: continue
            if (candidate.state == AudioRecord.STATE_INITIALIZED) {
                record = candidate
                break
            }
            candidate.release()
        }
        if (record == null) {
            Log.w(TAG, "Microphone unavailable on all audio sources; recording without audio")
            return
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(
            MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, minBuf * 4)
            },
            null, null, MediaCodec.CONFIGURE_FLAG_ENCODE,
        )
        codec.start()
        record.startRecording()
        audioRecord = record
        audioCodec = codec
        synchronized(lock) { expectedTracks = 2 }
        audioRunning = true
        audioThread = Thread({ audioLoop(record, codec, rate) }, "OneovaArAudio").apply { start() }
    }

    private fun audioLoop(record: AudioRecord, codec: MediaCodec, rate: Int) {
        val info = MediaCodec.BufferInfo()
        var samplesRead = 0L
        var firstUs = -1L
        var eosQueued = false
        try {
            while (true) {
                if (!eosQueued) {
                    val inIndex = codec.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val inBuf = codec.getInputBuffer(inIndex)!!
                        inBuf.clear()
                        val n = record.read(inBuf, inBuf.capacity())
                        val nowUs = (System.nanoTime() - startNs) / 1000
                        if (firstUs < 0) firstUs = nowUs - (n.coerceAtLeast(0) / 2) * 1_000_000L / rate
                        // Sample-count clock anchored at the first read: no jitter.
                        val ptsUs = firstUs + samplesRead * 1_000_000L / rate
                        if (n > 0) samplesRead += n / 2
                        val stop = !audioRunning
                        codec.queueInputBuffer(
                            inIndex, 0, n.coerceAtLeast(0), ptsUs.coerceAtLeast(0),
                            if (stop) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0,
                        )
                        if (stop) eosQueued = true
                    }
                }
                var out = codec.dequeueOutputBuffer(info, 0)
                while (out != MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        synchronized(lock) {
                            audioTrack = muxer.addTrack(codec.outputFormat)
                            maybeStartMuxer()
                        }
                    } else if (out >= 0) {
                        val buf = codec.getOutputBuffer(out)
                        if (buf != null && info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                            write(false, buf, info)
                        }
                        codec.releaseOutputBuffer(out, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                    out = codec.dequeueOutputBuffer(info, 0)
                }
            }
        } catch (e: RuntimeException) {
            Log.w(TAG, "Audio encoding stopped", e)
        }
    }

    private fun stopAudio() {
        audioRunning = false
        audioThread?.join(2_000)
        audioThread = null
        audioRecord?.let { runCatching { it.stop() }; it.release() }
        audioCodec?.let { runCatching { it.stop() }; it.release() }
        audioRecord = null
        audioCodec = null
    }

    companion object {
        private const val TAG = "OneovaArRecorder"
    }
}
