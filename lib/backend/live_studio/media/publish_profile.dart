// LIVE STUDIO v2 — publish and subscribe presets (pure, ARCHITECTURE §7).

import 'package:livekit_client/livekit_client.dart';

import '../contracts/studio_contracts.dart';

/// LiveKit track names.
class StudioTrackNames {
  StudioTrackNames._();
  static const String camera = 'cam';
  static const String microphone = 'mic';
  static const String tableScreen = kTableScreenTrack;
}

/// Camera capture + simulcast layers for a publisher.
///
/// WebRTC sends at most 3 simulcast encodings: the two lower layers below
/// plus the capture resolution.
/// - guests / co-hosts: 180p · 360p · 720p;
/// - host on a device that captures 1080p: 180p · 720p · 1080p (wall tiles
///   still get 180p; center / pop-out get 720p or 1080p).
class StudioPublishProfile {
  const StudioPublishProfile({required this.capture, required this.lowerLayers});

  final VideoParameters capture;
  final List<VideoParameters> lowerLayers;

  static const standard = StudioPublishProfile(
    capture: VideoParametersPresets.h720_169,
    lowerLayers: [VideoParametersPresets.h180_169, VideoParametersPresets.h360_169],
  );

  static const hostHd = StudioPublishProfile(
    capture: VideoParametersPresets.h1080_169,
    lowerLayers: [VideoParametersPresets.h180_169, VideoParametersPresets.h720_169],
  );

  /// Profile for [role]. [supports1080] says whether the camera actually
  /// delivered ≥ 1080 lines (checked after opening it).
  static StudioPublishProfile forRole(StudioRole role, {required bool supports1080}) =>
      role == StudioRole.host && supports1080 ? hostHd : standard;

  /// All layer heights, low → high.
  List<int> get layerHeights => [...lowerLayers.map((p) => p.dimensions.height), capture.dimensions.height];

  CameraCaptureOptions get cameraOptions => CameraCaptureOptions(params: capture);

  VideoPublishOptions get publishOptions => VideoPublishOptions(
        name: StudioTrackNames.camera,
        simulcast: true,
        videoSimulcastLayers: lowerLayers,
      );
}

/// Screen share on the table: one 1080p/15 fps layer, plus a 360p fallback.
const VideoPublishOptions kTableScreenPublishOptions = VideoPublishOptions(
  name: StudioTrackNames.tableScreen,
  simulcast: true,
  screenShareSimulcastLayers: [VideoParametersPresets.screenShareH360FPS3],
);

/// In-app capture. iOS whole-device sharing needs a ReplayKit broadcast
/// extension target (not in the project yet); flip `useiOSBroadcastExtension`
/// once it exists.
const ScreenShareCaptureOptions kTableScreenCaptureOptions = ScreenShareCaptureOptions(
  params: VideoParametersPresets.screenShareH1080FPS15,
);

/// What a subscriber asks the SFU for, given the rendered size in pixels.
class StudioSubscriptionPlan {
  const StudioSubscriptionPlan._(this.enabled, this.width, this.height);

  /// 0×0 (off screen / hidden) → paused.
  final bool enabled;
  final int width;
  final int height;

  static const paused = StudioSubscriptionPlan._(false, 0, 0);

  factory StudioSubscriptionPlan.forSize(double width, double height) {
    if (!(width > 0 && height > 0) || width.isNaN || height.isNaN) return paused;
    return StudioSubscriptionPlan._(true, width.ceil(), height.ceil());
  }

  /// The simulcast layer the SFU will pick for these dimensions (for QoS
  /// labels): the smallest layer that covers the rendered height.
  int expectedLayer(List<int> layerHeights) {
    if (!enabled || layerHeights.isEmpty) return 0;
    for (final h in layerHeights) {
      if (h >= height) return h;
    }
    return layerHeights.last;
  }

  @override
  bool operator ==(Object other) =>
      other is StudioSubscriptionPlan && other.enabled == enabled && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(enabled, width, height);
}
