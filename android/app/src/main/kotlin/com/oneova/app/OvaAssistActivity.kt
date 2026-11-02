package com.oneova.app

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Compact Ova over any app, the home screen or the lock screen.
 *
 * A translucent activity in its own task, so the app underneath (WhatsApp,
 * the launcher, ...) stays visible. It runs the `ovaOverlayMain` Dart
 * entrypoint (only the Ova panel, not the whole Oneova app) on a separate,
 * cached engine so it opens instantly after the first time.
 *
 * Opened by: the Ova handle ("O" gesture / tap), the button shortcut, the
 * accessibility button, the Quick Settings tile, the floating bubble, and the
 * system assist gesture (long-press power / home) once Oneova is the default
 * digital assistant.
 *
 * On the lock screen nothing is shown until the user unlocks (fingerprint,
 * face, PIN, pattern or password) via [KeyguardManager.requestDismissKeyguard].
 */
class OvaAssistActivity : FlutterFragmentActivity() {

    companion object {
        private const val ENGINE_ID = "ova_overlay_engine"
        private const val CHANNEL = "com.oneova.app/ova_overlay"
        const val EXTRA_SOURCE = "ova_source"

        fun open(context: Context, source: String) {
            val intent = Intent(context, OvaAssistActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra(EXTRA_SOURCE, source)
            }
            context.startActivity(intent)
        }
    }

    private var overlayChannel: MethodChannel? = null
    private var source = "app"
    private var unlocked = true
    private var awaitingUnlock = false

    override fun onCreate(savedInstanceState: Bundle?) {
        ensureOverlayEngine()
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
            android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
            android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        )
        handleLaunch(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunch(intent)
    }

    // Leaving Ova (Home, another app, screen off) closes it, so the next
    // open on a locked phone asks to unlock again.
    override fun onStop() {
        super.onStop()
        if (!awaitingUnlock && !isChangingConfigurations) finish()
    }

    private fun ensureOverlayEngine() {
        if (FlutterEngineCache.getInstance().contains(ENGINE_ID)) return
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val bundle = loader.findAppBundlePath()
            val engine = FlutterEngine(applicationContext, null, true)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(bundle, "ovaOverlayMain"))
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        } catch (e: Exception) {
            android.util.Log.e("OvaAssistActivity", "Failed to initialize overlay engine", e)
        }
    }

    override fun getCachedEngineId(): String = ENGINE_ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    // Transparent SurfaceView (drawn on top of the window); the default
    // TextureView path for transparent activities can stay blank on some GPUs.
    override fun getRenderMode(): RenderMode = RenderMode.surface

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Same device tools as in the full app.
        MethodChannel(messenger, "com.oneova.app/ova_assistant").setMethodCallHandler(
            OvaAssistantMethodHandler(this, onWakeDisplay = {}, onShowNotification = {})
        )
        OvaDeviceHub.register(this, flutterEngine, events = false)

        overlayChannel = MethodChannel(messenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchState" -> result.success(launchState())
                    "openFullApp" -> {
                        openFullApp(call.argument<String>("route"))
                        result.success(true)
                    }
                    "close" -> {
                        finish()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        overlayChannel?.setMethodCallHandler(null)
        overlayChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun launchState(): Map<String, Any> = mapOf(
        "source" to source,
        "unlocked" to unlocked,
        "voiceMode" to OvaTriggerConfig.load(this).voiceMode,
    )

    private fun handleLaunch(intent: Intent?) {
        source = intent?.getStringExtra(EXTRA_SOURCE)
            ?: if (intent?.action == Intent.ACTION_ASSIST) "assist" else "app"

        val km = getSystemService(KeyguardManager::class.java)
        unlocked = km == null || !km.isKeyguardLocked
        // Fully visible on lock screen for instant voice mode, task planning, and message reading
        setContentVisible(true)
        notifyShown()
    }

    private fun setContentVisible(visible: Boolean) {
        window?.decorView?.alpha = if (visible) 1f else 0f
    }

    private fun notifyShown() {
        overlayChannel?.invokeMethod("onShow", launchState())
    }

    private fun openFullApp(route: String?) {
        val km = getSystemService(KeyguardManager::class.java)
        if (km != null && km.isKeyguardLocked && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            awaitingUnlock = true
            km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() {
                    awaitingUnlock = false
                    unlocked = true
                    launchFullAppIntent(route)
                }

                override fun onDismissCancelled() {
                    awaitingUnlock = false
                }

                override fun onDismissError() {
                    awaitingUnlock = false
                }
            })
        } else {
            launchFullAppIntent(route)
        }
    }

    private fun launchFullAppIntent(route: String?) {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (!route.isNullOrEmpty() && route.startsWith("/")) {
                action = Intent.ACTION_VIEW
                data = Uri.parse("oneova://app$route")
            }
        }
        startActivity(intent)
        finish()
    }
}
