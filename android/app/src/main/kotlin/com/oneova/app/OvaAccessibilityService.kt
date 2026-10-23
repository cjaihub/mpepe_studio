package com.oneova.app

import android.accessibilityservice.AccessibilityButtonController
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Oneova Ova system-wide control layer.
 * Requires the user to enable it once in Settings > Accessibility.
 */
class OvaAccessibilityService : AccessibilityService() {

    private val main = Handler(Looper.getMainLooper())
    private var bubbleContainer: LinearLayout? = null
    private var currentPackage: String = ""
    private val recentNotifications = java.util.concurrent.CopyOnWriteArrayList<Map<String, Any>>()

    companion object {
        @Volatile
        var instance: OvaAccessibilityService? = null
            private set

        fun isRunning(): Boolean = instance != null
    }

    fun getRecentNotifications(): List<Map<String, Any>> = recentNotifications.toList()

    private fun addRecentNotification(packageName: String, text: String) {
        val item = mapOf<String, Any>(
            "packageName" to packageName,
            "text" to text,
            "timestamp" to System.currentTimeMillis()
        )
        recentNotifications.add(0, item)
        while (recentNotifications.size > 25) {
            recentNotifications.removeAt(recentNotifications.size - 1)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            accessibilityButtonController.registerAccessibilityButtonCallback(
                object : AccessibilityButtonController.AccessibilityButtonCallback() {
                    override fun onClicked(controller: AccessibilityButtonController) {
                        wakeAssistant()
                    }
                }
            )
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: ""
        if (pkg.isNotEmpty() && event?.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            if (pkg != currentPackage) OvaDeviceHub.emit("foreground", mapOf("package" to pkg))
            currentPackage = pkg
        } else if (event?.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
            val textList = event.text?.map { it.toString() } ?: emptyList()
            if (textList.isNotEmpty()) {
                val fullText = textList.joinToString(" ")
                addRecentNotification(if (pkg.isNotEmpty()) pkg else "System", fullText)
            }
        }
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: Intent?): Boolean {
        removeBubbles()
        instance = null
        return super.onUnbind(intent)
    }

    // ---- Wake Ova (Accessibility button / QS tile / notification) ----
    fun wakeAssistant() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("wake_assistant", true)
            action = "com.oneova.app.WAKE_ASSISTANT"
        }
        startActivity(intent)
    }

    fun foregroundPackage(): String = currentPackage

    // ---- Global actions ----
    fun global(action: String): Boolean = when (action) {
        "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
        "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
        "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
        "notifications" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
        "quick_settings" -> performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
        "lock" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN) else false
        "screenshot" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) performGlobalAction(GLOBAL_ACTION_TAKE_SCREENSHOT) else false
        else -> false
    }

    // ---- Screen reading ----
    fun readScreenText(): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        collectText(root, sb, 0)
        return sb.toString().take(8000)
    }

    private fun collectText(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 40) return
        if (node.isPassword) return // never read password fields
        val text = node.text?.toString() ?: node.contentDescription?.toString()
        if (!text.isNullOrBlank()) sb.append(text.trim()).append('\n')
        for (i in 0 until node.childCount) collectText(node.getChild(i), sb, depth + 1)
    }

    // ---- Click / type / scroll ----
    fun clickByText(label: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val matches = root.findAccessibilityNodeInfosByText(label)
        for (node in matches) {
            var target: AccessibilityNodeInfo? = node
            while (target != null && !target.isClickable) target = target.parent
            if (target != null && target.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
        }
        return false
    }

    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        if (focused.isPassword) return false
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun scroll(forward: Boolean): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = findScrollable(root) ?: return false
        return node.performAction(
            if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        )
    }

    private fun findScrollable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) return null
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val found = findScrollable(node.getChild(i))
            if (found != null) return found
        }
        return null
    }

    fun tap(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 60))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300): Boolean {
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    // ---- Fading chat bubbles at top of the screen, over any app ----
    fun showBubble(text: String, isUser: Boolean, durationMs: Long = 6000) {
        main.post {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val container = bubbleContainer ?: LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val lp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP
                    y = 96
                }
                wm.addView(this, lp)
                bubbleContainer = this
            }

            val dp = resources.displayMetrics.density
            val tv = TextView(this).apply {
                this.text = text
                setTextColor(Color.WHITE)
                textSize = 13.5f
                setPadding((14 * dp).toInt(), (9 * dp).toInt(), (14 * dp).toInt(), (9 * dp).toInt())
                maxLines = 6
                background = GradientDrawable().apply {
                    cornerRadius = 18 * dp
                    // Brand blue for user, dark glass for Ova, thin pink hairline accent
                    setColor(if (isUser) Color.parseColor("#E60C4FA8") else Color.parseColor("#E61A1A1A"))
                    setStroke((1 * dp).toInt(), Color.parseColor("#66FF2D87"))
                }
                alpha = 0f
                val lp = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    gravity = if (isUser) Gravity.END else Gravity.START
                    setMargins((16 * dp).toInt(), (4 * dp).toInt(), (16 * dp).toInt(), (4 * dp).toInt())
                }
                layoutParams = lp
            }
            container.addView(tv)
            tv.animate().alpha(1f).setDuration(220).start()
            main.postDelayed({
                tv.animate().alpha(0f).setDuration(600).withEndAction {
                    container.removeView(tv)
                    if (container.childCount == 0) removeBubbles()
                }.start()
            }, durationMs)
        }
    }

    private fun removeBubbles() {
        bubbleContainer?.let {
            try {
                (getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(it)
            } catch (_: Exception) {}
        }
        bubbleContainer = null
    }
}
