import Flutter
import PushKit
import UIKit
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // VoIP pushes wake the app (even when killed) so CallKit can ring.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - PushKit

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  /// iOS requires every VoIP push to report a CallKit call immediately, or it
  /// stops delivering them. Payload is built by functions/src/calls.ts.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let p = payload.dictionaryPayload
    let id = p["id"] as? String ?? UUID().uuidString
    let nameCaller = p["nameCaller"] as? String ?? "Oneova"
    let handle = p["handle"] as? String ?? "Oneova call"
    let isVideo = (p["isVideo"] as? Bool) ?? ((p["isVideo"] as? String) == "true")

    let data = flutter_callkit_incoming.Data(id: id, nameCaller: nameCaller, handle: handle, type: isVideo ? 1 : 0)
    data.appName = "Oneova"
    data.avatar = p["avatar"] as? String ?? ""
    data.duration = 45000
    data.extra = (p["extra"] as? NSDictionary) ?? [:]
    data.supportsVideo = true
    data.includesCallsInRecents = true
    data.configureAudioSession = true
    data.audioSessionMode = isVideo ? "videoChat" : "voiceChat"
    data.audioSessionActive = true
    data.maximumCallGroups = 1
    data.maximumCallsPerCallGroup = 1
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
      completion()
    }
  }
}
