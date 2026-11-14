import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'money_models.dart';

FirebaseFirestore get _db => FirebaseFirestore.instance;
String? get _uid => FirebaseAuth.instance.currentUser?.uid;

Future<Map<String, dynamic>> _call(String name, [Map<String, dynamic>? data]) async {
  final res = await FirebaseFunctions.instance.httpsCallable(name).call<Map<String, dynamic>>(data ?? const {});
  return Map<String, dynamic>.from(res.data);
}

/// Friendly text for a failed money call.
String moneyError(Object e) {
  if (e is FirebaseFunctionsException) return e.message ?? 'Something went wrong. Please try again.';
  if (e is StateError) return e.message;
  return 'Something went wrong. Please try again.';
}

// ───────────────────────────── Live data ─────────────────────────────

final creatorWalletProvider = StreamProvider<CreatorWallet>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const CreatorWallet());
  return _db.doc('wallets/$uid').snapshots().map((d) => CreatorWallet.fromMap(d.data()));
});

final walletLedgerProvider = StreamProvider<List<LedgerItem>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db
      .collection('wallets/$uid/ledger')
      .orderBy('createdAt', descending: true)
      .limit(80)
      .snapshots()
      .map((s) => s.docs.map(LedgerItem.fromDoc).toList());
});

final withdrawalsProvider = StreamProvider<List<Withdrawal>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db
      .collection('withdrawals')
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(Withdrawal.fromDoc).toList());
});

final withdrawalProvider = StreamProvider.family<Withdrawal?, String>((ref, id) {
  return _db.doc('withdrawals/$id').snapshots().map((d) => d.exists ? Withdrawal.fromDoc(d) : null);
});

final kycProvider = StreamProvider<KycState>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const KycState());
  return _db.doc('kyc/$uid').snapshots().map((d) => KycState.fromMap(d.data()));
});

final payoutMethodsProvider = StreamProvider<List<PayoutMethod>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db.collection('payout_methods/$uid/methods').snapshots().map((s) => s.docs.map(PayoutMethod.fromDoc).toList());
});

final planStateProvider = StreamProvider<PlanState>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const PlanState());
  return _db.doc('subscriptions/$uid').snapshots().map((d) => PlanState.fromMap(d.data()));
});

String dayKey(DateTime d) => d.toUtc().toIso8601String().substring(0, 10);

/// The last [days] days of insights, oldest first, one entry per day (gaps are zero).
final creatorDaysProvider = StreamProvider.family<List<DayStat>, int>((ref, days) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  final today = DateTime.now().toUtc();
  final start = DateTime.utc(today.year, today.month, today.day).subtract(Duration(days: days - 1));
  return _db
      .collection('creator_daily/$uid/days')
      .where('date', isGreaterThanOrEqualTo: dayKey(start))
      .snapshots()
      .map((s) {
    final byDay = {for (final d in s.docs) d.id: d.data()};
    return [
      for (var i = 0; i < days; i++)
        () {
          final date = start.add(Duration(days: i));
          final m = byDay[dayKey(date)];
          return m == null ? DayStat(date: date) : DayStat.fromMap(date, m);
        }(),
    ];
  });
});

final myClipsProvider = StreamProvider<List<ClipStat>>((ref) {
  final uid = _uid;
  if (uid == null) return Stream.value(const []);
  return _db
      .collection('content')
      .where('authorId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(ClipStat.fromDoc).toList());
});

final clipProvider = StreamProvider.family<ClipStat?, String>((ref, id) {
  return _db.doc('content/$id').snapshots().map((d) => d.exists ? ClipStat.fromDoc(d) : null);
});

final followerCountProvider = FutureProvider<int>((ref) async {
  final uid = _uid;
  if (uid == null) return 0;
  final s = await _db.collection('relationships').where('followingId', isEqualTo: uid).where('status', isEqualTo: 'accepted').count().get();
  return s.count ?? 0;
});

// ───────────────────────────── Actions ─────────────────────────────

final moneyServiceProvider = Provider<MoneyService>((ref) => MoneyService());

class MoneyService {
  static const _device = MethodChannel('com.oneova.app/ova_device');

  /// Releases Diamonds whose hold is over. Returns how many were released.
  Future<int> syncWallet() async {
    try {
      final r = await _call('walletSync');
      return (r['released'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('[Money] walletSync: $e');
      return 0;
    }
  }

  /// A random id kept on this install, so the server can spot new devices.
  Future<String> deviceId() async {
    final p = await SharedPreferences.getInstance();
    var id = p.getString('oneova_payout_device');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await p.setString('oneova_payout_device', id);
    }
    return id;
  }

  Future<String?> _simCountry() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _device.invokeMethod<String>('simCountry');
    } catch (_) {
      return null;
    }
  }

  /// Country of the signed-in phone number, from its dial code.
  String? _phoneCountry() {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    if (phone == null || !phone.startsWith('+')) return null;
    final digits = phone.substring(1);
    for (final len in [3, 2, 1]) {
      if (digits.length < len) continue;
      final c = _dialToCountry[digits.substring(0, len)];
      if (c != null) return c;
    }
    return null;
  }

  /// Asks for location (with a SIM / phone / language fallback) and returns
  /// the payout country, rails and fees from the server.
  Future<PayoutOptions> payoutOptions({bool useLocation = true}) async {
    Position? pos;
    if (useLocation && !kIsWeb) {
      try {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 8)),
          ).catchError((_) async => (await Geolocator.getLastKnownPosition())!);
        }
      } catch (e) {
        debugPrint('[Money] location: $e');
      }
    }
    final r = await _call('payoutOptions', {
      if (pos != null) 'lat': pos.latitude,
      if (pos != null) 'lng': pos.longitude,
      'simCountry': await _simCountry(),
      'phoneCountry': _phoneCountry(),
      'localeCountry': ui.PlatformDispatcher.instance.locale.countryCode,
      'deviceId': await deviceId(),
    });
    return PayoutOptions.fromMap(r);
  }

  Future<List<({String code, String name})>> banks(String country) async {
    final r = await _call('payoutBanks', {'country': country});
    return [for (final b in (r['banks'] as List?) ?? const []) (code: '${b['code']}', name: '${b['name']}')];
  }

  Future<String> savePayoutMethod(Map<String, dynamic> data) async {
    final r = await _call('savePayoutMethod', data);
    return '${r['id']}';
  }

  Future<void> deletePayoutMethod(String id) => _call('deletePayoutMethod', {'id': id});

  /// Opens (or continues) an identity check. Returns the private Storage
  /// folder for the photos, or null when already verified / in review.
  Future<({String sessionId, String path})?> startKyc() async {
    final r = await _call('kycStart');
    if (r['path'] == null) return null;
    return (sessionId: '${r['sessionId']}', path: '${r['path']}');
  }

  /// Sends the check for review once the photos are uploaded.
  Future<void> submitKyc({
    required String sessionId,
    required String fullName,
    required String country,
    required String documentType,
    Map<String, String> countrySignals = const {},
  }) =>
      _call('kycSubmit', {
        'sessionId': sessionId,
        'fullName': fullName,
        'country': country,
        'documentType': documentType,
        'countrySignals': countrySignals,
      });

  Future<String> refreshKyc() async {
    final r = await _call('kycRefresh');
    return '${r['status']}';
  }

  Future<Map<String, dynamic>> requestWithdrawal({required int diamonds, required String methodId, required String idempotencyKey}) async {
    return _call('requestWithdrawal', {
      'diamonds': diamonds,
      'methodId': methodId,
      'idempotencyKey': idempotencyKey,
      'deviceId': await deviceId(),
    });
  }

  Future<void> cancelWithdrawal(String id) => _call('cancelWithdrawal', {'id': id});
}

const _dialToCountry = <String, String>{
  '254': 'KE', '233': 'GH', '256': 'UG', '255': 'TZ', '250': 'RW', '260': 'ZM', '265': 'MW', '237': 'CM',
  '221': 'SN', '225': 'CI', '229': 'BJ', '226': 'BF', '234': 'NG', '27': 'ZA', '20': 'EG', '251': 'ET',
  '243': 'CD', '244': 'AO', '258': 'MZ', '263': 'ZW', '212': 'MA', '216': 'TN', '213': 'DZ', '257': 'BI',
  '1': 'US', '44': 'GB', '33': 'FR', '49': 'DE', '34': 'ES', '39': 'IT', '31': 'NL', '32': 'BE', '41': 'CH',
  '46': 'SE', '47': 'NO', '45': 'DK', '353': 'IE', '351': 'PT', '48': 'PL', '61': 'AU', '64': 'NZ', '91': 'IN',
  '81': 'JP', '82': 'KR', '65': 'SG', '971': 'AE', '966': 'SA', '55': 'BR', '52': 'MX', '90': 'TR',
};

// ───────────────────────────── Watch time ─────────────────────────────

/// Collects how long each clip was watched and sends it in small batches
/// (`recordWatchTime`), which feeds the creator's watch time and completion rate.
class WatchTimeRecorder {
  WatchTimeRecorder._();
  static final instance = WatchTimeRecorder._();

  final _items = <Map<String, Object>>[];
  Timer? _timer;

  void add(String contentId, int watchMs, int durationMs) {
    if (_uid == null || watchMs < 500 || durationMs < 1000) return;
    _items.add({'contentId': contentId, 'watchMs': watchMs, 'durationMs': durationMs});
    if (_items.length >= 10) {
      flush();
    } else {
      _timer ??= Timer(const Duration(seconds: 45), flush);
    }
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_items.isEmpty) return;
    final batch = List<Map<String, Object>>.of(_items.take(40));
    _items.removeRange(0, batch.length);
    try {
      await _call('recordWatchTime', {'items': batch});
    } catch (e) {
      debugPrint('[WatchTime] $e');
    }
  }
}
