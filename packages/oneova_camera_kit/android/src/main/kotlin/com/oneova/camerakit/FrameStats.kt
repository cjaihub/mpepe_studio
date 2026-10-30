package com.oneova.camerakit

/** Thread-safe frame counters with a rolling window of graded frame times. */
internal class FrameStats(private val window: Int = 240) {
    private val times = DoubleArray(window)
    private var count = 0
    private var next = 0
    private var graded = 0L
    private var passedThrough = 0L
    private var reason: String? = null
    private var width = 0
    private var height = 0
    private var lookId: String? = null

    @Synchronized
    fun graded(ms: Double, w: Int, h: Int, look: String?) {
        times[next] = ms
        next = (next + 1) % window
        if (count < window) count++
        graded++
        width = w
        height = h
        lookId = look
    }

    @Synchronized
    fun passedThrough(why: String) {
        passedThrough++
        reason = why
    }

    @Synchronized
    fun toMap(): Map<String, Any?> {
        val sorted = times.copyOf(count).also { it.sort() }
        val avg = if (count == 0) 0.0 else sorted.sum() / count
        val p95 = if (count == 0) 0.0 else sorted[((count - 1) * 95) / 100]
        return mapOf(
            "framesGraded" to graded,
            "framesPassedThrough" to passedThrough,
            "lastPassThroughReason" to reason,
            "averageFrameMs" to avg,
            "p95FrameMs" to p95,
            "width" to width,
            "height" to height,
            "lookId" to lookId,
        )
    }
}
