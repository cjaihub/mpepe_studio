package com.oneova.app

import android.app.assist.AssistStructure
import android.graphics.Bitmap
import android.graphics.Rect
import android.util.Base64
import android.view.accessibility.AccessibilityNodeInfo
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.min

/**
 * Ephemeral in-memory store holding the most recent screen snapshot and spatially
 * positioned text blocks captured when Ova is summoned via the Power Button
 * (VoiceInteractionSession), Accessibility Edge Handle, Volume Shortcut, or Bubble.
 *
 * Security: Never writes user screen pixels or text to external storage/Gallery.
 */
object OvaAssistSnapshotStore {

    data class Snapshot(
        val imageBase64: String,
        val width: Int,
        val height: Int,
        val packageName: String,
        val webUrl: String,
        val blocks: List<Map<String, Any>>,
        val capturedAtMs: Long,
    ) {
        fun toMap(): Map<String, Any> = mapOf(
            "hasBitmap" to imageBase64.isNotEmpty(),
            "imageBase64" to imageBase64,
            "width" to width,
            "height" to height,
            "packageName" to packageName,
            "webUrl" to webUrl,
            "blocks" to blocks,
            "capturedAtMs" to capturedAtMs,
        )
    }

    @Volatile
    var latest: Snapshot? = null
        private set

    fun clear() {
        latest = null
    }

    fun hasFreshSnapshot(maxAgeMs: Long = 12_000L): Boolean {
        val snap = latest ?: return false
        return (System.currentTimeMillis() - snap.capturedAtMs) <= maxAgeMs
    }

    fun encodeBitmapToBase64(bitmap: Bitmap, maxWidth: Int = 1080, quality: Int = 78): String {
        val scaled = if (bitmap.width > maxWidth && bitmap.width > 0) {
            val h = ((bitmap.height.toFloat() / bitmap.width.toFloat()) * maxWidth).toInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(bitmap, maxWidth, h, true)
        } else {
            bitmap
        }
        val baos = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, quality, baos)
        if (scaled !== bitmap) {
            try { scaled.recycle() } catch (_: Exception) {}
        }
        return Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
    }

    fun extractFromAssistStructure(structure: AssistStructure?, screenW: Int, screenH: Int): List<Map<String, Any>> {
        if (structure == null || screenW <= 0 || screenH <= 0) return emptyList()
        val out = ArrayList<Map<String, Any>>()
        val seen = HashSet<String>()
        val w = screenW.toFloat()
        val h = screenH.toFloat()

        fun walk(node: AssistStructure.ViewNode, offsetX: Int, offsetY: Int, depth: Int) {
            if (depth > 40 || out.size >= 80) return
            val absL = offsetX + node.left
            val absT = offsetY + node.top
            val absR = absL + node.width
            val absB = absT + node.height
            val inputType = node.inputType
            val isPassword = (inputType and 0x80) != 0 || (inputType and 0x90) != 0

            if (!isPassword) {
                val raw = (node.text?.toString() ?: node.contentDescription?.toString() ?: "").trim()
                if (raw.length >= 2 && node.width > 12 && node.height > 10) {
                    val nl = (absL / w).coerceIn(0f, 1f)
                    val nt = (absT / h).coerceIn(0f, 1f)
                    val nr = (absR / w).coerceIn(0f, 1f)
                    val nb = (absB / h).coerceIn(0f, 1f)
                    val dedupKey = "${raw.take(64)}:${(nl * 20).toInt()}:${(nt * 20).toInt()}"
                    if (nr > nl + 0.01f && nb > nt + 0.008f && seen.add(dedupKey)) {
                        out.add(
                            mapOf(
                                "id" to "b_${out.size}",
                                "text" to raw.take(400),
                                "left" to nl.toDouble(),
                                "top" to nt.toDouble(),
                                "right" to nr.toDouble(),
                                "bottom" to nb.toDouble(),
                            )
                        )
                    }
                }
            }
            val nextOffX = absL - node.scrollX
            val nextOffY = absT - node.scrollY
            for (i in 0 until node.childCount) {
                walk(node.getChildAt(i), nextOffX, nextOffY, depth + 1)
            }
        }

        for (i in 0 until structure.windowNodeCount) {
            val wn = structure.getWindowNodeAt(i)
            val root = wn.rootViewNode ?: continue
            walk(root, wn.left, wn.top, 0)
        }
        return out
    }

    fun extractFromAccessibilityTree(root: AccessibilityNodeInfo?, screenW: Int, screenH: Int): List<Map<String, Any>> {
        if (root == null || screenW <= 0 || screenH <= 0) return emptyList()
        val out = ArrayList<Map<String, Any>>()
        val seen = HashSet<String>()
        val rect = Rect()
        val w = screenW.toFloat()
        val h = screenH.toFloat()

        fun walk(node: AccessibilityNodeInfo?, depth: Int) {
            if (node == null || depth > 40 || out.size >= 80) return
            if (node.isPassword) return
            val raw = (node.text?.toString() ?: node.contentDescription?.toString() ?: "").trim()
            if (raw.length >= 2) {
                node.getBoundsInScreen(rect)
                if (rect.width() > 14 && rect.height() > 10 && rect.bottom > 0 && rect.top < screenH) {
                    val nl = (rect.left / w).coerceIn(0f, 1f)
                    val nt = (rect.top / h).coerceIn(0f, 1f)
                    val nr = (rect.right / w).coerceIn(0f, 1f)
                    val nb = (rect.bottom / h).coerceIn(0f, 1f)
                    val dedupKey = "${raw.take(64)}:${(nl * 20).toInt()}:${(nt * 20).toInt()}"
                    if (nr > nl + 0.01f && nb > nt + 0.008f && seen.add(dedupKey)) {
                        out.add(
                            mapOf(
                                "id" to "a_${out.size}",
                                "text" to raw.take(400),
                                "left" to nl.toDouble(),
                                "top" to nt.toDouble(),
                                "right" to nr.toDouble(),
                                "bottom" to nb.toDouble(),
                            )
                        )
                    }
                }
            }
            for (i in 0 until node.childCount) {
                walk(node.getChild(i), depth + 1)
            }
        }

        walk(root, 0)
        return out
    }

    fun captureWithOcr(
        bitmap: Bitmap?,
        packageName: String,
        webUrl: String,
        existingBlocks: List<Map<String, Any>>,
        onDone: (Snapshot) -> Unit,
    ) {
        val now = System.currentTimeMillis()
        if (bitmap == null) {
            val snap = Snapshot(
                imageBase64 = "",
                width = 0,
                height = 0,
                packageName = packageName,
                webUrl = webUrl,
                blocks = existingBlocks,
                capturedAtMs = now,
            )
            latest = snap
            onDone(snap)
            return
        }

        val w = max(1, bitmap.width)
        val h = max(1, bitmap.height)
        val encoded = try {
            encodeBitmapToBase64(bitmap)
        } catch (_: Exception) {
            ""
        }

        // Fast save immediately so Flutter never stalls waiting for OCR.
        val initial = Snapshot(
            imageBase64 = encoded,
            width = w,
            height = h,
            packageName = packageName,
            webUrl = webUrl,
            blocks = existingBlocks,
            capturedAtMs = now,
        )
        latest = initial

        try {
            val image = InputImage.fromBitmap(bitmap, 0)
            val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
            recognizer.process(image)
                .addOnSuccessListener { result ->
                    val merged = ArrayList<Map<String, Any>>()
                    val existingTextKeys = HashSet<String>()
                    // Prefer OCR blocks for pixel-accurate text inside images/videos/webviews,
                    // keeping non-overlapping accessibility labels when needed.
                    for (tb in result.textBlocks) {
                        for (line in tb.lines) {
                            val txt = line.text.trim()
                            val box = line.boundingBox ?: continue
                            if (txt.length < 2 || box.width() < 8 || box.height() < 6) continue
                            val nl = (box.left.toFloat() / w).coerceIn(0f, 1f)
                            val nt = (box.top.toFloat() / h).coerceIn(0f, 1f)
                            val nr = (box.right.toFloat() / w).coerceIn(0f, 1f)
                            val nb = (box.bottom.toFloat() / h).coerceIn(0f, 1f)
                            existingTextKeys.add(txt.lowercase().take(40))
                            merged.add(
                                mapOf(
                                    "id" to "o_${merged.size}",
                                    "text" to txt.take(400),
                                    "left" to nl.toDouble(),
                                    "top" to nt.toDouble(),
                                    "right" to nr.toDouble(),
                                    "bottom" to nb.toDouble(),
                                )
                            )
                        }
                    }
                    for (eb in existingBlocks) {
                        if (merged.size >= 80) break
                        val txt = (eb["text"] as? String ?: "").trim()
                        if (txt.isEmpty() || existingTextKeys.contains(txt.lowercase().take(40))) continue
                        merged.add(eb)
                    }
                    val enriched = initial.copy(blocks = merged.take(80))
                    latest = enriched
                    try { recognizer.close() } catch (_: Exception) {}
                    onDone(enriched)
                }
                .addOnFailureListener {
                    try { recognizer.close() } catch (_: Exception) {}
                    onDone(initial)
                }
        } catch (_: Exception) {
            onDone(initial)
        }
    }

    fun storeTextBlocksOnly(
        packageName: String,
        webUrl: String,
        blocks: List<Map<String, Any>>,
    ): Snapshot {
        val snap = Snapshot(
            imageBase64 = "",
            width = 0,
            height = 0,
            packageName = packageName,
            webUrl = webUrl,
            blocks = blocks,
            capturedAtMs = min(System.currentTimeMillis(), Long.MAX_VALUE),
        )
        latest = snap
        return snap
    }
}
