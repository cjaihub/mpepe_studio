package com.oneova.camerakit

import android.content.Context
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.video.LocalVideoTrack
import com.oneova.camerakit.ar.ArCameraChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.VideoFrame

/** Grades one local flutter_webrtc video track through [GlLookRenderer]. */
internal class TrackLookHook(
    private val track: LocalVideoTrack,
    maxInFlight: Int,
) : LocalVideoTrack.ExternalVideoFrameProcessing {
    val stats = FrameStats()
    private val renderer = GlLookRenderer(maxInFlight, stats)

    fun attach() = track.addProcessor(this)

    fun setLook(request: LookRequest) = renderer.requestLook(request)

    fun detach() {
        // removeProcessor takes the lock held while frames are processed, so
        // no frame is mid-render once it returns.
        track.removeProcessor(this)
        renderer.dispose()
    }

    override fun onFrame(frame: VideoFrame): VideoFrame = renderer.process(frame)
}

class OneovaCameraKitPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var deviceChannel: MethodChannel
    private var capabilityProbe: DeviceCapabilityProbe? = null
    private var thermalBridge: ThermalGovernorBridge? = null
    private val hooks = HashMap<String, TrackLookHook>()
    private var arCamera: ArCameraChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        capabilityProbe = DeviceCapabilityProbe(context)
        thermalBridge = ThermalGovernorBridge(context)

        channel = MethodChannel(binding.binaryMessenger, "oneova_camera_kit/look_processor")
        channel.setMethodCallHandler(this)

        deviceChannel = MethodChannel(binding.binaryMessenger, "oneova_camera_kit/device")
        deviceChannel.setMethodCallHandler { call, result ->
            handleDeviceCall(call, result)
        }

        arCamera = ArCameraChannel(context, binding.binaryMessenger, binding.textureRegistry)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        deviceChannel.setMethodCallHandler(null)
        arCamera?.dispose()
        arCamera = null
        thermalBridge?.closeHintSession()
        capabilityProbe = null
        thermalBridge = null
        synchronized(hooks) {
            hooks.values.forEach { it.detach() }
            hooks.clear()
        }
    }

    private fun handleDeviceCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probeHardwareCapabilities" -> {
                val probe = capabilityProbe
                if (probe != null) {
                    result.success(probe.probe())
                } else {
                    result.error("unavailable", "Capability probe not initialized", null)
                }
            }
            "getThermalHeadroom" -> {
                val forecastSeconds = call.argument<Int>("forecastSeconds") ?: 0
                val bridge = thermalBridge
                if (bridge != null) {
                    result.success(bridge.getThermalHeadroom(forecastSeconds))
                } else {
                    result.success(0.5f)
                }
            }
            "getThermalSnapshot" -> {
                val bridge = thermalBridge
                if (bridge != null) {
                    result.success(bridge.getThermalSnapshot())
                } else {
                    result.success(mapOf(
                        "headroom" to 0.5f,
                        "forecastHeadroom10s" to 0.5f,
                        "thermalLevel" to "nominal",
                        "isPowerSaveMode" to false,
                        "batteryLevel" to 100,
                        "isCharging" to false,
                        "timestamp" to System.currentTimeMillis()
                    ))
                }
            }
            "createHintSession" -> {
                val targetDurationNanos = (call.argument<Number>("targetDurationNanos"))?.toLong() ?: 16_666_666L
                val success = thermalBridge?.createHintSession(targetDurationNanos) ?: false
                result.success(success)
            }
            "reportActualDuration" -> {
                val actualDurationNanos = (call.argument<Number>("actualDurationNanos"))?.toLong() ?: 0L
                val success = thermalBridge?.reportActualDuration(actualDurationNanos) ?: false
                result.success(success)
            }
            "closeHintSession" -> {
                thermalBridge?.closeHintSession()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val trackId = call.argument<String>("trackId")
        if (trackId == null) {
            result.error("bad_args", "trackId is required", null)
            return
        }
        try {
            when (call.method) {
                "attach" -> attach(trackId, call.argument<Int>("maxInFlightFrames") ?: 0, result)
                "setLook" -> {
                    val hook = hook(trackId, result) ?: return
                    val look = call.argument<Map<*, *>>("look")?.let { NativeLookData.fromMap(it) }
                    hook.setLook(LookRequest(look, (call.argument<Int>("crossFadeMs") ?: 0).coerceAtLeast(0)))
                    result.success(null)
                }
                "stats" -> {
                    val hook = hook(trackId, result) ?: return
                    result.success(hook.stats.toMap())
                }
                "detach" -> {
                    synchronized(hooks) { hooks.remove(trackId) }?.detach()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", e.message, null)
        }
    }

    private fun attach(trackId: String, maxInFlight: Int, result: MethodChannel.Result) {
        if (maxInFlight < 1) {
            result.error("bad_args", "maxInFlightFrames must be at least 1", null)
            return
        }
        val track = FlutterWebRTCPlugin.sharedSingleton?.getLocalTrack(trackId) as? LocalVideoTrack
        if (track == null) {
            result.error("track_not_found", "No local video track $trackId", null)
            return
        }
        synchronized(hooks) {
            if (hooks.containsKey(trackId)) {
                result.success(null)
                return
            }
            val hook = TrackLookHook(track, maxInFlight)
            hook.attach()
            hooks[trackId] = hook
        }
        result.success(null)
    }

    private fun hook(trackId: String, result: MethodChannel.Result): TrackLookHook? {
        val hook = synchronized(hooks) { hooks[trackId] }
        if (hook == null) result.error("not_attached", "No look processor on $trackId", null)
        return hook
    }
}
