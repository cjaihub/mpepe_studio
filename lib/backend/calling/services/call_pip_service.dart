import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only call helpers in `MainActivity` over `com.oneova.app/call_pip`:
/// * system picture-in-picture for video calls (auto-enter on Android 12+,
///   onUserLeaveHint on 8–11) and a [inPip] flag the UI can follow;
/// * the ringback tone the caller hears while the other phone rings;
/// * the proximity wake lock that turns the screen off at the ear.
class CallPipService {
  static const MethodChannel _channel = MethodChannel('com.oneova.app/call_pip');
  static bool? _last;
  static bool? _lastProximity;
  static bool? _lastRingback;
  static bool _listening = false;

  /// True while the activity is in system PiP.
  static final ValueNotifier<bool> inPip = ValueNotifier(false);

  static bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        inPip.value = (call.arguments as Map?)?['inPip'] == true;
      }
    });
  }

  static void setAutoEnter(bool enabled) {
    if (!_android) return;
    _listen();
    if (_last == enabled) return;
    _last = enabled;
    _channel.invokeMethod<void>('setAutoEnter', {'enabled': enabled}).catchError((_) {});
  }

  static void setProximity(bool enabled) {
    if (!_android || _lastProximity == enabled) return;
    _lastProximity = enabled;
    _channel.invokeMethod<void>('setProximity', {'enabled': enabled}).catchError((_) {});
  }

  static void setRingback(bool enabled) {
    if (!_android || _lastRingback == enabled) return;
    _lastRingback = enabled;
    _channel.invokeMethod<void>('ringback', {'enabled': enabled}).catchError((_) {});
  }
}
