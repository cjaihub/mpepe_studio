import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';

/// How Ova is summoned. Stored in `user_settings/{uid}.ovaTriggers` and
/// mirrored to Android (`OvaTriggerConfig.kt`) so the system-wide triggers
/// work while the app is closed.
class OvaTriggerSettings {
  static const category = 'ovaTriggers';

  static const shortcutOff = 'off';
  static const shortcutDoubleVolumeDown = 'double_volume_down';
  static const shortcutVolumeUpDown = 'volume_up_down';

  /// Draw "O": in the app anywhere, and from the edge Ova handle over other
  /// apps, the home screen and the lock screen.
  final bool drawO;

  /// Hardware button shortcut: [shortcutOff], [shortcutDoubleVolumeDown] or
  /// [shortcutVolumeUpDown].
  final String buttonShortcut;

  /// Allow triggers on the lock screen. Unlocking is always required before
  /// Ova shows anything.
  final bool lockScreen;

  /// Open Ova straight into voice mode.
  final bool voiceMode;

  const OvaTriggerSettings({
    this.drawO = true,
    this.buttonShortcut = shortcutOff,
    this.lockScreen = true,
    this.voiceMode = false,
  });

  factory OvaTriggerSettings.fromMap(Map<String, dynamic> m) {
    final shortcut = m['buttonShortcut'];
    return OvaTriggerSettings(
      drawO: m['drawO'] as bool? ?? true,
      buttonShortcut: shortcut is String &&
              const [shortcutOff, shortcutDoubleVolumeDown, shortcutVolumeUpDown].contains(shortcut)
          ? shortcut
          : shortcutOff,
      lockScreen: m['lockScreen'] as bool? ?? true,
      voiceMode: m['voiceMode'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'drawO': drawO,
        'buttonShortcut': buttonShortcut,
        'lockScreen': lockScreen,
        'voiceMode': voiceMode,
      };

  @override
  bool operator ==(Object other) =>
      other is OvaTriggerSettings &&
      other.drawO == drawO &&
      other.buttonShortcut == buttonShortcut &&
      other.lockScreen == lockScreen &&
      other.voiceMode == voiceMode;

  @override
  int get hashCode => Object.hash(drawO, buttonShortcut, lockScreen, voiceMode);
}

/// The signed-in user's Ova trigger settings (defaults until loaded).
final ovaTriggerSettingsProvider = Provider<OvaTriggerSettings>((ref) {
  final settings = ref.watch(settingsProvider).value ?? const <String, dynamic>{};
  final raw = settings[OvaTriggerSettings.category];
  return OvaTriggerSettings.fromMap(raw is Map ? Map<String, dynamic>.from(raw) : const {});
});
