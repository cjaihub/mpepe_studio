import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A notification seen by Ova (Android, with Notification access on).
class OvaPhoneNotification {
  final String key;
  final String package;
  final String app;
  final String title;
  final String text;
  final DateTime postTime;
  final bool canReply;

  const OvaPhoneNotification({
    required this.key,
    required this.package,
    required this.app,
    required this.title,
    required this.text,
    required this.postTime,
    required this.canReply,
  });

  factory OvaPhoneNotification.fromMap(Map m) => OvaPhoneNotification(
        key: (m['key'] ?? '').toString(),
        package: (m['package'] ?? '').toString(),
        app: (m['app'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        text: (m['text'] ?? '').toString(),
        postTime: DateTime.fromMillisecondsSinceEpoch((m['postTime'] as num?)?.toInt() ?? 0),
        canReply: m['canReply'] == true,
      );
}

/// Which special accesses are granted at the OS level.
class OvaAccessStatus {
  final bool notificationAccess;
  final bool sms;
  final bool accessibility;
  final bool dndAccess;
  final bool overlay;

  const OvaAccessStatus({
    this.notificationAccess = false,
    this.sms = false,
    this.accessibility = false,
    this.dndAccess = false,
    this.overlay = false,
  });

  factory OvaAccessStatus.fromMap(Map m) => OvaAccessStatus(
        notificationAccess: m['notificationAccess'] == true,
        sms: m['sms'] == true,
        accessibility: m['accessibility'] == true,
        dndAccess: m['dndAccess'] == true,
        overlay: m['overlay'] == true,
      );
}

/// Dart side of OvaDeviceHub.kt. Android only; every call is a no-op elsewhere.
class OvaDeviceHub {
  static const _methods = MethodChannel('com.oneova.app/ova_device');
  static const _events = EventChannel('com.oneova.app/ova_events');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  Stream<Map<dynamic, dynamic>>? _stream;

  Stream<Map<dynamic, dynamic>> get events {
    if (!supported) return const Stream.empty();
    return _stream ??= _events.receiveBroadcastStream().where((e) => e is Map).cast<Map<dynamic, dynamic>>();
  }

  Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    if (!supported) return null;
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('[OvaDeviceHub] $method: ${e.code} ${e.message}');
      rethrow;
    }
  }

  Future<OvaAccessStatus> status() async {
    try {
      final m = await _call<Map>('status');
      return m == null ? const OvaAccessStatus() : OvaAccessStatus.fromMap(m);
    } catch (_) {
      return const OvaAccessStatus();
    }
  }

  Future<Map<String, dynamic>> deviceState() async {
    final m = await _call<Map>('deviceState');
    return m == null ? <String, dynamic>{} : Map<String, dynamic>.from(m);
  }

  Future<List<OvaPhoneNotification>> notifications({int limit = 15}) async {
    final l = await _call<List>('notifications', {'limit': limit});
    return (l ?? const []).whereType<Map>().map(OvaPhoneNotification.fromMap).toList();
  }

  Future<String> reply(String key, String text) async => await _call<String>('replyNotification', {'key': key, 'text': text}) ?? 'unsupported';
  Future<bool> openNotification(String key) async => await _call<bool>('openNotification', {'key': key}) ?? false;
  Future<bool> dismissNotification(String key) async => await _call<bool>('dismissNotification', {'key': key}) ?? false;

  Future<bool> mediaKey(String action) async => await _call<bool>('mediaKey', {'action': action}) ?? false;
  Future<String> setDnd(bool on) async => await _call<String>('setDnd', {'on': on}) ?? 'unsupported';
  Future<String> setRinger(String mode) async => await _call<String>('setRinger', {'mode': mode}) ?? 'unsupported';
  Future<bool> openPanel(String panel) async => await _call<bool>('openPanel', {'panel': panel}) ?? false;
  Future<void> openNotificationAccess() => _call('openNotificationAccess');
  Future<void> openDndAccess() => _call('openDndAccess');
  Future<void> returnToApp() => _call('returnToApp');

  /// Takes audio focus for Live voice: `exclusive` pauses other audio,
  /// `duck` lowers it. Returns granted / delayed / failed (unsupported off Android).
  Future<String> acquireAudioFocus({String mode = 'exclusive'}) async {
    try {
      return await _call<String>('acquireAudioFocus', {'mode': mode}) ?? 'unsupported';
    } catch (_) {
      return 'failed';
    }
  }

  Future<void> releaseAudioFocus() async {
    try {
      await _call('releaseAudioFocus');
    } catch (_) {}
  }

  /// Focus changes (`gain`, `loss`, `loss_transient`, `duck`) and
  /// `silenced` when another app (a call, a recorder) takes the mic.
  Stream<String> get audioFocusEvents => events.map((e) {
        if (e['type'] == 'audio_focus') return (e['state'] ?? 'other').toString();
        if (e['type'] == 'mic_silenced') return e['silenced'] == true ? 'silenced' : 'unsilenced';
        return '';
      }).where((s) => s.isNotEmpty);
}

final ovaDeviceHubProvider = Provider<OvaDeviceHub>((ref) => OvaDeviceHub());

/// Live device events: recent notifications (in memory only) and the app in front.
class OvaDeviceEvents {
  final List<OvaPhoneNotification> notifications;
  final String foregroundPackage;
  const OvaDeviceEvents({this.notifications = const [], this.foregroundPackage = ''});
}

final ovaDeviceEventsProvider = NotifierProvider<OvaDeviceEventsNotifier, OvaDeviceEvents>(OvaDeviceEventsNotifier.new);

class OvaDeviceEventsNotifier extends Notifier<OvaDeviceEvents> {
  StreamSubscription? _sub;

  @override
  OvaDeviceEvents build() {
    final hub = ref.read(ovaDeviceHubProvider);
    _sub = hub.events.listen(_onEvent, onError: (_) {});
    ref.onDispose(() => _sub?.cancel());
    return const OvaDeviceEvents();
  }

  void _onEvent(Map<dynamic, dynamic> e) {
    switch (e['type']) {
      case 'notification':
        final n = OvaPhoneNotification.fromMap(e);
        final list = [n, ...state.notifications.where((x) => x.key != n.key)].take(20).toList();
        state = OvaDeviceEvents(notifications: list, foregroundPackage: state.foregroundPackage);
      case 'notification_removed':
        state = OvaDeviceEvents(
          notifications: state.notifications.where((x) => x.key != e['key']).toList(),
          foregroundPackage: state.foregroundPackage,
        );
      case 'foreground':
        state = OvaDeviceEvents(notifications: state.notifications, foregroundPackage: (e['package'] ?? '').toString());
    }
  }

  void clear() => state = OvaDeviceEvents(foregroundPackage: state.foregroundPackage);
}
