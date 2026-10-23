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
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * System-Wide Floating Overlay Service for Oneova Ova Assistant.
 * Renders an ambient floating assistant dock and trigger bubble directly over any Android application.
 */
class OvaOverlayService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayRoot: FrameLayout? = null
    private var isExpanded: Boolean = false

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
            ACTION_TOGGLE -> {
                if (overlayRoot?.visibility == View.VISIBLE) {
                    if (isExpanded) collapseOverlay() else expandOverlay()
                } else {
                    showOverlay()
                }
            }
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
            .setContentText("Tap to open or drag edge bubble over apps")
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
                        // Click detected -> Expand floating assistant dock
                        expandOverlay()
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

    private fun expandOverlay() {
        isExpanded = true
        val dp = resources.displayMetrics.density
        val root = overlayRoot ?: return

        root.removeAllViews()

        val params = root.layoutParams as WindowManager.LayoutParams
        params.width = (resources.displayMetrics.widthPixels * 0.92).toInt()
        params.height = WindowManager.LayoutParams.WRAP_CONTENT
        params.flags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
        params.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        params.y = (32 * dp).toInt()
        params.x = 0

        // Build Floating Dock Card matching Oneova style
        val dockCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding((16 * dp).toInt(), (14 * dp).toInt(), (16 * dp).toInt(), (14 * dp).toInt())
            background = GradientDrawable().apply {
                cornerRadius = 22 * dp
                setColor(Color.parseColor("#F2141416")) // Deep Dark Glass
                setStroke((1 * dp).toInt(), Color.parseColor("#330C4FA8"))
            }

            // Header row: [Icon Oneova] ... [Close]
            val headerRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    bottomMargin = (12 * dp).toInt()
                }

                val title = TextView(context).apply {
                    text = "Oneova Ambient AI"
                    setTextColor(Color.WHITE)
                    textSize = 14f
                    typeface = android.graphics.Typeface.DEFAULT_BOLD
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
                addView(title)

                val closeBtn = TextView(context).apply {
                    text = "✕"
                    setTextColor(Color.parseColor("#9CA3AF"))
                    textSize = 16f
                    setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
                    setOnClickListener {
                        collapseOverlay()
                    }
                }
                addView(closeBtn)
            }
            addView(headerRow)

            // Quick command capsules: [Back] [Home] [WhatsApp] [Recents]
            val chipsScroll = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    bottomMargin = (12 * dp).toInt()
                }

                fun addActionChip(label: String, action: () -> Unit) {
                    val chip = TextView(context).apply {
                        text = label
                        setTextColor(Color.parseColor("#F3F4F6"))
                        textSize = 11.5f
                        setPadding((10 * dp).toInt(), (5 * dp).toInt(), (10 * dp).toInt(), (5 * dp).toInt())
                        background = GradientDrawable().apply {
                            cornerRadius = 14 * dp
                            setColor(Color.parseColor("#262628"))
                            setStroke((1 * dp).toInt(), Color.parseColor("#26FFFFFF"))
                        }
                        layoutParams = LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT
                        ).apply {
                            rightMargin = (8 * dp).toInt()
                        }
                        setOnClickListener { action() }
                    }
                    addView(chip)
                }

                addActionChip("⇦ Back") {
                    OvaAccessibilityService.instance?.global("back")
                }
                addActionChip("⌂ Home") {
                    OvaAccessibilityService.instance?.global("home")
                }
                addActionChip("▢ Recents") {
                    OvaAccessibilityService.instance?.global("recents")
                }
                addActionChip("📸 Screenshot") {
                    OvaAccessibilityService.instance?.global("screenshot")
                }
            }
            addView(chipsScroll)

            // Input Row: [ EditText ] [ Send Button ]
            val inputRow = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding((10 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
                background = GradientDrawable().apply {
                    cornerRadius = 24 * dp
                    setColor(Color.parseColor("#2C2C2E"))
                    setStroke((1 * dp).toInt(), Color.parseColor("#1FFFFFFF"))
                }

                val editText = EditText(context).apply {
                    hint = "Ask Ova or command device..."
                    setHintTextColor(Color.parseColor("#6B7280"))
                    setTextColor(Color.WHITE)
                    textSize = 13f
                    background = null
                    isSingleLine = true
                    layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                        setPadding((6 * dp).toInt(), (6 * dp).toInt(), (6 * dp).toInt(), (6 * dp).toInt())
                    }
                }
                addView(editText)

                val sendBtn = TextView(context).apply {
                    text = "➤"
                    setTextColor(Color.parseColor("#0C4FA8")) // Brand blue
                    textSize = 16f
                    setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
                    setOnClickListener {
                        val query = editText.text.toString().trim()
                        if (query.isNotEmpty()) {
                            editText.setText("")
                            handleAmbientCommand(query)
                        }
                    }
                }
                addView(sendBtn)
            }
            addView(inputRow)
        }

        root.addView(dockCard)
        windowManager?.updateViewLayout(root, params)
    }

    private fun collapseOverlay() {
        isExpanded = false
        overlayRoot?.let { root ->
            windowManager?.removeView(root)
            overlayRoot = null
        }
        buildOverlayView()
    }

    private fun handleAmbientCommand(query: String) {
        val lower = query.lowercase()
        val a11y = OvaAccessibilityService.instance

        if (a11y != null) {
            when {
                lower == "back" || lower == "go back" -> {
                    a11y.global("back")
                    a11y.showBubble("Going back", isUser = false)
                }
                lower == "home" || lower == "go home" -> {
                    a11y.global("home")
                    a11y.showBubble("Navigating to Home screen", isUser = false)
                }
                lower.contains("recents") || lower == "recent apps" -> {
                    a11y.global("recents")
                    a11y.showBubble("Showing recent applications", isUser = false)
                }
                lower.contains("notifications") -> {
                    a11y.global("notifications")
                    a11y.showBubble("Opening notification panel", isUser = false)
                }
                lower.contains("screenshot") -> {
                    a11y.global("screenshot")
                    a11y.showBubble("Capturing screenshot", isUser = false)
                }
                lower.startsWith("scroll down") -> {
                    a11y.scroll(forward = true)
                    a11y.showBubble("Scrolled down", isUser = false)
                }
                lower.startsWith("scroll up") -> {
                    a11y.scroll(forward = false)
                    a11y.showBubble("Scrolled up", isUser = false)
                }
                lower.startsWith("tap ") || lower.startsWith("click ") -> {
                    val label = query.substring(4).trim()
                    val clicked = a11y.clickByText(label)
                    a11y.showBubble(if (clicked) "Tapped '$label'" else "Couldn't locate '$label'", isUser = false)
                }
                lower.startsWith("type ") -> {
                    val textToType = query.substring(5).trim()
                    val typed = a11y.typeText(textToType)
                    a11y.showBubble(if (typed) "Typed text" else "No active text field focused", isUser = false)
                }
                else -> {
                    // Open Oneova to handle via full AI brain
                    a11y.showBubble("Connecting to Oneova AI Brain...", isUser = false)
                    val wakeIntent = Intent(this, MainActivity::class.java).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        putExtra("wake_assistant", true)
                        putExtra("pending_query", query)
                        action = "com.oneova.app.WAKE_ASSISTANT"
                    }
                    startActivity(wakeIntent)
                }
            }
        } else {
            // Wake full Oneova app
            val wakeIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("wake_assistant", true)
                putExtra("pending_query", query)
                action = "com.oneova.app.WAKE_ASSISTANT"
            }
            startActivity(wakeIntent)
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
