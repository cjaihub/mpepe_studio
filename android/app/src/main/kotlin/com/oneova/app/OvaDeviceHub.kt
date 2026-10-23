package com.oneova.app

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
import android.telephony.TelephonyManager
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Device awareness for Ova: notifications, SMS inbox, live device state,
 * media keys, Do Not Disturb and quick settings panels.
 *
 * Method channel: com.oneova.app/ova_device
 * Event channel:  com.oneova.app/ova_events  (notifications, foreground app, ...)
 */
object OvaDeviceHub {
    private const val METHODS = "com.oneova.app/ova_device"
    private const val EVENTS = "com.oneova.app/ova_events"

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null

    fun emit(type: String, data: Map<String, Any?>) {
        main.post { sink?.success(mapOf("type" to type) + data) }
    }

    fun register(context: Context, engine: FlutterEngine) {
        val app = context.applicationContext
        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        MethodChannel(engine.dartExecutor.binaryMessenger, METHODS).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status(app))
                    "deviceState" -> result.success(deviceState(app))
                    "openNotificationAccess" -> {
                        startSettings(app, Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        result.success(true)
                    }
                    "openDndAccess" -> {
                        startSettings(app, Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        result.success(true)
                    }
                    "notifications" -> {
                        val l = OvaNotificationListener.instance
                        if (l == null) result.error("NO_ACCESS", "Notification access is off", null)
                        else result.success(l.recent(call.argument<Int>("limit") ?: 15))
                    }
                    "replyNotification" -> {
                        val l = OvaNotificationListener.instance
                        if (l == null) result.error("NO_ACCESS", "Notification access is off", null)
                        else result.success(l.reply(call.argument<String>("key") ?: "", call.argument<String>("text") ?: ""))
                    }
                    "openNotification" -> result.success(OvaNotificationListener.instance?.open(call.argument<String>("key") ?: "") ?: false)
                    "dismissNotification" -> result.success(OvaNotificationListener.instance?.dismiss(call.argument<String>("key") ?: "") ?: false)
                    "mediaKey" -> result.success(mediaKey(app, call.argument<String>("action") ?: "play_pause"))
                    "setDnd" -> result.success(setDnd(app, call.argument<Boolean>("on") ?: true))
                    "setRinger" -> result.success(setRinger(app, call.argument<String>("mode") ?: "normal"))
                    "openPanel" -> result.success(openPanel(app, call.argument<String>("panel") ?: "internet"))
                    "returnToApp" -> {
                        app.startActivity(Intent(app, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                        })
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("OVA_DEVICE_ERROR", e.message, null)
            }
        }
    }

    private fun startSettings(app: Context, action: String) {
        app.startActivity(Intent(action).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
    }

    private fun status(app: Context): Map<String, Any?> {
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return mapOf(
            "notificationAccess" to (Settings.Secure.getString(app.contentResolver, "enabled_notification_listeners")?.contains(app.packageName) ?: false),
            "notificationListenerConnected" to OvaNotificationListener.isConnected(),
            "accessibility" to OvaAccessibilityService.isRunning(),
            "dndAccess" to nm.isNotificationPolicyAccessGranted,
            "overlay" to Settings.canDrawOverlays(app),
        )
    }

    private fun deviceState(app: Context): Map<String, Any?> {
        val bm = app.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val battery = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val bStatus = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
        val charging = bStatus == BatteryManager.BATTERY_STATUS_CHARGING || bStatus == BatteryManager.BATTERY_STATUS_FULL

        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        val network = when {
            caps == null -> "offline"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        val validated = caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) ?: false
        val signalLevel = signalLevel(app, network, caps)

        val stat = StatFs(Environment.getDataDirectory().path)
        val freeGb = stat.availableBytes / 1_000_000_000.0
        val totalGb = stat.totalBytes / 1_000_000_000.0

        val am = app.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }

        val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val inCall = audio.mode == AudioManager.MODE_IN_CALL || audio.mode == AudioManager.MODE_IN_COMMUNICATION
        val ringer = when (audio.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> "silent"
            AudioManager.RINGER_MODE_VIBRATE -> "vibrate"
            else -> "normal"
        }
        val vol = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val volMax = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val dnd = nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL &&
            nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN

        val airplane = Settings.Global.getInt(app.contentResolver, Settings.Global.AIRPLANE_MODE_ON, 0) == 1

        return mapOf(
            "battery" to battery,
            "charging" to charging,
            "network" to network,
            "internet" to validated,
            "signalLevel" to signalLevel,
            "downKbps" to (caps?.linkDownstreamBandwidthKbps ?: 0),
            "storageFreeGb" to "%.1f".format(freeGb).toDouble(),
            "storageTotalGb" to "%.1f".format(totalGb).toDouble(),
            "ramFreeGb" to "%.1f".format(mem.availMem / 1_000_000_000.0).toDouble(),
            "lowMemory" to mem.lowMemory,
            "inCall" to inCall,
            "ringer" to ringer,
            "musicActive" to audio.isMusicActive,
            "mediaVolume" to if (volMax > 0) (vol * 100 / volMax) else 0,
            "dnd" to dnd,
            "airplane" to airplane,
            "foregroundApp" to (OvaAccessibilityService.instance?.foregroundPackage() ?: ""),
            "nowPlaying" to nowPlaying(app),
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "android" to Build.VERSION.RELEASE,
        )
    }

    /** Signal bars 0-4 for the active network, or -1 when unknown. No permission needed. */
    private fun signalLevel(app: Context, network: String, caps: NetworkCapabilities?): Int = try {
        when (network) {
            "wifi" -> {
                val rssi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) caps?.signalStrength ?: Int.MIN_VALUE else Int.MIN_VALUE
                if (rssi == Int.MIN_VALUE) -1
                else {
                    @Suppress("DEPRECATION")
                    WifiManager.calculateSignalLevel(rssi, 5)
                }
            }
            "cellular" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val tm = app.getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                    tm.signalStrength?.level ?: -1
                } else -1
            }
            else -> -1
        }
    } catch (e: Exception) {
        -1
    }

    /** Title/artist of active media; needs Notification access. */
    private fun nowPlaying(app: Context): Map<String, Any?>? {
        if (!OvaNotificationListener.isConnected()) return null
        return try {
            val msm = app.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val sessions = msm.getActiveSessions(ComponentName(app, OvaNotificationListener::class.java))
            val c = sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: sessions.firstOrNull()
            val md = c?.metadata ?: return null
            mapOf(
                "app" to c.packageName,
                "title" to md.getString(android.media.MediaMetadata.METADATA_KEY_TITLE),
                "artist" to md.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST),
                "playing" to (c.playbackState?.state == PlaybackState.STATE_PLAYING),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun mediaKey(app: Context, action: String): Boolean {
        val code = when (action) {
            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
            "stop" -> KeyEvent.KEYCODE_MEDIA_STOP
            else -> KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
        return true
    }

    /** Returns "ok" or "no_access" (user must allow Do Not Disturb access). */
    private fun setDnd(app: Context, on: Boolean): String {
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.isNotificationPolicyAccessGranted) return "no_access"
        nm.setInterruptionFilter(if (on) NotificationManager.INTERRUPTION_FILTER_PRIORITY else NotificationManager.INTERRUPTION_FILTER_ALL)
        return "ok"
    }

    private fun setRinger(app: Context, mode: String): String {
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val target = when (mode) {
            "silent" -> AudioManager.RINGER_MODE_SILENT
            "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
            else -> AudioManager.RINGER_MODE_NORMAL
        }
        if (!nm.isNotificationPolicyAccessGranted && (target == AudioManager.RINGER_MODE_SILENT || audio.ringerMode == AudioManager.RINGER_MODE_SILENT)) {
            return "no_access"
        }
        return try {
            audio.ringerMode = target
            "ok"
        } catch (_: SecurityException) {
            "no_access"
        }
    }

    private fun openPanel(app: Context, panel: String): Boolean {
        val action = when (panel) {
            "wifi" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS
            "internet" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_WIRELESS_SETTINGS
            "volume" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_VOLUME else Settings.ACTION_SOUND_SETTINGS
            "nfc" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) Settings.Panel.ACTION_NFC else Settings.ACTION_NFC_SETTINGS
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "battery" -> Intent.ACTION_POWER_USAGE_SUMMARY
            "display" -> Settings.ACTION_DISPLAY_SETTINGS
            "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
            "airplane" -> Settings.ACTION_AIRPLANE_MODE_SETTINGS
            "hotspot" -> Settings.ACTION_WIRELESS_SETTINGS
            "data_usage" -> Settings.ACTION_DATA_USAGE_SETTINGS
            "storage" -> Settings.ACTION_INTERNAL_STORAGE_SETTINGS
            "apps" -> Settings.ACTION_APPLICATION_SETTINGS
            "notifications" -> Settings.ACTION_APP_NOTIFICATION_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        val intent = Intent(action).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
        if (action == Settings.ACTION_APP_NOTIFICATION_SETTINGS) {
            intent.putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName)
        }
        return try {
            app.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
