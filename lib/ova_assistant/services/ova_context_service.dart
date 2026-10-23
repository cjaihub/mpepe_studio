import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/ova_context_model.dart';
import 'ova_native_service.dart';

final ovaNativeServiceProvider = Provider<OvaNativeService>((ref) {
  return OvaNativeService();
});

final ovaContextProvider = NotifierProvider<OvaContextNotifier, PhoneContextState>(OvaContextNotifier.new);

class OvaContextNotifier extends Notifier<PhoneContextState> {
  final OvaNativeService? _customNative;

  OvaContextNotifier([this._customNative]);

  OvaNativeService get _native => _customNative ?? ref.read(ovaNativeServiceProvider);

  @override
  PhoneContextState build() {
    // Refresh context asynchronously after initial state build
    Future.microtask(() => refresh());
    return const PhoneContextState();
  }

  Future<void> refresh() async {
    final info = await _native.getDeviceInfo();
    // The native channel only exists on Android; read the battery directly elsewhere.
    try {
      final battery = Battery();
      info['batteryLevel'] = (await battery.batteryLevel) / 100.0;
      final bs = await battery.batteryState;
      info['isCharging'] = bs == BatteryState.charging || bs == BatteryState.full;
    } catch (_) {}
    final now = DateTime.now();
    final timeStr = DateFormat('h:mm').format(now);

    final realNotifs = await _native.getRecentNotifications();

    PhoneContextState currentState = const PhoneContextState();
    try {
      currentState = state;
    } catch (_) {}

    final updated = currentState.copyWith(
      batteryLevel: (info['batteryLevel'] as num?)?.toDouble() ?? 1.0,
      isCharging: info['isCharging'] as bool? ?? false,
      networkType: info['networkType'] as String? ?? 'Unknown',
      currentTimeString: timeStr,
      unreadNotificationsCount: realNotifs.length,
      activeApp: 'Oneova',
    );

    try {
      state = updated;
    } catch (_) {}
  }
}
