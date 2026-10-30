package com.oneova.app

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handler for the `com.oneova.app/ova_assistant` channel. Shared by the main
 * app engine ([MainActivity]) and the compact system overlay engine
 * ([OvaAssistActivity]) so Ova has the same device tools in both.
 */
class OvaAssistantMethodHandler(
    private val activity: Activity,
    private val onWakeDisplay: () -> Unit,
    private val onShowNotification: () -> Unit,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        with(activity) {
            when (call.method) {
                "startBackgroundAssistant" -> {
                    onShowNotification()
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
                        onWakeDisplay()
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

                // System-wide Ova triggers (Draw "O" handle, button shortcut, lock screen).
                "setTriggerConfig" -> {
                    OvaTriggerConfig.save(this, call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                    OvaAccessibilityService.instance?.applyTriggerConfig()
                    result.success(true)
                }

                "getTriggerConfig" -> result.success(OvaTriggerConfig.load(this).toMap())

                "openOvaOverlay" -> {
                    OvaAssistActivity.open(this, "app")
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }
}
