package com.oneova.camerakit

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Range
import android.util.Size
import java.util.Locale

/**
 * Dynamically probes hardware capabilities of the Android device.
 * Enforces NO hard-coded device lists anywhere.
 */
class DeviceCapabilityProbe(private val context: Context) {

    fun probe(): Map<String, Any?> {
        val memoryInfo = probeMemory()
        val cameras = probeCameras()
        val encoders = probeEncoders()
        val gpu = probeGpu()
        val thermal = probeThermalBaseline()

        val totalRamMb = (memoryInfo["totalRamBytes"] as? Long ?: 0L) / (1024 * 1024)
        val has4kEncoder = encoders.any {
            val maxW = it["maxWidth"] as? Int ?: 0
            val maxH = it["maxHeight"] as? Int ?: 0
            (maxW >= 3840 && maxH >= 2160) || (maxW >= 2160 && maxH >= 3840)
        }
        val hasHevc10Bit = encoders.any {
            it["codec"] == "video/hevc" && (it["supports10Bit"] as? Boolean == true)
        }

        val calculatedTier = when {
            totalRamMb >= 7500 && has4kEncoder && hasHevc10Bit -> "high"
            totalRamMb >= 3800 && has4kEncoder -> "medium"
            totalRamMb >= 3500 -> "medium"
            else -> "low"
        }

        val socModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL
        } else {
            Build.HARDWARE
        }

        return mapOf(
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "device" to Build.DEVICE,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "socModel" to socModel,
            "osVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "hardwareTier" to calculatedTier,
            "memory" to memoryInfo,
            "cameras" to cameras,
            "encoders" to encoders,
            "gpu" to gpu,
            "thermal" to thermal
        )
    }

    private fun probeMemory(): Map<String, Any?> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        if (activityManager != null) {
            activityManager.getMemoryInfo(memoryInfo)
            return mapOf(
                "totalRamBytes" to memoryInfo.totalMem,
                "availRamBytes" to memoryInfo.availMem,
                "lowMemory" to memoryInfo.lowMemory,
                "thresholdBytes" to memoryInfo.threshold
            )
        }
        val runtime = Runtime.getRuntime()
        return mapOf(
            "totalRamBytes" to runtime.totalMemory(),
            "availRamBytes" to runtime.freeMemory(),
            "lowMemory" to false,
            "thresholdBytes" to 0L
        )
    }

    private fun probeCameras(): List<Map<String, Any?>> {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return emptyList()

        val results = mutableListOf<Map<String, Any?>>()
        try {
            for (cameraId in cameraManager.cameraIdList) {
                val chars = cameraManager.getCameraCharacteristics(cameraId)
                val facing = when (chars.get(CameraCharacteristics.LENS_FACING)) {
                    CameraMetadata.LENS_FACING_FRONT -> "front"
                    CameraMetadata.LENS_FACING_BACK -> "back"
                    CameraMetadata.LENS_FACING_EXTERNAL -> "external"
                    else -> "unknown"
                }

                val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val resolutions = mutableListOf<Map<String, Int>>()
                var maxFps = 30

                if (map != null) {
                    val outputSizes: Array<Size>? = map.getOutputSizes(android.graphics.ImageFormat.YUV_420_888)
                        ?: map.getOutputSizes(android.graphics.SurfaceTexture::class.java)

                    outputSizes?.forEach { size ->
                        resolutions.add(mapOf("width" to size.width, "height" to size.height))
                    }
                }

                val fpsRanges: Array<Range<Int>>? = chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                fpsRanges?.forEach { range ->
                    if (range.upper > maxFps) {
                        maxFps = range.upper
                    }
                }

                val capabilities = chars.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: intArrayOf()
                val is10BitSupported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    capabilities.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_DYNAMIC_RANGE_TEN_BIT)
                } else {
                    false
                }

                val isHdrSupported = capabilities.contains(CameraMetadata.REQUEST_AVAILABLE_CAPABILITIES_BURST_CAPTURE) || is10BitSupported

                results.add(
                    mapOf(
                        "id" to cameraId,
                        "facing" to facing,
                        "resolutions" to resolutions,
                        "maxFps" to maxFps,
                        "is10BitSupported" to is10BitSupported,
                        "isHdrSupported" to isHdrSupported
                    )
                )
            }
        } catch (_: Exception) {}

        return results
    }

    private fun probeEncoders(): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val mediaCodecList = MediaCodecList(MediaCodecList.ALL_CODECS)
        val targetCodecs = listOf(
            MediaFormat.MIMETYPE_VIDEO_AVC,
            MediaFormat.MIMETYPE_VIDEO_HEVC,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) MediaFormat.MIMETYPE_VIDEO_AV1 else "video/av01",
            MediaFormat.MIMETYPE_VIDEO_VP9
        )

        for (codecInfo in mediaCodecList.codecInfos) {
            if (!codecInfo.isEncoder) continue

            val supportedTypes = codecInfo.supportedTypes
            for (type in targetCodecs) {
                if (supportedTypes.any { it.equals(type, ignoreCase = true) }) {
                    try {
                        val caps = codecInfo.getCapabilitiesForType(type)
                        val videoCaps = caps.videoCapabilities

                        val isHardware = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            codecInfo.isHardwareAccelerated
                        } else {
                            val name = codecInfo.name.lowercase(Locale.ROOT)
                            !name.startsWith("omx.google.") && !name.startsWith("c2.android.")
                        }

                        val maxWidth = videoCaps?.supportedWidths?.upper ?: 1920
                        val maxHeight = videoCaps?.supportedHeights?.upper ?: 1080
                        val maxBitrate = videoCaps?.bitrateRange?.upper ?: 20_000_000
                        val maxFrameRate = videoCaps?.supportedFrameRates?.upper?.toInt() ?: 60

                        val profileLevels = mutableListOf<Map<String, Int>>()
                        var supports10Bit = false
                        caps.profileLevels?.forEach { pl ->
                            profileLevels.add(mapOf("profile" to pl.profile, "level" to pl.level))
                            if (type == MediaFormat.MIMETYPE_VIDEO_HEVC &&
                                (pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10 ||
                                 pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10 ||
                                 pl.profile == MediaCodecInfo.CodecProfileLevel.HEVCProfileMain10HDR10Plus)) {
                                supports10Bit = true
                            }
                        }

                        results.add(
                            mapOf(
                                "name" to codecInfo.name,
                                "codec" to type,
                                "isHardwareAccelerated" to isHardware,
                                "maxWidth" to maxWidth,
                                "maxHeight" to maxHeight,
                                "maxBitrateBps" to maxBitrate,
                                "maxFps" to maxFrameRate,
                                "supports10Bit" to supports10Bit,
                                "profileLevels" to profileLevels
                            )
                        )
                    } catch (_: Exception) {}
                }
            }
        }
        return results
    }

    private fun probeGpu(): Map<String, Any?> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val configInfo = activityManager?.deviceConfigurationInfo
        val glEsVersion = configInfo?.glEsVersion ?: "3.0"
        val reqGlEsVersion = configInfo?.reqGlEsVersion ?: 0x00030000

        val hasVulkan = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL)
        } else {
            false
        }

        return mapOf(
            "glEsVersion" to glEsVersion,
            "reqGlEsVersion" to reqGlEsVersion,
            "hasVulkan" to hasVulkan,
            "hasUnifiedMemory" to true
        )
    }

    private fun probeThermalBaseline(): Map<String, Any?> {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val isPowerSaveMode = powerManager?.isPowerSaveMode ?: false

        val thermalHeadroom = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && powerManager != null) {
            try {
                powerManager.getThermalHeadroom(0)
            } catch (_: Exception) {
                0.5f
            }
        } else {
            0.5f
        }

        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
        val batteryLevel = batteryManager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
        val isCharging = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && batteryManager != null) {
            batteryManager.isCharging
        } else {
            false
        }

        return mapOf(
            "thermalHeadroom" to thermalHeadroom,
            "isPowerSaveMode" to isPowerSaveMode,
            "batteryLevel" to batteryLevel,
            "isCharging" to isCharging
        )
    }
}
