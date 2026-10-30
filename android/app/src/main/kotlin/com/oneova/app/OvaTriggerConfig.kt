package com.oneova.app

import android.content.Context

/**
 * System-wide Ova trigger settings. The source of truth is Firestore
 * `user_settings/{uid}.ovaTriggers` (edited in Ova Triggers settings); the
 * Dart side mirrors it here so the accessibility service can read it while
 * the app is not running.
 */
data class OvaTriggerConfig(
    /** Show the edge "Ova handle"; start an "O" on it and draw it anywhere. */
    val drawO: Boolean = true,
    /** "off" | "double_volume_down" | "volume_up_down". */
    val buttonShortcut: String = SHORTCUT_OFF,
    /** Allow the triggers on the lock screen (unlock is always required first). */
    val lockScreen: Boolean = true,
    /** Start Ova straight in voice mode. */
    val voiceMode: Boolean = false,
    /** Settings > Accessibility > Reduce motion: simple fades instead of the summon animation. */
    val reduceMotion: Boolean = false,
    /** Handle position: edge (true = right) and vertical fraction of the screen. */
    val handleRight: Boolean = true,
    val handleY: Float = 0.42f,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "drawO" to drawO,
        "buttonShortcut" to buttonShortcut,
        "lockScreen" to lockScreen,
        "voiceMode" to voiceMode,
    )

    companion object {
        const val SHORTCUT_OFF = "off"
        const val SHORTCUT_DOUBLE_VOLUME_DOWN = "double_volume_down"
        const val SHORTCUT_VOLUME_UP_DOWN = "volume_up_down"

        private const val PREFS = "ova_triggers"

        fun load(context: Context): OvaTriggerConfig {
            val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            return OvaTriggerConfig(
                drawO = p.getBoolean("drawO", true),
                buttonShortcut = p.getString("buttonShortcut", SHORTCUT_OFF) ?: SHORTCUT_OFF,
                lockScreen = p.getBoolean("lockScreen", true),
                voiceMode = p.getBoolean("voiceMode", false),
                reduceMotion = p.getBoolean("reduceMotion", false),
                handleRight = p.getBoolean("handleRight", true),
                handleY = p.getFloat("handleY", 0.42f),
            )
        }

        fun save(context: Context, values: Map<*, *>) {
            val e = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            (values["drawO"] as? Boolean)?.let { e.putBoolean("drawO", it) }
            (values["buttonShortcut"] as? String)?.let { e.putString("buttonShortcut", it) }
            (values["lockScreen"] as? Boolean)?.let { e.putBoolean("lockScreen", it) }
            (values["voiceMode"] as? Boolean)?.let { e.putBoolean("voiceMode", it) }
            (values["reduceMotion"] as? Boolean)?.let { e.putBoolean("reduceMotion", it) }
            e.apply()
        }

        fun saveHandlePosition(context: Context, right: Boolean, y: Float) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putBoolean("handleRight", right)
                .putFloat("handleY", y.coerceIn(0.08f, 0.92f))
                .apply()
        }
    }
}
