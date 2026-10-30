import Flutter
import Foundation

extension NativeLookData {
  enum ParseError: Error, CustomStringConvertible {
    case invalid(String)
    var description: String {
      switch self {
      case .invalid(let message): return message
      }
    }
  }

  /// Parses and validates `NativeLook.toMap()`.
  init(map: [String: Any]) throws {
    guard let id = map["id"] as? String else { throw ParseError.invalid("look.id missing") }
    guard let u = map["uniforms"] as? FlutterStandardTypedData, u.type == .float32 else {
      throw ParseError.invalid("look.uniforms must be a Float32List")
    }
    let floats = u.data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    guard floats.count == LookEngineShader.floatCount else {
      throw ParseError.invalid(
        "look.uniforms has \(floats.count) floats, shader expects \(LookEngineShader.floatCount)")
    }
    guard let lut = map["lutAtlas"] as? FlutterStandardTypedData,
      let size = (map["lutSize"] as? NSNumber)?.intValue, size >= 2,
      lut.data.count == size * size * size * 4
    else { throw ParseError.invalid("look.lutAtlas size mismatch") }
    guard let curves = map["curves"] as? FlutterStandardTypedData,
      curves.data.count == Self.curvesWidth * Self.curvesHeight * 4
    else { throw ParseError.invalid("look.curves size mismatch") }
    self.init(id: id, uniforms: floats, lutAtlas: lut.data, lutSize: size, curves: curves.data)
  }
}

/// Grades one local flutter_webrtc video track through [MetalLookRenderer].
final class TrackLookHook {
  let stats: FrameStats
  private let trackId: String
  private let renderer: MetalLookRenderer
  private var token: Any?

  init(trackId: String, renderer: MetalLookRenderer, stats: FrameStats) {
    self.trackId = trackId
    self.renderer = renderer
    self.stats = stats
  }

  /// Main thread. Returns false when the track is not a local camera track.
  func attach() -> Bool {
    let renderer = self.renderer
    token = OneovaWebRTCBridge.addProcessor(toTrack: trackId) { frame in renderer.process(frame) }
    return token != nil
  }

  func setLook(_ request: LookRequest) {
    renderer.requestLook(request)
  }

  /// Main thread.
  func detach() {
    if let token { OneovaWebRTCBridge.removeProcessor(token, fromTrack: trackId) }
    token = nil
  }
}

public class OneovaCameraKitPlugin: NSObject, FlutterPlugin {
  private var hooks: [String: TrackLookHook] = [:]
  private var attaching: Set<String> = []
  private let setupQueue = DispatchQueue(label: "oneova.camerakit.setup", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "oneova_camera_kit/look_processor", binaryMessenger: registrar.messenger())
    let instance = OneovaCameraKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let deviceChannel = FlutterMethodChannel(
      name: "oneova_camera_kit/device", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: deviceChannel)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    hooks.values.forEach { $0.detach() }
    hooks.removeAll()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "probeHardwareCapabilities":
      result(DeviceCapabilityProbe.probe())
      return
    case "getThermalHeadroom":
      let forecastSeconds = (call.arguments as? [String: Any])?["forecastSeconds"] as? Int ?? 0
      result(ThermalGovernorBridge.getThermalHeadroom(forecastSeconds: forecastSeconds))
      return
    case "getThermalSnapshot":
      result(ThermalGovernorBridge.getThermalSnapshot())
      return
    case "createHintSession", "reportActualDuration":
      // iOS manages hint threads automatically; report success
      result(true)
      return
    case "closeHintSession":
      result(nil)
      return
    default:
      break
    }

    // Look processor track methods
    guard let args = call.arguments as? [String: Any], let trackId = args["trackId"] as? String else {
      result(FlutterError(code: "bad_args", message: "trackId is required", details: nil))
      return
    }
    switch call.method {
    case "attach":
      attach(trackId, maxInFlight: (args["maxInFlightFrames"] as? NSNumber)?.intValue ?? 0, result: result)
    case "setLook":
      guard let hook = hook(trackId, result) else { return }
      do {
        let look = try (args["look"] as? [String: Any]).map { try NativeLookData(map: $0) }
        let fade = max(0, (args["crossFadeMs"] as? NSNumber)?.intValue ?? 0)
        hook.setLook(LookRequest(look: look, crossFadeMs: fade))
        result(nil)
      } catch {
        result(FlutterError(code: "bad_args", message: "\(error)", details: nil))
      }
    case "stats":
      guard let hook = hook(trackId, result) else { return }
      result(hook.stats.toMap())
    case "detach":
      hooks.removeValue(forKey: trackId)?.detach()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func attach(_ trackId: String, maxInFlight: Int, result: @escaping FlutterResult) {
    guard maxInFlight >= 1 else {
      result(FlutterError(code: "bad_args", message: "maxInFlightFrames must be at least 1", details: nil))
      return
    }
    if hooks[trackId] != nil || attaching.contains(trackId) {
      result(nil)
      return
    }
    attaching.insert(trackId)
    // Shader compilation takes a moment; keep it off the main thread.
    setupQueue.async {
      let stats = FrameStats()
      let made = Result { try MetalLookRenderer(maxInFlight: maxInFlight, stats: stats) }
      DispatchQueue.main.async {
        self.attaching.remove(trackId)
        switch made {
        case .failure(let error):
          result(FlutterError(code: "gpu_unavailable", message: "\(error)", details: nil))
        case .success(let renderer):
          let hook = TrackLookHook(trackId: trackId, renderer: renderer, stats: stats)
          guard hook.attach() else {
            result(FlutterError(code: "track_not_found", message: "No local camera track \(trackId)", details: nil))
            return
          }
          self.hooks[trackId] = hook
          result(nil)
        }
      }
    }
  }

  private func hook(_ trackId: String, _ result: FlutterResult) -> TrackLookHook? {
    guard let hook = hooks[trackId] else {
      result(FlutterError(code: "not_attached", message: "No look processor on \(trackId)", details: nil))
      return nil
    }
    return hook
  }
}
