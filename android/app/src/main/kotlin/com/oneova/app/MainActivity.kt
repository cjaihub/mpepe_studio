package com.oneova.app

import android.app.Notification
import android.app.PictureInPictureParams
import android.util.Rational
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
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

    override fun onCreate(savedInstanceState: Bundle?) {
        ensureProcessEngine()
        super.onCreate(savedInstanceState)
        createHighPriorityNotificationChannel()
        enableWakeAndLockScreenDisplay()
        showPersistentAssistantNotification()
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        checkAssistantWakeIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_PIP_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setAutoEnter") {
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
        assistantChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundAssistant" -> {
                    showPersistentAssistantNotification()
                    result.success(true)
                }
                "stopBackgroundAssistant" -> {
                    val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    nm.cancel(7771)
                    result.success(true)
                }
                "getDeviceInfo" -> {
                    try {
                        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                        val batteryCapacity = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
                        val isCharging = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val status = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS) ?: -1
                            status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
                        } else false

                        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                        var networkType = "Offline"
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val activeNetwork = connectivityManager?.activeNetwork
                            val caps = connectivityManager?.getNetworkCapabilities(activeNetwork)
                            if (caps != null) {
                                networkType = when {
                                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
                                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile data"
                                    else -> "Other"
                                }
                            }
                        }
                        val stat = android.os.StatFs(android.os.Environment.getDataDirectory().path)

                        val data = mapOf(
                            "batteryLevel" to (batteryCapacity / 100.0),
                            "isCharging" to isCharging,
                            "networkType" to networkType,
                            "availableStorageMB" to (stat.availableBytes / 1_000_000L)
                        )
                        result.success(data)
                    } catch (e: Exception) {
                        result.error("DEVICE_INFO_ERROR", e.message, null)
                    }
                }

                "getRecentNotifications" -> {
                    try {
                        val notifs = OvaAccessibilityService.instance?.getRecentNotifications() ?: emptyList<Map<String, Any>>()
                        result.success(notifs)
                    } catch (e: Exception) {
                        result.error("NOTIFS_ERROR", e.message, null)
                    }
                }

                "openWhatsApp" -> {
                    try {
                        val phone = call.argument<String>("phone") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        val cleanedPhone = phone.replace(Regex("[^0-9]"), "")

                        val uri = if (cleanedPhone.isNotEmpty()) {
                            Uri.parse("https://api.whatsapp.com/send?phone=$cleanedPhone&text=${Uri.encode(message)}")
                        } else {
                            Uri.parse("https://api.whatsapp.com/send?text=${Uri.encode(message)}")
                        }

                        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
                            setPackage("com.whatsapp")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }

                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                            result.success(true)
                        } else {
                            // Fallback without strict package name
                            val fallbackIntent = Intent(Intent.ACTION_VIEW, uri).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(fallbackIntent)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("WHATSAPP_LAUNCH_ERROR", e.message, null)
                    }
                }

                "openCamera" -> {
                    try {
                        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CAMERA_LAUNCH_ERROR", e.message, null)
                    }
                }

                "launchApp" -> {
                    try {
                        val packageName = call.argument<String>("packageName") ?: ""
                        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                        if (launchIntent != null) {
                            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            startActivity(launchIntent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("APP_LAUNCH_ERROR", e.message, null)
                    }
                }

                "openSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_LAUNCH_ERROR", e.message, null)
                    }
                }

                "triggerHapticPulse" -> {
                    try {
                        val durationMs = (call.argument<Int>("durationMs") ?: 50).toLong()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                            vibratorManager?.defaultVibrator?.vibrate(
                                VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator?.vibrate(
                                    VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
                                )
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator?.vibrate(durationMs)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("HAPTIC_ERROR", e.message, null)
                    }
                }

                "canDrawOverlays" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }

                "requestOverlayPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OVERLAY_PERMISSION_ERROR", e.message, null)
                    }
                }

                "wakeScreen" -> {
                    try {
                        enableWakeAndLockScreenDisplay()
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                        @Suppress("DEPRECATION")
                        val wakeLock = powerManager?.newWakeLock(
                            android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK or android.os.PowerManager.ACQUIRE_CAUSES_WAKEUP,
                            "oneova:assistant_wake"
                        )
                        wakeLock?.acquire(3000)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKE_ERROR", e.message, null)
                    }
                }

                "isAccessibilityEnabled" -> result.success(OvaAccessibilityService.isRunning())

                "openAccessibilitySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        })
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("A11Y_SETTINGS_ERROR", e.message, null)
                    }
                }

                "deviceControl" -> {
                    val svc = OvaAccessibilityService.instance
                    if (svc == null) {
                        result.error("A11Y_DISABLED", "Enable Oneova Ova in Accessibility settings", null)
                    } else {
                        try {
                            val action = call.argument<String>("action") ?: ""
                            val ok: Any = when (action) {
                                "global" -> svc.global(call.argument<String>("name") ?: "")
                                "readScreen" -> svc.readScreenText()
                                "foregroundPackage" -> svc.foregroundPackage()
                                "clickText" -> svc.clickByText(call.argument<String>("text") ?: "")
                                "typeText" -> svc.typeText(call.argument<String>("text") ?: "")
                                "scroll" -> svc.scroll(call.argument<Boolean>("forward") ?: true)
                                "tap" -> svc.tap(
                                    (call.argument<Double>("x") ?: 0.0).toFloat(),
                                    (call.argument<Double>("y") ?: 0.0).toFloat()
                                )
                                "swipe" -> svc.swipe(
                                    (call.argument<Double>("x1") ?: 0.0).toFloat(),
                                    (call.argument<Double>("y1") ?: 0.0).toFloat(),
                                    (call.argument<Double>("x2") ?: 0.0).toFloat(),
                                    (call.argument<Double>("y2") ?: 0.0).toFloat()
                                )
                                "bubble" -> {
                                    svc.showBubble(
                                        call.argument<String>("text") ?: "",
                                        call.argument<Boolean>("isUser") ?: false
                                    )
                                    true
                                }
                                else -> false
                            }
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("DEVICE_CONTROL_ERROR", e.message, null)
                        }
                    }
                }

                "startSystemOverlay" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
                            result.error("PERMISSION_DENIED", "Overlay permission required", null)
                        } else {
                            OvaOverlayService.start(this)
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("START_OVERLAY_ERROR", e.message, null)
                    }
                }

                "stopSystemOverlay" -> {
                    try {
                        OvaOverlayService.stop(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("STOP_OVERLAY_ERROR", e.message, null)
                    }
                }

                "isSystemOverlayActive" -> result.success(OvaOverlayService.isRunning)

                "openAssistantSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_VOICE_INPUT_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                        } else {
                            startActivity(Intent(Settings.ACTION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            })
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ASSISTANT_SETTINGS_ERROR", e.message, null)
                    }
                }

                "openPowerButtonSettings" -> {
                    try {
                        val intent = Intent("android.settings.GESTURE_SETTINGS").apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        if (intent.resolveActivity(packageManager) != null) {
                            startActivity(intent)
                        } else {
                            startActivity(Intent(Settings.ACTION_SETTINGS).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                            })
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("GESTURE_SETTINGS_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
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
            val channelId = "oneova_high_importance_channel"
            val channelName = "OneOva Priority Alerts"
            val channelDescription = "Instant notifications for live streams, new followers, studio exports, and messages."
            val importance = NotificationManager.IMPORTANCE_HIGH

            val soundUri = Uri.parse(
                ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + packageName + "/" + R.raw.oneova_notification
            )

            val audioAttributes = AudioAttributes.Builder()
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .build()

            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                enableLights(true)
                lightColor = Color.parseColor("#1877F2") // OneOva Brand Blue
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 100, 60, 140)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(soundUri, audioAttributes)
                setShowBadge(true)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
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

    private fun showPersistentAssistantNotification() {
        val channelId = "oneova_high_importance_channel"
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("wake_assistant", true)
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
            .setContentTitle("Oneova AI Studio")
            .setContentText("All you need in your Pocket as a creative")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(7771, notification)
    }
}
