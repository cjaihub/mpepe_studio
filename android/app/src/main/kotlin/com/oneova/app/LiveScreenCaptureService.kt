package com.oneova.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
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
 */
class LiveScreenCaptureService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_NOT_STICKY
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
            .setContentText("Your screen is on the Live Studio table")
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
