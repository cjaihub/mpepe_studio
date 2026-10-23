import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

final ovaDeviceControlProvider = Provider<OvaDeviceControl>((ref) => OvaDeviceControl());

/// Result of a device-control command.
class OvaControlResult {
  final bool ok;
  final String message;
  const OvaControlResult(this.ok, this.message);
}

/// System-wide device control through the native Ova AccessibilityService.
/// Sensitive actions (typing, tapping, locking) are gated behind biometrics.
class OvaDeviceControl {
  static const MethodChannel _channel = MethodChannel('com.oneova.app/ova_assistant');
  final LocalAuthentication _auth = LocalAuthentication();

  bool get _supported => !kIsWeb && Platform.isAndroid;

  Future<bool> isEnabled() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    if (!_supported) return;
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  /// Fingerprint / PIN gate. Returns true when the owner is verified.
  Future<bool> verifyOwner({String reason = 'Confirm it is you to let Ova control your device'}) async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return await _auth.authenticate(localizedReason: reason);
    } catch (e) {
      debugPrint('[OvaDeviceControl] biometric error: $e');
      return false;
    }
  }

  Future<dynamic> _call(String action, [Map<String, dynamic> args = const {}]) {
    return _channel.invokeMethod('deviceControl', {'action': action, ...args});
  }

  Future<String> readScreen() async => (await _call('readScreen')) as String? ?? '';

  /// Taps the first clickable element whose text or label matches [label].
  /// The caller has already asked the user to confirm.
  Future<bool> tapText(String label) async => (await _call('clickText', {'text': label})) == true;

  /// Types into the focused field of the app in front.
  Future<bool> typeIntoFocused(String text) async => (await _call('typeText', {'text': text})) == true;

  Future<String> foregroundPackage() async => (await _call('foregroundPackage')) as String? ?? '';

  /// Shows a chat bubble that fades at the top of whatever app is open.
  Future<void> showBubble(String text, {bool isUser = false}) async {
    if (!await isEnabled()) return;
    await _call('bubble', {'text': text, 'isUser': isUser});
  }

  /// Executes a natural-language style device command. Returns null if the
  /// command is not a device-control command so callers can fall through to the AI brain.
  Future<OvaControlResult?> execute(String prompt) async {
    final p = prompt.toLowerCase().trim();
    final intent = _parse(p, prompt.trim());
    if (intent == null) return null;

    if (!await isEnabled()) {
      return const OvaControlResult(
        false,
        'Device control is off. Open Ova Setup and enable "Oneova Ova" in Accessibility settings.',
      );
    }

    if (intent.sensitive && !await verifyOwner()) {
      return const OvaControlResult(false, 'Verification failed. I did not run that action.');
    }

    try {
      final dynamic res = await _call(intent.action, intent.args);
      final ok = res == true;
      return OvaControlResult(ok, ok ? intent.success : 'I could not do that on this screen.');
    } on PlatformException catch (e) {
      return OvaControlResult(false, e.message ?? 'Device control failed.');
    }
  }

  _Intent? _parse(String p, String original) {
    if (RegExp(r'^(go )?back$').hasMatch(p)) {
      return _Intent('global', {'name': 'back'}, 'Went back.');
    }
    if (RegExp(r'^(go )?home$|go to (the )?home screen').hasMatch(p)) {
      return _Intent('global', {'name': 'home'}, 'Going home.');
    }
    if (p.contains('recent apps') || p == 'recents') {
      return _Intent('global', {'name': 'recents'}, 'Showing recent apps.');
    }
    if (p.contains('notifications') && (p.startsWith('open') || p.startsWith('show'))) {
      return _Intent('global', {'name': 'notifications'}, 'Opened notifications.');
    }
    if (p.contains('quick settings')) {
      return _Intent('global', {'name': 'quick_settings'}, 'Opened quick settings.');
    }
    if (p.contains('take a screenshot') || p == 'screenshot') {
      return _Intent('global', {'name': 'screenshot'}, 'Screenshot taken.');
    }
    if (p.contains('lock the phone') || p.contains('lock screen')) {
      return _Intent('global', {'name': 'lock'}, 'Locked.', sensitive: true);
    }
    if (p.startsWith('scroll down')) {
      return _Intent('scroll', {'forward': true}, 'Scrolled down.');
    }
    if (p.startsWith('scroll up')) {
      return _Intent('scroll', {'forward': false}, 'Scrolled up.');
    }
    final tap = RegExp(r'^(tap|click|press) (on )?(.+)$').firstMatch(p);
    if (tap != null) {
      return _Intent('clickText', {'text': tap.group(3)!}, 'Tapped "${tap.group(3)}".', sensitive: true);
    }
    final type = RegExp(r'^type (.+)$', caseSensitive: false).firstMatch(original);
    if (type != null) {
      return _Intent('typeText', {'text': type.group(1)!}, 'Typed it in.', sensitive: true);
    }
    return null;
  }
}

class _Intent {
  final String action;
  final Map<String, dynamic> args;
  final String success;
  final bool sensitive;
  _Intent(this.action, this.args, this.success, {this.sensitive = false});
}
