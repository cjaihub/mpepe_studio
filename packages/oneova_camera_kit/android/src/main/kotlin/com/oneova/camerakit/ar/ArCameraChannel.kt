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
            else -> result.notImplemented()
        }
    }

    private fun open(call: MethodCall, result: MethodChannel.Result) {
        session?.close()
        val front = call.argument<Boolean>("front") == true
        val needs = ArNeeds.fromMap(call.argument<Map<*, *>>("needs"))
        val s = ArCameraSession(context, textures, front, needs) { event -> sink?.success(event) }
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
