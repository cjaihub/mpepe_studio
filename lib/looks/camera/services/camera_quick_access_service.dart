import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/camera_smart_lock_state.dart';

/// Configuration parsed from a quick access launch (QS Tile, App Shortcut, Lock Screen, or App Intent).
@immutable
class QuickAccessCameraLaunch {
  final CaptureMode initialMode;
  final String? initialLookId;
  final bool autoRecord;
  final bool selfie;
  final Map<String, String> queryParameters;

  const QuickAccessCameraLaunch({
    this.initialMode = CaptureMode.video,
    this.initialLookId,
    this.autoRecord = false,
    this.selfie = false,
    this.queryParameters = const {},
  });

  /// Factory constructor parsing deep-link URI or query map.
  factory QuickAccessCameraLaunch.fromUri(Uri uri) {
    final params = uri.queryParameters;
    final modeStr = (params['mode'] ?? uri.pathSegments.lastOrNull ?? 'video').toLowerCase();

    CaptureMode mode;
    switch (modeStr) {
      case 'photo':
        mode = CaptureMode.photo;
        break;
      case 'slowmo':
      case 'slow_motion':
        mode = CaptureMode.slowMotion;
        break;
      case 'timelapse':
      case 'fast_motion':
        mode = CaptureMode.fastMotion;
        break;
      case 'multisnap':
      case 'multi_snap':
        mode = CaptureMode.multiSnap;
        break;
      case 'dual':
      case 'dual_camera':
        mode = CaptureMode.dualCamera;
        break;
      case 'video':
      default:
        mode = CaptureMode.video;
        break;
    }

    final lookId = params['look'] ?? params['lookId'];
    final autoRecord = params['autoRecord'] == 'true' || params['record'] == '1';
    final selfie = params['camera'] == 'front' || params['selfie'] == 'true';

    return QuickAccessCameraLaunch(
      initialMode: mode,
      initialLookId: lookId,
      autoRecord: autoRecord,
      selfie: selfie,
      queryParameters: params,
    );
  }

  @override
  String toString() =>
      'QuickAccessCameraLaunch(mode: $initialMode, look: $initialLookId, autoRecord: $autoRecord, selfie: $selfie)';
}

/// Service managing OS integration for instant camera capture shortcuts,
/// Android Quick Settings Tile, iOS Control Center Controls, and App Intents.
class CameraQuickAccessService {
  static const MethodChannel _channel = MethodChannel('com.oneova.app/quick_camera');

  final StreamController<QuickAccessCameraLaunch> _launchController =
      StreamController<QuickAccessCameraLaunch>.broadcast();

  Stream<QuickAccessCameraLaunch> get onQuickLaunch => _launchController.stream;

  CameraQuickAccessService() {
    _initPlatformListener();
  }

  void _initPlatformListener() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onLaunchFromTile':
        case 'onLaunchFromAppIntent':
        case 'onLaunchFromShortcut':
          final args = call.arguments;
          if (args is Map) {
            final stringMap = args.map((k, v) => MapEntry(k.toString(), v.toString()));
            final dummyUri = Uri(path: 'camera', queryParameters: stringMap);
            _launchController.add(QuickAccessCameraLaunch.fromUri(dummyUri));
          }
          break;
        default:
          break;
      }
    });
  }

  /// Triggers update of Android Quick Settings Tile state (e.g., active recording indicator).
  Future<void> updateTileState({required bool isRecording}) async {
    try {
      await _channel.invokeMethod('updateTileState', {'isRecording': isRecording});
    } on PlatformException catch (e) {
      debugPrint('[CameraQuickAccessService] Platform tile update skipped: ${e.message}');
    } on MissingPluginException {
      // Graceful fallback for non-native / test execution
    }
  }

  /// Emits a mock or deep-link launch directly in-app.
  void dispatchLaunch(QuickAccessCameraLaunch launch) {
    _launchController.add(launch);
  }

  void dispose() {
    _launchController.close();
  }
}

final cameraQuickAccessServiceProvider = Provider<CameraQuickAccessService>((ref) {
  final service = CameraQuickAccessService();
  ref.onDispose(() => service.dispose());
  return service;
});
