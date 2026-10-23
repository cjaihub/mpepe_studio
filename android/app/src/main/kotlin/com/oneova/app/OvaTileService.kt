package com.oneova.app

import android.content.Intent
import android.service.quicksettings.TileService

/** Quick Settings tile "Ask Ova" — wakes the assistant from anywhere on the device. */
class OvaTileService : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("wake_assistant", true)
            action = "com.oneova.app.WAKE_ASSISTANT"
        }
        @Suppress("DEPRECATION")
        startActivityAndCollapse(intent)
    }
}
