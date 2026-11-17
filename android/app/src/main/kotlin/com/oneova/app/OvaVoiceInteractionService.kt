package com.oneova.app

import android.app.assist.AssistContent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.speech.RecognitionService

/**
 * True system-level Digital Assistant entry point for Android (`RoleManager.ROLE_ASSISTANT`).
 * Enables long-press Power button and bottom-corner swipe to summon Ova cleanly
 * over any screen (including lock screen when allowed) with automatic screen
 * bitmap + AssistStructure extraction.
 */
class OvaVoiceInteractionService : VoiceInteractionService() {
    override fun onReady() {
        super.onReady()
        OvaAssistActivity.prewarm(applicationContext)
    }
}

class OvaVoiceInteractionSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession {
        return OvaAssistSession(this)
    }
}

class OvaAssistSession(context: Context) : VoiceInteractionSession(context) {

    private var lastAssistPkg: String = ""
    private var lastAssistUrl: String = ""
    private var lastBlocks: List<Map<String, Any>> = emptyList()
    private var launched = false

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        launched = false
        lastAssistPkg = ""
        lastAssistUrl = ""
        lastBlocks = emptyList()
        OvaAssistActivity.prewarm(context.applicationContext)
    }

    @Suppress("DEPRECATION")
    override fun onHandleAssist(
        data: Bundle?,
        structure: AssistStructure?,
        content: AssistContent?,
    ) {
        super.onHandleAssist(data, structure, content)
        val dm = context.resources.displayMetrics
        val pkg = structure?.activityComponent?.packageName ?: ""
        val url = try {
            content?.webUri?.toString() ?: ""
        } catch (_: Exception) {
            ""
        }
        val extracted = OvaAssistSnapshotStore.extractFromAssistStructure(
            structure,
            dm.widthPixels,
            dm.heightPixels,
        )
        if (pkg.isNotEmpty()) lastAssistPkg = pkg
        if (url.isNotEmpty()) lastAssistUrl = url
        if (extracted.isNotEmpty()) lastBlocks = extracted

        // Launch immediately if Android doesn't deliver a screenshot (e.g. FLAG_SECURE screen).
        if (!launched) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!launched) {
                    launched = true
                    OvaAssistSnapshotStore.storeTextBlocksOnly(lastAssistPkg, lastAssistUrl, lastBlocks)
                    OvaAssistActivity.open(context, "power_assist")
                    try { finish() } catch (_: Exception) {}
                }
            }, 220)
        }
    }

    override fun onHandleScreenshot(screenshot: Bitmap?) {
        super.onHandleScreenshot(screenshot)
        launched = true
        OvaAssistSnapshotStore.captureWithOcr(
            bitmap = screenshot,
            packageName = lastAssistPkg,
            webUrl = lastAssistUrl,
            existingBlocks = lastBlocks,
        ) {
            OvaAssistActivity.notifySnapshotUpdated()
        }
        OvaAssistActivity.open(context, "power_assist")
        try { finish() } catch (_: Exception) {}
    }
}

/**
 * Minimal RecognitionService registration so PackageManager & RoleManager expose
 * Oneova consistently across all OEM Digital Assistant pickers (HiOS, OneUI, MIUI, Pixel).
 */
class OvaRecognitionService : RecognitionService() {
    override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
        // Live voice is streamed through Vertex Gemini Live directly inside Ova.
        listener?.error(android.speech.SpeechRecognizer.ERROR_NO_MATCH)
    }

    override fun onCancel(listener: Callback?) {}
    override fun onStopListening(listener: Callback?) {}
}
