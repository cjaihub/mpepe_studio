import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user has allowed Ova to use. Stored on this phone only.
/// An ability needs BOTH the opt-in here and the OS permission.
class OvaAbilities {
  final bool bubble;
  final bool suggestions;
  final bool readNotifications;
  final bool readSms;
  final bool deviceState;
  final bool screenControl;
  final bool finishAlerts;

  const OvaAbilities({
    // Off by default: the floating bubble only shows if the user turns it
    // on in Ova > Abilities. Ova stays reachable from chat, AI Lab and gestures.
    this.bubble = false,
    this.suggestions = true,
    this.readNotifications = false,
    this.readSms = false,
    this.deviceState = true,
    this.screenControl = false,
    this.finishAlerts = true,
  });

  OvaAbilities copyWith({
    bool? bubble,
    bool? suggestions,
    bool? readNotifications,
    bool? readSms,
    bool? deviceState,
    bool? screenControl,
    bool? finishAlerts,
  }) =>
      OvaAbilities(
        bubble: bubble ?? this.bubble,
        suggestions: suggestions ?? this.suggestions,
        readNotifications: readNotifications ?? this.readNotifications,
        readSms: readSms ?? this.readSms,
        deviceState: deviceState ?? this.deviceState,
        screenControl: screenControl ?? this.screenControl,
        finishAlerts: finishAlerts ?? this.finishAlerts,
      );
}

final ovaAbilitiesProvider = NotifierProvider<OvaAbilitiesNotifier, OvaAbilities>(OvaAbilitiesNotifier.new);

class OvaAbilitiesNotifier extends Notifier<OvaAbilities> {
  static const _p = 'ova_ability_';

  @override
  OvaAbilities build() {
    _load();
    return const OvaAbilities();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    const d = OvaAbilities();
    state = OvaAbilities(
      bubble: sp.getBool('${_p}bubble_v2') ?? d.bubble,
      suggestions: sp.getBool('${_p}suggestions') ?? d.suggestions,
      readNotifications: sp.getBool('${_p}notifications') ?? d.readNotifications,
      readSms: sp.getBool('${_p}sms') ?? d.readSms,
      deviceState: sp.getBool('${_p}device') ?? d.deviceState,
      screenControl: sp.getBool('${_p}screen') ?? d.screenControl,
      finishAlerts: sp.getBool('${_p}alerts') ?? d.finishAlerts,
    );
  }

  Future<void> _save(String key, bool v) async => (await SharedPreferences.getInstance()).setBool('$_p$key', v);

  void setBubble(bool v) { state = state.copyWith(bubble: v); _save('bubble_v2', v); }
  void setSuggestions(bool v) { state = state.copyWith(suggestions: v); _save('suggestions', v); }
  void setReadNotifications(bool v) { state = state.copyWith(readNotifications: v); _save('notifications', v); }
  void setReadSms(bool v) { state = state.copyWith(readSms: v); _save('sms', v); }
  void setDeviceState(bool v) { state = state.copyWith(deviceState: v); _save('device', v); }
  void setScreenControl(bool v) { state = state.copyWith(screenControl: v); _save('screen', v); }
  void setFinishAlerts(bool v) { state = state.copyWith(finishAlerts: v); _save('alerts', v); }
}
