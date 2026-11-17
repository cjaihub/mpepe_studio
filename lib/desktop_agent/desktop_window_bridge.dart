import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_input_router.dart';

class DesktopDisplayInfo {
  final int index;
  final String name;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool isPrimary;

  const DesktopDisplayInfo({
    required this.index,
    required this.name,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.isPrimary,
  });

  factory DesktopDisplayInfo.fromMap(Map<dynamic, dynamic> map, int fallbackIdx) {
    return DesktopDisplayInfo(
      index: (map['index'] as num?)?.toInt() ?? fallbackIdx,
      name: (map['name'] ?? 'Display ${fallbackIdx + 1}').toString(),
      x: (map['x'] as num?)?.toInt() ?? 0,
      y: (map['y'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 1920,
      height: (map['height'] as num?)?.toInt() ?? 1080,
      isPrimary: map['isPrimary'] == true,
    );
  }
}

class DesktopPermissionsSnapshot {
  final String platform;
  final bool accessibility;
  final bool inputMonitoring;
  final bool screenRecording;
  final bool automation;
  final bool microphone;
  final bool desktopFolder;
  final bool documentsFolder;
  final bool downloadsFolder;
  final bool externalVolumes;
  final bool fullDiskAccess;
  final bool isElevated;
  final List<String> mountedVolumes;
  final List<String> authorizedFolders;
  final List<DesktopDisplayInfo> displays;

  const DesktopPermissionsSnapshot({
    this.platform = 'desktop',
    this.accessibility = false,
    this.inputMonitoring = false,
    this.screenRecording = false,
    this.automation = false,
    this.microphone = false,
    this.desktopFolder = false,
    this.documentsFolder = false,
    this.downloadsFolder = false,
    this.externalVolumes = false,
    this.fullDiskAccess = false,
    this.isElevated = false,
    this.mountedVolumes = const [],
    this.authorizedFolders = const [],
    this.displays = const [],
  });

  factory DesktopPermissionsSnapshot.fromMap(Map<dynamic, dynamic> raw) {
    final rawDisplays = raw['displays'];
    final parsedDisplays = <DesktopDisplayInfo>[];
    if (rawDisplays is List) {
      for (int i = 0; i < rawDisplays.length; i++) {
        final item = rawDisplays[i];
        if (item is Map) {
          parsedDisplays.add(DesktopDisplayInfo.fromMap(item, i));
        }
      }
    }
    List<String> strList(dynamic v) => v is List
        ? v.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const [];

    return DesktopPermissionsSnapshot(
      platform: (raw['platform'] ?? 'desktop').toString(),
      accessibility: raw['accessibility'] == true,
      inputMonitoring: raw['inputMonitoring'] == true,
      screenRecording: raw['screenRecording'] == true,
      automation: raw['automation'] == true,
      microphone: raw['microphone'] == true,
      desktopFolder: raw['desktopFolder'] == true,
      documentsFolder: raw['documentsFolder'] == true,
      downloadsFolder: raw['downloadsFolder'] == true,
      externalVolumes: raw['externalVolumes'] == true,
      fullDiskAccess: raw['fullDiskAccess'] == true,
      isElevated: raw['isElevated'] == true,
      mountedVolumes: strList(raw['mountedVolumes']),
      authorizedFolders: strList(raw['authorizedFolders']),
      displays: parsedDisplays,
    );
  }

  bool get mouseKeyboardReady =>
      platform == 'windows'
          ? accessibility
          : (accessibility && inputMonitoring);

  bool get storageFoldersReady =>
      desktopFolder && documentsFolder && downloadsFolder;

  int get missingCriticalCount {
    int count = 0;
    if (!mouseKeyboardReady) count++;
    if (!screenRecording) count++;
    if (!storageFoldersReady) count++;
    if (platform == 'macos' && !automation) count++;
    return count;
  }
}

/// Cross-platform bridge to the native macOS Menu Bar + Carbon Global Hotkey
/// + LaunchAgent + TCC Permissions AND Windows System Tray + Win32 RegisterHotKey
/// + Registry Startup + Permissions/Display Discovery.
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
  final ValueNotifier<DesktopPermissionsSnapshot> permissions =
      ValueNotifier<DesktopPermissionsSnapshot>(const DesktopPermissionsSnapshot());
  final ValueNotifier<int> selectedDisplayIndex = ValueNotifier<int>(0);

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
    await refreshPermissions();
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

  Future<DesktopPermissionsSnapshot> refreshPermissions() async {
    if (!isDesktop) return permissions.value;
    try {
      final raw = await _channel.invokeMethod<dynamic>('getPermissionsStatus');
      if (raw is Map) {
        final snap = DesktopPermissionsSnapshot.fromMap(raw);
        permissions.value = snap;
        return snap;
      }
    } catch (e) {
      debugPrint('[DesktopWindowBridge] refreshPermissions notice: $e');
    }
    return permissions.value;
  }

  Future<DesktopPermissionsSnapshot> requestPermission(String permission) async {
    if (!isDesktop) return permissions.value;
    try {
      final raw = await _channel.invokeMethod<dynamic>(
        'requestPermission',
        {'permission': permission},
      );
      if (raw is Map) {
        final snap = DesktopPermissionsSnapshot.fromMap(raw);
        permissions.value = snap;
        return snap;
      }
    } catch (e) {
      debugPrint('[DesktopWindowBridge] requestPermission notice: $e');
    }
    return refreshPermissions();
  }

  Future<void> openPermissionSettings(String pane) async {
    if (!isDesktop) return;
    try {
      await _channel.invokeMethod('openPermissionSettings', {'pane': pane});
    } catch (_) {}
  }

  Future<List<String>> authorizeStorageFolder() async {
    if (!isDesktop) return const [];
    try {
      final raw = await _channel.invokeMethod<dynamic>('authorizeStorageFolder');
      await refreshPermissions();
      if (raw is List) {
        return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (e) {
      debugPrint('[DesktopWindowBridge] authorizeStorageFolder notice: $e');
    }
    return permissions.value.authorizedFolders;
  }

  Future<DesktopPermissionsSnapshot> resetStalePermissions() async {
    if (!isDesktop) return permissions.value;
    try {
      final raw = await _channel.invokeMethod<dynamic>('resetStalePermissions');
      if (raw is Map) {
        final snap = DesktopPermissionsSnapshot.fromMap(raw);
        permissions.value = snap;
        return snap;
      }
    } catch (_) {}
    return refreshPermissions();
  }

  void selectDisplay(int index) {
    selectedDisplayIndex.value = index;
    DesktopInputRouter.selectedDisplayIndex = index;
  }
}
