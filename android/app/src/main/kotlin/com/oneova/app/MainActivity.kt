package com.oneova.app

import android.app.Notification
import android.app.PictureInPictureParams
import android.util.Rational
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val OVA_CHANNEL = "com.oneova.app/ova_assistant"
    private var assistantChannel: MethodChannel? = null
    private val CALL_PIP_CHANNEL = "com.oneova.app/call_pip"
    // True while a video call screen is showing; leaving the app then enters PiP.
    private var callPipEnabled = false
    private var callPipChannel: MethodChannel? = null
    // Ringback the caller hears while the other phone rings.
    private var ringback: ToneGenerator? = null
    // Screen off while an audio call is held to the ear.
    private var proximityLock: PowerManager.WakeLock? = null

    private var lastSuggestionPostedAt = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        ensureProcessEngine()
        super.onCreate(savedInstanceState)
        createHighPriorityNotificationChannel()
        enableWakeAndLockScreenDisplay()
        showPersistentAssistantNotification()
    }

    override fun onResume() {
        super.onResume()
        val now = System.currentTimeMillis()
        if (lastSuggestionPostedAt > 0L && now - lastSuggestionPostedAt > 120_000L) {
            showPersistentAssistantNotification()
        }
    }

    // One FlutterEngine per process, kept alive across MainActivity instances.
    // If Back on the home screen finishes the activity while our foreground
    // services keep the process alive, a fresh engine would re-run main(), and
    // media_kit's MediaKit.ensureInitialized() then tears down the old isolate's
    // still-running libmpv handles, whose wakeup callbacks were freed with that
    // isolate -> SIGSEGV in libmpv.so (mpv/mpv core, mpv/opener).
    // Reattaching to the same cached engine never re-runs main(), so that can't happen.
    // Cached engines are not destroyed with the activity (shouldDestroyEngineWithHost
    // defaults to false), but they are also not started by Flutter, so we run the
    // Dart entrypoint here, and register plugins via the engine constructor.
    private fun ensureProcessEngine() {
        if (FlutterEngineCache.getInstance().contains(ENGINE_ID)) return
        val engine = FlutterEngine(applicationContext, null, true)
        engine.navigationChannel.setInitialRoute(initialRouteFromIntent(intent))
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    // Same rule Flutter uses for deep links on a cold start (oneova:// / mstudio://).
    private fun initialRouteFromIntent(intent: Intent?): String {
        val data = intent?.data ?: return "/"
        val path = data.path?.takeIf { it.isNotEmpty() } ?: "/"
        val query = data.query?.let { "?$it" } ?: ""
        val fragment = data.fragment?.let { "#$it" } ?: ""
        return path + query + fragment
    }

    override fun getCachedEngineId(): String = ENGINE_ID

    companion object {
        private const val ENGINE_ID = "oneova_main_engine"
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Android 8–11 have no auto-enter; enter PiP manually for video calls.
        if (callPipEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                enterPictureInPictureMode(
                    PictureInPictureParams.Builder().setAspectRatio(Rational(9, 16)).build()
                )
            } catch (_: Exception) {}
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        callPipChannel?.invokeMethod("pipChanged", mapOf("inPip" to isInPictureInPictureMode))
    }

    override fun onDestroy() {
        setRingback(false)
        setProximity(false)
        super.onDestroy()
    }

    private fun setRingback(on: Boolean) {
        try {
            if (on) {
                if (ringback != null) return
                ringback = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 70).also {
                    it.startTone(ToneGenerator.TONE_SUP_RINGTONE)
                }
            } else {
                ringback?.stopTone()
                ringback?.release()
                ringback = null
            }
        } catch (_: Exception) {
            ringback = null
        }
    }

    private fun setProximity(on: Boolean) {
        try {
            if (on) {
                if (proximityLock?.isHeld == true) return
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
                proximityLock = pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "oneova:call_proximity")
                    .also { it.acquire(4 * 60 * 60 * 1000L) }
            } else {
                proximityLock?.let { if (it.isHeld) it.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY) }
                proximityLock = null
            }
        } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        checkAssistantWakeIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Payment device key: hardware-backed, biometric-gated signing (DeviceKeyChannel.kt).
        DeviceKeyChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        // KYC country detector: SIM, network and on-device geocoder (CountrySignalsChannel.kt).
        CountrySignalsChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        // Live Studio "Share to table": mediaProjection foreground service.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.oneova.app/live_screen_capture").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> { LiveScreenCaptureService.start(applicationContext); result.success(true) }
                    "stop" -> { LiveScreenCaptureService.stop(applicationContext); result.success(true) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("screen_capture_service", e.message, null)
            }
        }
        callPipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_PIP_CHANNEL)
        callPipChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setProximity") {
                setProximity(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            } else if (call.method == "ringback") {
                setRingback(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            } else if (call.method == "setAutoEnter") {
                callPipEnabled = call.argument<Boolean>("enabled") ?: false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    try {
                        setPictureInPictureParams(
                            PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(9, 16))
                                .setAutoEnterEnabled(callPipEnabled)
                                .build()
                        )
                    } catch (_: Exception) {}
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        OvaDeviceHub.register(this, flutterEngine)

        assistantChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OVA_CHANNEL)
        assistantChannel?.setMethodCallHandler(
            OvaAssistantMethodHandler(
                this,
                onWakeDisplay = { enableWakeAndLockScreenDisplay() },
                onShowNotification = { showPersistentAssistantNotification() },
            )
        )
    }

    private fun enableWakeAndLockScreenDisplay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    private fun createHighPriorityNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val soundUri = Uri.parse(
                ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/" + R.raw.oneova_notification
            )

            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            val notificationManager = getSystemService(NotificationManager::class.java)

            // Primary channel + refreshed v3 channel so existing installs immediately pick up the new catchy chime
            val channels = listOf(
                Triple(
                    "oneova_high_importance_channel",
                    "Oneova Priority Alerts",
                    "Instant notifications for live streams, new followers, studio exports, and messages."
                ),
                Triple(
                    "oneova_ai_pulse_channel",
                    "Oneova Live AI Suggestions & Pulse",
                    "Live AI creative suggestions, smart cross-app actions, and studio insights."
                )
            )

            for ((id, name, desc) in channels) {
                val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_HIGH).apply {
                    description = desc
                    enableLights(true)
                    lightColor = Color.parseColor("#0C4FA8")
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 90, 50, 130, 50, 160)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setSound(soundUri, audioAttributes)
                    setShowBadge(true)
                }
                notificationManager?.createNotificationChannel(channel)
            }
        }
    }

    private fun checkAssistantWakeIntent(intent: Intent?) {
        if (intent?.getBooleanExtra("wake_assistant", false) == true ||
            intent?.action == "com.oneova.app.WAKE_ASSISTANT") {
            enableWakeAndLockScreenDisplay()
            val query = intent?.getStringExtra("pending_query")
            val params = if (query != null) mapOf("query" to query) else null
            assistantChannel?.invokeMethod("onBackgroundWake", params)
        }
    }

    private fun showPersistentAssistantNotification(customTitle: String? = null, customBody: String? = null) {
        lastSuggestionPostedAt = System.currentTimeMillis()
        val suggestions = listOf(
            "✨ Ova AI · Trending Reel Hook" to "Start your next Reel with a 1.5s visual contrast cut — creators using fast hook transitions are seeing +42% watch time today.",
            "🎬 Ova Director · Multi-Photo + Music" to "Drop up to 10 photos in Status or Reels with a trending beat — carousel posts with music are getting 2.3× more replies right now.",
            "⚡ Ova Live Pulse · Smart Quick Replies" to "Cross-app notifications now pop up live inside Oneova with 1-second AI reply pills so you never miss a message while creating.",
            "🎨 Ova Color Grader · Cinema Look" to "Try 'Golden Hour Warmth' or ask Ova AI to grade your clip in natural language before posting your next Reel.",
            "🚀 Ova Growth AI · Best Window to Post" to "Your audience engagement peaks in the next 45 minutes — record a 15s update or drop a musical photo story now.",
            "🎙️ Ova Voice Studio · Instant Polish" to "Tap the AI Polish ✨ button in the composer to turn quick voice notes into punchy captions, scripts, or smart replies in 1 second.",
            "🔥 Ova AI · Remix & Collab Idea" to "Reply to your top comment with a short video or multi-photo story to spark a back-and-forth thread with your followers.",
            "💡 Ova Strategist · Bio & Hook Tip" to "Pin a high-retention Reel and add 3 niche keywords to your caption so Oneova Semantic Search surfaces your work first."
        )
        val picked = suggestions.random()
        val titleText = customTitle?.takeIf { it.isNotBlank() } ?: picked.first
        val bodyText = customBody?.takeIf { it.isNotBlank() } ?: picked.second

        val channelId = "oneova_ai_pulse_channel"
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("wake_assistant", true)
            putExtra("pending_query", bodyText)
            action = "com.oneova.app.WAKE_ASSISTANT"
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        } else {
            android.app.PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = android.app.PendingIntent.getActivity(this, 1001, intent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle(titleText)
            .setContentText(bodyText)
            .setStyle(Notification.BigTextStyle().bigText(bodyText).setBigContentTitle(titleText))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(false)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(7771, notification)
    }
}
