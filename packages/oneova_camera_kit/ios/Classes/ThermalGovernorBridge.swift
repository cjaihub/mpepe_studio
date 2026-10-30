import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// iOS Thermal Governor Bridge.
/// Uses ProcessInfo.processInfo.thermalState, Low Power Mode, and battery charging state.
final class ThermalGovernorBridge {

  static func getThermalHeadroom(forecastSeconds: Int) -> Float {
    let state = ProcessInfo.processInfo.thermalState
    switch state {
    case .nominal: return 0.2
    case .fair: return 0.6
    case .serious: return 0.95
    case .critical: return 1.3
    @unknown default: return 0.3
    }
  }

  static func getThermalSnapshot() -> [String: Any] {
    let state = ProcessInfo.processInfo.thermalState
    let thermalLevel: String
    let headroom: Float
    switch state {
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

    let isPowerSave = ProcessInfo.processInfo.isLowPowerModeEnabled
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
      "headroom": headroom,
      "forecastHeadroom10s": headroom,
      "thermalLevel": thermalLevel,
      "isPowerSaveMode": isPowerSave,
      "batteryLevel": batteryLevel,
      "isCharging": isCharging,
      "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
    ]
  }
}
