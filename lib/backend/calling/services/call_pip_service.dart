import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android system picture-in-picture for video calls.
///
/// Talks to `MainActivity` over `com.oneova.app/call_pip`: while enabled,
/// leaving the app mid video call shrinks it into a system PiP window
/// (auto-enter on Android 12+, onUserLeaveHint on 8–11).
class CallPipService {
  static const MethodChannel _channel = MethodChannel('com.oneova.app/call_pip');
  static bool? _last;

  static void setAutoEnter(bool enabled) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_last == enabled) return;
    _last = enabled;
    _channel.invokeMethod<void>('setAutoEnter', {'enabled': enabled}).catchError((_) {});
  }
}
