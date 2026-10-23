import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'login_security.dart';

/// One row of `users/{uid}/login_history`.
class LoginHistoryEntry {
  final String id;
  final DateTime? at;
  final bool success;
  final String method;
  final String? failureCode;
  final String deviceId;
  final String deviceModel;
  final String os;
  final String osVersion;
  final String appVersion;
  final bool newDevice;
  final String? ipMasked;
  final String? place;
  final String? locationSource;

  const LoginHistoryEntry({
    required this.id,
    required this.at,
    required this.success,
    required this.method,
    required this.failureCode,
    required this.deviceId,
    required this.deviceModel,
    required this.os,
    required this.osVersion,
    required this.appVersion,
    required this.newDevice,
    required this.ipMasked,
    required this.place,
    required this.locationSource,
  });

  factory LoginHistoryEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    String s(String k) => (d[k] as String?) ?? '';
    final loc = d['location'] as Map<String, dynamic>?;
    final place = [d['city'], d['region'], d['country']]
        .whereType<String>()
        .where((x) => x.isNotEmpty)
        .join(', ');
    String? coords;
    if (loc != null && loc['lat'] is num && loc['lng'] is num) {
      coords = '${(loc['lat'] as num).toStringAsFixed(2)}, ${(loc['lng'] as num).toStringAsFixed(2)}';
    }
    return LoginHistoryEntry(
      id: doc.id,
      at: ((d['at'] ?? d['clientAt']) as Timestamp?)?.toDate(),
      success: d['success'] == true,
      method: s('method'),
      failureCode: d['failureCode'] as String?,
      deviceId: s('deviceId'),
      deviceModel: s('deviceModel'),
      os: s('os'),
      osVersion: s('osVersion'),
      appVersion: s('appVersion'),
      newDevice: d['newDevice'] == true,
      ipMasked: d['ipMasked'] as String?,
      place: place.isNotEmpty ? place : coords,
      locationSource: place.isNotEmpty ? (d['geoSource'] as String?) : (coords != null ? 'device' : null),
    );
  }
}

/// Keeps an append-only sign-in log per account.
///
/// Every sign-in writes one row: device, OS, app version, time, method,
/// success, and an approximate place. The place is the phone's coarse
/// location (rounded to ~1 km, only when location permission was already
/// given; this never asks for it) or the IP region from the `loginContext`
/// Cloud Function when that is deployed.
///
/// A failed attempt before sign-in has no account to write to yet, so it is
/// kept on this device and added to the account's log on its next sign-in.
class LoginHistory {
  LoginHistory._();
  static final LoginHistory instance = LoginHistory._();

  static const _storage = FlutterSecureStorage();
  static const _pendingKey = 'oneova_login_failures';
  static const _maxPending = 20;

  _DeviceFacts? _facts;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('login_history');

  /// Newest first, live.
  Stream<List<LoginHistoryEntry>> watch(String uid, {int limit = 50}) => _col(uid)
      .orderBy('clientAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map(LoginHistoryEntry.fromDoc).toList());

  /// Records a completed sign-in for [user], plus any failed attempts this
  /// device saw for the same phone number before it. Never throws.
  Future<void> recordSuccess(User user, {required String method, required bool newDevice}) async {
    try {
      final base = await _baseFields();
      final ctx = await _placeFields();
      final pending = await _takePending(_phoneDigits(user));
      final batch = FirebaseFirestore.instance.batch();
      for (final f in pending) {
        batch.set(_col(user.uid).doc(), {
          ...base,
          'success': false,
          'method': f['method'] ?? 'unknown',
          'failureCode': f['code'],
          'newDevice': newDevice,
          'clientAt': Timestamp.fromMillisecondsSinceEpoch(f['t'] as int? ?? 0),
          'at': FieldValue.serverTimestamp(),
        });
      }
      batch.set(_col(user.uid).doc(), {
        ...base,
        ...ctx,
        'success': true,
        'method': method,
        'newDevice': newDevice,
        'clientAt': Timestamp.now(),
        'at': FieldValue.serverTimestamp(),
      });
      await batch.commit().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[LoginHistory] success: $e');
    }
  }

  /// Records a failed check. Written straight to the account when someone is
  /// already signed in (a wrong second-factor code), otherwise kept on this
  /// device until that phone number signs in. Never throws.
  Future<void> recordFailure({required String method, String? code, String? phone}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        final base = await _baseFields();
        await _col(user.uid).add({
          ...base,
          'success': false,
          'method': method,
          'failureCode': code,
          'newDevice': false,
          'clientAt': Timestamp.now(),
          'at': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 6));
        return;
      }
      if (phone == null || phone.isEmpty) return;
      final list = await _readPending();
      list.add({'phone': phone, 'method': method, 'code': code, 't': DateTime.now().millisecondsSinceEpoch});
      while (list.length > _maxPending) {
        list.removeAt(0);
      }
      await _storage.write(key: _pendingKey, value: jsonEncode(list));
    } catch (e) {
      debugPrint('[LoginHistory] failure: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _readPending() async {
    try {
      final raw = await _storage.read(key: _pendingKey).timeout(const Duration(seconds: 2));
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static String _digits(String? v) => (v ?? '').replaceAll(RegExp(r'\D'), '');

  /// The account's phone digits: its phone number, or the number inside the
  /// phone-password identity (`p<digits>@phone.oneova.app`).
  static String? _phoneDigits(User user) {
    final phone = _digits(user.phoneNumber);
    if (phone.isNotEmpty) return phone;
    final email = user.email ?? '';
    if (email.endsWith('@${LoginSecurity.authEmailDomain}') && email.startsWith('p')) {
      final d = _digits(email.split('@').first);
      if (d.isNotEmpty) return d;
    }
    return null;
  }

  /// Removes and returns this phone's pending failures from the last week.
  Future<List<Map<String, dynamic>>> _takePending(String? phoneDigits) async {
    final list = await _readPending();
    if (list.isEmpty) return [];
    final weekAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    final mine = <Map<String, dynamic>>[];
    final keep = <Map<String, dynamic>>[];
    for (final f in list) {
      if ((f['t'] as int? ?? 0) < weekAgo) continue;
      if (phoneDigits != null && _digits(f['phone'] as String?) == phoneDigits) {
        mine.add(f);
      } else {
        keep.add(f);
      }
    }
    await _storage.write(key: _pendingKey, value: jsonEncode(keep));
    return mine;
  }

  Future<Map<String, dynamic>> _baseFields() async {
    final f = _facts ??= await _DeviceFacts.load();
    return {
      'deviceId': await LoginSecurity.instance.deviceId(),
      'deviceModel': f.model,
      'os': f.os,
      'osVersion': f.osVersion,
      'appVersion': f.appVersion,
      'physical': f.physical,
    };
  }

  /// Coarse device location (permission already granted only), then the IP
  /// region from the server. Each part is optional.
  Future<Map<String, dynamic>> _placeFields() async {
    final out = <String, dynamic>{};
    final results = await Future.wait([_coarseLocation(), _ipContext()]);
    final loc = results[0];
    final ip = results[1];
    if (loc != null) out['location'] = loc;
    if (ip != null) {
      for (final k in ['ipMasked', 'country', 'region', 'city']) {
        final v = ip[k];
        if (v is String && v.isNotEmpty) out[k] = v.length > 60 ? v.substring(0, 60) : v;
      }
      if (out.containsKey('country') || out.containsKey('city')) out['geoSource'] = 'ip';
    }
    return out;
  }

  Future<Map<String, dynamic>?> _coarseLocation() async {
    if (kIsWeb) return null;
    try {
      final p = await Geolocator.checkPermission();
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) return null;
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 4),
            ),
          );
      double round(double v) => (v * 100).roundToDouble() / 100;
      return {'lat': round(pos.latitude), 'lng': round(pos.longitude), 'source': 'device_coarse'};
    } catch (e) {
      debugPrint('[LoginHistory] location: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _ipContext() async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('loginContext', options: HttpsCallableOptions(timeout: const Duration(seconds: 4)))
          .call<Map<String, dynamic>>({
        'networkCountry': PlatformDispatcher.instance.locale.countryCode,
      });
      return Map<String, dynamic>.from(res.data);
    } catch (e) {
      // Not deployed or offline: the row is still written without it.
      debugPrint('[LoginHistory] ip context: $e');
      return null;
    }
  }
}

class _DeviceFacts {
  final String model;
  final String os;
  final String osVersion;
  final String appVersion;
  final bool physical;

  const _DeviceFacts(this.model, this.os, this.osVersion, this.appVersion, this.physical);

  static Future<_DeviceFacts> load() async {
    var model = 'Unknown device';
    var os = kIsWeb ? 'web' : defaultTargetPlatform.name;
    var osVersion = '';
    var physical = true;
    try {
      final info = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final a = await info.androidInfo;
        model = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android';
        osVersion = '${a.version.release} (SDK ${a.version.sdkInt})';
        physical = a.isPhysicalDevice;
      } else if (!kIsWeb && Platform.isIOS) {
        final i = await info.iosInfo;
        model = i.utsname.machine;
        os = i.systemName;
        osVersion = i.systemVersion;
        physical = i.isPhysicalDevice;
      } else if (kIsWeb) {
        final w = await info.webBrowserInfo;
        model = w.browserName.name;
      }
    } catch (_) {}
    var appVersion = '';
    try {
      final p = await PackageInfo.fromPlatform();
      appVersion = '${p.version}+${p.buildNumber}';
    } catch (_) {}
    return _DeviceFacts(model, os, osVersion, appVersion, physical);
  }
}
