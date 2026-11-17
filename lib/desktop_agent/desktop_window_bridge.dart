import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-platform bridge to the native macOS Menu Bar + Carbon Global Hotkey
/// + LaunchAgent AND Windows System Tray + Win32 RegisterHotKey + Registry Startup.
class DesktopWindowBridge {
  DesktopWindowBridge._();
  static final DesktopWindowBridge instance = DesktopWindowBridge._();

  static const MethodChannel _channel = MethodChannel('com.oneova.app/desktop_window');

  final ValueNotifier<bool> isHudMode = ValueNotifier<bool>(false);
  final ValueNotifier<bool> startupEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> hotkeyLabel = ValueNotifier<String>(
    !kIsWeb && Platform.isWindows ? 'Alt+Space' : '⌥Space',
  );
  final ValueNotifier<int> summonTick = ValueNotifier<int>(0);

  bool _initialized = false;

  static bool get isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  Future<void> init() async {
    if (_initialized || !isDesktop) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWindowEvent' && call.arguments is Map) {
        final map = Map<String, dynamic>.from(call.arguments as Map);
        if (map.containsKey('hud')) {
          isHudMode.value = map['hud'] == true;
        }
        if (map['event'] == 'summon') {
          summonTick.value++;
        }
      }
    });
    await refreshState();
  }

  Future<void> refreshState() async {
    if (!isDesktop) return;
    try {
      final raw = await _channel.invokeMethod<dynamic>('getState');
      if (raw is Map) {
        isHudMode.value = raw['hud'] == true;
        startupEnabled.value = raw['startup'] == true;
        final hk = (raw['hotkey'] ?? '').toString();
        if (hk.isNotEmpty) hotkeyLabel.value = hk;
      }
    } catch (e) {
      debugPrint('[DesktopWindowBridge] refreshState notice: $e');
    }
  }

  Future<bool> setHudMode(bool hud) async {
    if (!isDesktop) return false;
    try {
      await _channel.invokeMethod('setHudMode', {'hud': hud});
      isHudMode.value = hud;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> toggleHud() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod('toggleHud');
    } catch (_) {}
  }

  Future<void> showStudio() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod('showStudio');
      isHudMode.value = false;
    } catch (_) {}
  }

  Future<void> hideToTray() async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod('hideToTray');
    } catch (_) {}
  }

  Future<bool> setStartupEnabled(bool enabled) async {
    if (!isDesktop) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setStartupEnabled', {
        'enabled': enabled,
      });
      startupEnabled.value = ok == true ? enabled : await getStartupEnabled();
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> getStartupEnabled() async {
    if (!isDesktop) return false;
    try {
      final on = await _channel.invokeMethod<bool>('getStartupEnabled') ?? false;
      startupEnabled.value = on;
      return on;
    } catch (_) {
      return false;
    }
  }
}
