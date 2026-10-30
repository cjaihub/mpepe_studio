package com.oneova.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Live Studio "Share to table": Android 14+ only allows MediaProjection while a
 * foreground service of type mediaProjection is running. Order (Dart side):
 *   1. flutter_webrtc Helper.requestCapturePermission()  (user consent)
 *   2. LiveScreenCaptureService.start()                  (this service)
 *   3. createScreenShareTrack()                          (uses the stored consent)
 *   4. LiveScreenCaptureService.stop() when sharing ends
 *
 * Game Live: the host leaves Oneova to play, so on API 30+ the service also
 * claims the microphone (and the camera when CAMERA is granted) types; that
 * keeps the mic/camera tracks alive while Oneova is in the background.
 * Android throws when a type is claimed without its runtime permission, so
 * each type is only added when its permission is granted at start.
 */
class LiveScreenCaptureService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, serviceTypes())
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
    }

    private fun granted(permission: String): Boolean =
        checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** mediaProjection, plus microphone / camera (API 30+) when their permission is granted. */
    private fun serviceTypes(): Int {
        var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (granted(android.Manifest.permission.RECORD_AUDIO)) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            }
            if (granted(android.Manifest.permission.CAMERA)) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
        }
        return types
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Live screen sharing", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while you share your screen to the Live Studio table"
                setShowBadge(false)
            }
        )
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Oneova is sharing your screen")
            .setContentText("Your live keeps going while you use other apps")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "oneova_live_screen_share"
        private const val NOTIFICATION_ID = 7341

        fun start(context: Context) {
            val intent = Intent(context, LiveScreenCaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LiveScreenCaptureService::class.java))
        }
    }
}
