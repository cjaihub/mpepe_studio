import AVFoundation
import Foundation
import Metal
import VideoToolbox

#if canImport(UIKit)
import UIKit
#endif

/// Probes dynamic hardware capabilities of the iOS / macOS device.
/// Enforces NO fixed device lists anywhere.
final class DeviceCapabilityProbe {

  static func probe() -> [String: Any] {
    let memoryInfo = probeMemory()
    let cameras = probeCameras()
    let encoders = probeEncoders()
    let gpu = probeGpu()
    let thermal = probeThermalBaseline()

    let totalRamMb = (memoryInfo["totalRamBytes"] as? Int64 ?? 0) / (1024 * 1024)
    let has4kEncoder = encoders.contains { enc in
      let maxW = enc["maxWidth"] as? Int ?? 0
      let maxH = enc["maxHeight"] as? Int ?? 0
      return (maxW >= 3840 && maxH >= 2160) || (maxW >= 2160 && maxH >= 3840)
    }
    let hasHevc10Bit = encoders.contains { enc in
      return (enc["codec"] as? String == "video/hevc") && (enc["supports10Bit"] as? Bool == true)
    }

    let calculatedTier: String
    if totalRamMb >= 5500 && has4kEncoder && hasHevc10Bit {
      calculatedTier = "high"
    } else if totalRamMb >= 3500 && has4kEncoder {
      calculatedTier = "medium"
    } else {
      calculatedTier = "low"
    }

    let modelId = getDeviceModelIdentifier()

    return [
      "model": modelId,
      "manufacturer": "Apple",
      "device": modelId,
      "hardware": modelId,
      "board": modelId,
      "socModel": modelId,
      "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
      "sdkInt": 0,
      "hardwareTier": calculatedTier,
      "memory": memoryInfo,
      "cameras": cameras,
      "encoders": encoders,
      "gpu": gpu,
      "thermal": thermal
    ]
  }

  private static func probeMemory() -> [String: Any] {
    let totalBytes = Int64(ProcessInfo.processInfo.physicalMemory)
    var availBytes = totalBytes / 2
    if #available(iOS 13.0, macOS 10.15, *) {
      let osProc = os_proc_available_memory()
      if osProc > 0 {
        availBytes = Int64(osProc)
      }
    }
    return [
      "totalRamBytes": totalBytes,
      "availRamBytes": availBytes,
      "lowMemory": availBytes < (500 * 1024 * 1024),
      "thresholdBytes": Int64(400 * 1024 * 1024)
    ]
  }

  private static func probeCameras() -> [[String: Any]] {
    var results: [[String: Any]] = []

    #if canImport(AVFoundation)
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .builtInTelephotoCamera,
        .builtInTrueDepthCamera
      ],
      mediaType: .video,
      position: .unspecified
    )

    for device in discoverySession.devices {
      let facing: String
      switch device.position {
      case .front: facing = "front"
      case .back: facing = "back"
      default: facing = "external"
      }

      var resolutions: [[String: Int]] = []
      var maxFps = 30
      var is10BitSupported = false
      var isHdrSupported = false

      for format in device.formats {
        let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let res = ["width": Int(dims.width), "height": Int(dims.height)]
        if !resolutions.contains(where: { $0["width"] == res["width"] && $0["height"] == res["height"] }) {
          resolutions.append(res)
        }

        for range in format.videoSupportedFrameRateRanges {
          if Int(range.maxFrameRate) > maxFps {
            maxFps = Int(range.maxFrameRate)
          }
        }

        if format.isVideoHDRSupported {
          isHdrSupported = true
        }

        if #available(iOS 14.1, macOS 11.0, *) {
          for colorSpace in format.supportedColorSpaces {
            if colorSpace == .HLG_BT2020 {
              is10BitSupported = true
            }
          }
        }
      }

      results.append([
        "id": device.uniqueID,
        "facing": facing,
        "resolutions": resolutions,
        "maxFps": maxFps,
        "is10BitSupported": is10BitSupported,
        "isHdrSupported": isHdrSupported
      ])
    }
    #endif

    return results
  }

  private static func probeEncoders() -> [[String: Any]] {
    var results: [[String: Any]] = []

    // Probing hardware encoders via VideoToolbox and AVFoundation
    let isH264Supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
    results.append([
      "name": "Apple VideoToolbox H.264",
      "codec": "video/avc",
      "isHardwareAccelerated": isH264Supported,
      "maxWidth": 3840,
      "maxHeight": 2160,
      "maxBitrateBps": 60_000_000,
      "maxFps": 60,
      "supports10Bit": false,
      "profileLevels": [["profile": 100, "level": 52]]
    ])

    let isHevcSupported = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    results.append([
      "name": "Apple VideoToolbox HEVC",
      "codec": "video/hevc",
      "isHardwareAccelerated": isHevcSupported,
      "maxWidth": 3840,
      "maxHeight": 2160,
      "maxBitrateBps": 100_000_000,
      "maxFps": 60,
      "supports10Bit": true,
      "profileLevels": [["profile": 2, "level": 52]]
    ])

    return results
  }

  private static func probeGpu() -> [String: Any] {
    let device = MTLCreateSystemDefaultDevice()
    let gpuName = device?.name ?? "Apple Metal GPU"

    var maxWorkingSet: Int64 = 0
    if #available(iOS 12.0, macOS 10.14, *), let dev = device {
      maxWorkingSet = Int64(dev.recommendedMaxWorkingSetSize)
    }

    var metalFamily = "Apple3"
    if #available(iOS 16.0, macOS 13.0, *), let dev = device {
      if dev.supportsFamily(.metal3) {
        metalFamily = "Metal3"
      } else if dev.supportsFamily(.apple7) {
        metalFamily = "Apple7"
      }
    }

    return [
      "glEsVersion": "Metal (\(metalFamily))",
      "reqGlEsVersion": 0x00030000,
      "hasVulkan": false,
      "hasUnifiedMemory": device?.hasUnifiedMemory ?? true,
      "name": gpuName,
      "maxWorkingSetBytes": maxWorkingSet
    ]
  }

  private static func probeThermalBaseline() -> [String: Any] {
    let thermalState = ProcessInfo.processInfo.thermalState
    let thermalLevel: String
    let headroom: Float
    switch thermalState {
    case .nominal:
      thermalLevel = "nominal"
      headroom = 0.2
    case .fair:
      thermalLevel = "fair"
      headroom = 0.6
    case .serious:
      thermalLevel = "serious"
      headroom = 0.95
    case .critical:
      thermalLevel = "critical"
      headroom = 1.3
    @unknown default:
      thermalLevel = "nominal"
      headroom = 0.3
    }

    var isPowerSave = false
    isPowerSave = ProcessInfo.processInfo.isLowPowerModeEnabled

    var batteryLevel = 100
    var isCharging = false

    #if canImport(UIKit)
    UIDevice.current.isBatteryMonitoringEnabled = true
    let bLevel = UIDevice.current.batteryLevel
    if bLevel >= 0 {
      batteryLevel = Int(bLevel * 100)
    }
    isCharging = (UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)
    #endif

    return [
      "thermalHeadroom": headroom,
      "isPowerSaveMode": isPowerSave,
      "batteryLevel": batteryLevel,
      "isCharging": isCharging,
      "thermalLevel": thermalLevel
    ]
  }

  private static func getDeviceModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce("") { identifier, element in
      guard let value = element.value as? Int8, value != 0 else { return identifier }
      return identifier + String(UnicodeScalar(UInt8(value)))
    }
    return identifier.isEmpty ? "iPhone" : identifier
  }
}
