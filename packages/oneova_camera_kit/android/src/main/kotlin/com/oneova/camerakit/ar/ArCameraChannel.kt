package com.oneova.camerakit.ar

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

/**
 * `oneova_camera_kit/ar_camera` (methods) and `.../frames` (tracking events)
 * for [ArCameraSession]. One session at a time; opening again closes the
 * previous one.
 */
internal class ArCameraChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val methods = MethodChannel(messenger, "oneova_camera_kit/ar_camera")
    private val events = EventChannel(messenger, "oneova_camera_kit/ar_camera/frames")
    private var sink: EventChannel.EventSink? = null
    private var session: ArCameraSession? = null

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    fun dispose() {
        session?.close()
        session = null
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "open") {
            open(call, result)
            return
        }
        val s = session
        if (s == null) {
            if (call.method == "close") result.success(null) else result.error("not_open", "AR camera is not open", null)
            return
        }
        when (call.method) {
            "close" -> {
                s.close()
                session = null
                result.success(null)
            }
            "setNeeds" -> {
                s.setNeeds(ArNeeds.fromMap(call.arguments as? Map<*, *>))
                result.success(null)
            }
            "setScene" -> {
                s.setScene(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                result.success(null)
            }
            "putModel" -> {
                val id = call.argument<String>("id")
                val path = call.argument<String>("path")
                if (id == null || path == null) {
                    result.error("bad_args", "id and path are required", null)
                } else {
                    s.putModel(id, path) { err -> if (err == null) result.success(null) else result.error("model_failed", err, null) }
                }
            }
            "putImage" -> {
                val id = call.argument<String>("id")
                val image = call.argument<Map<*, *>>("image")
                if (id == null || image == null) {
                    result.error("bad_args", "id and image are required", null)
                } else {
                    s.putImage(id, image)
                    result.success(null)
                }
            }
            "setBackgroundVideo" -> {
                s.setBackgroundVideo(call.argument<String>("path"))
                result.success(null)
            }
            "setBackground" -> {
                s.setBackground(call.argument<Map<*, *>>("image"))
                result.success(null)
            }
            "setWorld" -> {
                s.setWorld(call.arguments as? Map<*, *> ?: emptyMap<String, Any>())
                result.success(null)
            }
            "setTorch" -> {
                s.setTorch(call.argument<Boolean>("on") == true)
                result.success(null)
            }
            "setFlashMode" -> {
                s.setFlashMode(call.argument<String>("mode") ?: "off")
                result.success(null)
            }
            "setZoom" -> {
                s.setZoom((call.argument<Number>("ratio") ?: 1).toFloat())
                result.success(null)
            }
            "takePicture" -> {
                val file = File(context.cacheDir, "oneova_ar_photo_${System.currentTimeMillis()}.jpg")
                s.takePicture(file) { path, err ->
                    if (path != null) result.success(path) else result.error("capture_failed", err, null)
                }
            }
            "startRecording" -> {
                val path = call.argument<String>("path")
                    ?: File(context.cacheDir, "oneova_ar_video_${System.currentTimeMillis()}.mp4").absolutePath
                s.startRecording(File(path), call.argument<Boolean>("audio") != false) { err ->
                    if (err == null) result.success(path) else result.error("record_failed", err, null)
                }
            }
            "stopRecording" -> s.stopRecording { ms ->
                if (ms >= 0) result.success(ms) else result.error("record_failed", "Nothing was recorded", null)
            }
            "stats" -> result.success(s.stats())
            "focusAt" -> s.focusAt(
                (call.argument<Number>("x") ?: 0.5).toFloat(),
                (call.argument<Number>("y") ?: 0.5).toFloat(),
                call.argument<Boolean>("lock") == true,
            ) { ok -> result.success(ok) }
            "unlockFocus" -> {
                s.unlock()
                result.success(null)
            }
            "exposureInfo" -> result.success(s.exposureInfo())
            "setExposure" -> result.success(s.setExposure((call.argument<Number>("ev") ?: 0).toFloat()).toDouble())
            "manualInfo" -> result.success(s.manualInfo())
            "setManual" -> {
                s.setManual(
                    call.argument<Number>("iso")?.toInt(),
                    call.argument<Number>("exposureNs")?.toLong(),
                    call.argument<Number>("awb")?.toInt(),
                    call.argument<Number>("focus")?.toFloat(),
                )
                result.success(null)
            }
            "setGrade" -> {
                try {
                    val look = (call.argument<Map<*, *>>("look"))?.let { com.oneova.camerakit.NativeLookData.fromMap(it) }
                    val m = call.argument<List<Number>>("matrix")?.map { it.toFloat() }?.toFloatArray()
                    s.setGrade(look, m)
                    result.success(null)
                } catch (e: IllegalArgumentException) {
                    result.error("bad_look", e.message, null)
                }
            }
            "setLowLight" -> {
                s.setLowLight(call.argument<Boolean>("on") == true)
                result.success(null)
            }
            "zoomInfo" -> result.success(s.zoomInfo())
            "setDeviceRotation" -> {
                s.setDeviceRotation(call.argument<Int>("rotation") ?: 0)
                result.success(null)
            }
            "micBusy" -> result.success(s.micBusy())
            "thermalStatus" -> result.success(s.thermalStatus())
            "playSound" -> {
                s.playSound(call.argument<String>("kind") ?: "shutter")
                result.success(null)
            }
            "setThrottle" -> {
                s.setThrottle(call.argument<Boolean>("on") == true)
                result.success(null)
            }
            "setSceneMode" -> {
                s.setSceneMode(call.argument<String>("mode") ?: "auto")
                result.success(null)
            }
            "dualSupported" -> result.success(s.dualSupported())
            "setDual" -> s.setDual(call.argument<Boolean>("on") == true, dualLayout(call)) { err ->
                if (err == null) result.success(null) else result.error(err, err, null)
            }
            "setDualLayout" -> {
                s.setDualLayout(dualLayout(call))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun dualLayout(call: MethodCall) = ArGlPipeline.DualLayout(
        mode = if (call.argument<String>("layout") == "split") 1 else 0,
        x = (call.argument<Number>("x") ?: 0.62).toFloat(),
        y = (call.argument<Number>("y") ?: 0.12).toFloat(),
        w = (call.argument<Number>("w") ?: 0.32).toFloat(),
        h = (call.argument<Number>("h") ?: 0.3).toFloat(),
        swap = call.argument<Boolean>("swap") == true,
    )

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        session?.close()
        val front = call.argument<Boolean>("front") == true
        val needs = ArNeeds.fromMap(call.argument<Map<*, *>>("needs"))
        val s = ArCameraSession(
            context, textures, front, needs,
            emit = { event -> sink?.success(event) },
            aspect43 = call.argument<Boolean>("aspect43") == true,
            quality = call.argument<String>("quality") ?: "1080p30",
        )
        session = s
        s.open { size, err ->
            if (session !== s) {
                result.error("closed", "Superseded by another open", null)
            } else if (size == null) {
                s.close()
                session = null
                result.error("open_failed", err, null)
            } else {
                result.success(
                    mapOf(
                        "textureId" to s.textureId,
                        "width" to size.width,
                        "height" to size.height,
                        "mirrored" to front,
                    ),
                )
            }
        }
    }
}
