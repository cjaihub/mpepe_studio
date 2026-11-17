package com.oneova.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * System-Wide Floating Overlay Service for Oneova Ova Assistant.
 * Renders a draggable "Ova" bubble over any Android application; tapping it
 * opens the compact Ova overlay ([OvaAssistActivity]).
 */
class OvaOverlayService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayRoot: FrameLayout? = null

    private var initialX: Int = 0
    private var initialY: Int = 0
    private var initialTouchX: Float = 0f
    private var initialTouchY: Float = 0f

    companion object {
        const val ACTION_SHOW = "com.oneova.app.SHOW_OVERLAY"
        const val ACTION_HIDE = "com.oneova.app.HIDE_OVERLAY"
        const val ACTION_TOGGLE = "com.oneova.app.TOGGLE_OVERLAY"
        const val CHANNEL_ID = "oneova_overlay_channel"
        const val NOTIFICATION_ID = 8882

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context) {
            val intent = Intent(context, OvaOverlayService::class.java).apply {
                action = ACTION_SHOW
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, OvaOverlayService::class.java).apply {
                action = ACTION_HIDE
            }
            context.startService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildForegroundNotification())
        buildOverlayView()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> showOverlay()
            ACTION_HIDE -> {
                hideOverlay()
                stopSelf()
            }
            ACTION_TOGGLE -> showOverlay()
            else -> showOverlay()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        removeOverlayView()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Oneova Assistant Floating Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Active floating assistant over Android applications"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(channel)
        }
    }

    private fun buildForegroundNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("wake_assistant", true)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 1002, intent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Oneova Ova Active")
            .setContentText("Tap the Ova bubble to ask Ova over any app")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun buildOverlayView() {
        if (overlayRoot != null) return

        val dp = resources.displayMetrics.density
        overlayRoot = FrameLayout(this).apply {
            // Master container
        }

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 20
            y = (resources.displayMetrics.heightPixels * 0.45).toInt()
        }

        // Render Collapsed Floating Pill
        val collapsedPill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding((12 * dp).toInt(), (8 * dp).toInt(), (14 * dp).toInt(), (8 * dp).toInt())
            background = GradientDrawable().apply {
                cornerRadius = 24 * dp
                setColor(Color.parseColor("#E6121214")) // Dark Studio Glass
                setStroke((1.5 * dp).toInt(), Color.parseColor("#0C4FA8")) // Brand Blue edge
            }

            // Dot accent
            val dot = View(context).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.parseColor("#FF2D87")) // Brand Pink accent
                }
                layoutParams = LinearLayout.LayoutParams((8 * dp).toInt(), (8 * dp).toInt()).apply {
                    rightMargin = (8 * dp).toInt()
                }
            }
            addView(dot)

            val label = TextView(context).apply {
                text = "Ova"
                setTextColor(Color.WHITE)
                textSize = 13f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
            }
            addView(label)

            val translateBtn = TextView(context).apply {
                text = "A文"
                setTextColor(Color.parseColor("#FF2D87"))
                textSize = 11f
                typeface = android.graphics.Typeface.DEFAULT_BOLD
                setPadding((8 * dp).toInt(), (2 * dp).toInt(), (2 * dp).toInt(), (2 * dp).toInt())
                contentDescription = "Translate current screen in place"
                setOnClickListener {
                    val svc = OvaAccessibilityService.instance
                    if (svc != null) {
                        svc.wakeAssistant("bubble_translate", "translate_screen")
                    } else {
                        OvaAssistActivity.open(context, "bubble_translate", "translate_screen")
                    }
                }
            }
            addView(translateBtn)

            tag = "collapsed_pill"
        }

        // Drag & Tap listener on pill
        collapsedPill.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - initialTouchX).toInt()
                    params.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(overlayRoot, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val diffX = Math.abs(event.rawX - initialTouchX)
                    val diffY = Math.abs(event.rawY - initialTouchY)
                    if (diffX < 10 && diffY < 10) {
                        // Tap -> capture snapshot if accessibility active & summon compact Ova pill.
                        val svc = OvaAccessibilityService.instance
                        if (svc != null) {
                            svc.wakeAssistant("bubble")
                        } else {
                            OvaAssistActivity.open(this, "bubble")
                        }
                    }
                    true
                }
                else -> false
            }
        }

        overlayRoot?.addView(collapsedPill)
        try {
            windowManager?.addView(overlayRoot, params)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun showOverlay() {
        overlayRoot?.visibility = View.VISIBLE
    }

    private fun hideOverlay() {
        overlayRoot?.visibility = View.GONE
    }

    private fun removeOverlayView() {
        overlayRoot?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        overlayRoot = null
    }
}
