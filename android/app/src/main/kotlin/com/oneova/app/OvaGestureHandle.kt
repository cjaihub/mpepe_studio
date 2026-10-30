package com.oneova.app

import android.annotation.SuppressLint
import android.content.Context
import android.animation.ValueAnimator
import android.graphics.PixelFormat
import android.graphics.PointF
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import kotlin.math.hypot

/**
 * The "Ova handle": a slim bar on the screen edge, shown over every app and
 * (when hosted by the accessibility service) over the lock screen.
 *
 * Android does not let an app see touches meant for other apps, so an "O"
 * cannot be detected on a bare screen. Instead the stroke starts on this
 * handle: Android keeps sending the rest of that finger's movement to the
 * handle's window wherever it goes, so the "O" itself can be drawn anywhere.
 *
 * - Start on the handle and draw an "O" -> opens Ova.
 * - Tap the handle -> opens Ova.
 * - Long-press, then drag -> moves the handle (left/right edge, any height).
 */
class OvaGestureHandle(
    private val context: Context,
    private val windowType: Int,
    private val onTrigger: (source: String) -> Unit,
) {
    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())
    private val density = context.resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    private var root: FrameLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var trail: OvaStrokeView? = null

    private val points = ArrayList<PointF>()
    private var downTime = 0L
    private var dragging = false
    private var movedPastSlop = false
    private val longPress = Runnable {
        dragging = true
        root?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }

    val isShowing: Boolean get() = root != null

    fun show() {
        if (root != null) return
        val cfg = OvaTriggerConfig.load(context)
        val touchW = (28 * density).toInt()
        val touchH = (96 * density).toInt()

        val bar = View(context).apply {
            background = GradientDrawable().apply {
                cornerRadius = 4 * density
                setColor(context.getColor(R.color.brand_blue))
                setStroke((1 * density).toInt(), context.getColor(R.color.brand_pink))
            }
            alpha = 0.85f
            contentDescription = "Ova handle. Tap, or start here and draw an O, to open Ova."
        }
        val frame = FrameLayout(context).apply {
            addView(
                bar,
                FrameLayout.LayoutParams((6 * density).toInt(), (64 * density).toInt()).apply {
                    gravity = Gravity.CENTER_VERTICAL or (if (cfg.handleRight) Gravity.END else Gravity.START)
                    marginEnd = (2 * density).toInt()
                    marginStart = (2 * density).toInt()
                }
            )
        }

        val lp = WindowManager.LayoutParams(
            touchW,
            touchH,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or (if (cfg.handleRight) Gravity.END else Gravity.START)
            x = 0
            y = (context.resources.displayMetrics.heightPixels * cfg.handleY).toInt() - touchH / 2
        }

        attachTouch(frame, lp)
        try {
            wm.addView(frame, lp)
            root = frame
            params = lp
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun hide() {
        main.removeCallbacks(longPress)
        removeTrail()
        root?.let {
            try {
                wm.removeView(it)
            } catch (_: Exception) {}
        }
        root = null
        params = null
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachTouch(frame: FrameLayout, lp: WindowManager.LayoutParams) {
        frame.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    points.clear()
                    points.add(PointF(e.rawX, e.rawY))
                    downTime = e.eventTime
                    dragging = false
                    movedPastSlop = false
                    main.postDelayed(longPress, 450)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val start = points.firstOrNull() ?: return@setOnTouchListener true
                    if (dragging) {
                        lp.y = (e.rawY - lp.height / 2f).toInt()
                        try {
                            wm.updateViewLayout(frame, lp)
                        } catch (_: Exception) {}
                        return@setOnTouchListener true
                    }
                    points.add(PointF(e.rawX, e.rawY))
                    if (!movedPastSlop && hypot(e.rawX - start.x, e.rawY - start.y) > touchSlop) {
                        movedPastSlop = true
                        main.removeCallbacks(longPress)
                    }
                    // The trail appears only once the stroke curves like an "O".
                    if (trail == null && movedPastSlop && OvaStrokeRecognizer.looksLikeO(points, density)) showTrail()
                    trail?.update(points)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    main.removeCallbacks(longPress)
                    when {
                        dragging -> {
                            val dm = context.resources.displayMetrics
                            val right = e.rawX > dm.widthPixels / 2f
                            OvaTriggerConfig.saveHandlePosition(context, right, e.rawY / dm.heightPixels)
                            // Re-attach on the chosen edge.
                            hide()
                            show()
                        }
                        !movedPastSlop && e.eventTime - downTime < 350 -> {
                            frame.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                            onTrigger("handle_tap")
                        }
                        OvaStrokeRecognizer.isCircle(points, density) -> {
                            frame.performHapticFeedback(
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM
                                else HapticFeedbackConstants.LONG_PRESS
                            )
                            if (trail == null) showTrail()
                            val view = trail
                            trail = null
                            // Ring closes, pulses and becomes the Ova orb; then Ova opens.
                            view?.summon(ArrayList(points), reduceMotion()) {
                                removeWindow(view)
                                onTrigger("draw_o")
                            } ?: onTrigger("draw_o")
                        }
                    }
                    // Anything else: the trail (if any) fades out quietly.
                    fadeOutTrail()
                    dragging = false
                    points.clear()
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    main.removeCallbacks(longPress)
                    fadeOutTrail()
                    dragging = false
                    points.clear()
                    true
                }
                else -> false
            }
        }
    }

    // ---- Stroke trail drawn over the whole screen while tracing the "O" ----

    private fun reduceMotion(): Boolean =
        OvaTriggerConfig.load(context).reduceMotion || !ValueAnimator.areAnimatorsEnabled()

    private fun showTrail() {
        if (trail != null) return
        val view = OvaStrokeView(context)
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            windowType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        try {
            wm.addView(view, lp)
            trail = view
        } catch (_: Exception) {}
    }

    private fun fadeOutTrail() {
        val view = trail ?: return
        trail = null
        view.fadeOut(reduceMotion()) { removeWindow(view) }
    }

    private fun removeTrail() {
        trail?.let { removeWindow(it) }
        trail = null
    }

    private fun removeWindow(view: View) {
        try {
            wm.removeView(view)
        } catch (_: Exception) {}
    }
}
