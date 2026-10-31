import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/security/login_security.dart';
import '../auth/services/oneova_biometrics_service.dart';
import '../auth/services/secure_logout_service.dart';

final ovaGuardServiceProvider = Provider<OvaGuardService>((ref) => OvaGuardService(ref));

/// Signed-in (non-guest) uid, so the streams below follow sign-in changes.
final _guardUidProvider = StreamProvider<String?>((ref) => FirebaseAuth.instance
    .authStateChanges()
    .map((u) => (u == null || u.isAnonymous) ? null : u.uid));

/// Account risk + open alerts for the signed-in user (server-written).
final ovaGuardStateProvider = StreamProvider.autoDispose<Map<String, dynamic>>((ref) {
  final uid = ref.watch(_guardUidProvider).value;
  if (uid == null) return Stream.value(const {});
  return FirebaseFirestore.instance
      .collection('security_state')
      .doc(uid)
      .snapshots()
      .map((d) => d.data() ?? const {});
});

final ovaGuardEventsProvider = StreamProvider.autoDispose<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
  final uid = ref.watch(_guardUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('security_events')
      .doc(uid)
      .collection('events')
      .orderBy('at', descending: true)
      .limit(40)
      .snapshots()
      .map((s) => s.docs);
});

final ovaGuardDevicesProvider = StreamProvider.autoDispose<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
  final uid = ref.watch(_guardUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('security_state')
      .doc(uid)
      .collection('devices')
      .orderBy('lastSeenAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) => s.docs);
});

/// Automatic protective steps Ova Guard took on this account
/// (functions/src/guard/actions.ts): what, why, and until when.
final ovaGuardActionsProvider = StreamProvider.autoDispose<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((ref) {
  final uid = ref.watch(_guardUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('security_actions')
      .where('uid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) => s.docs);
});

/// One link's safety, from `guardCheckLinks` (Web Risk + look-alike checks).
class LinkSafety {
  final String url;
  final String verdict; // safe | suspicious | dangerous
  final List<String> reasons;
  const LinkSafety(this.url, this.verdict, this.reasons);
  bool get dangerous => verdict == 'dangerous';
  bool get suspicious => verdict == 'suspicious';
}

/// Client side of Ova Guard (functions/src/security.ts). The app only
/// reports what it sees; all scoring and every write to `security_events`
/// happen on the server.
class OvaGuardService {
  OvaGuardService(this._ref);

  final Ref _ref;
  final _functions = FirebaseFunctions.instance;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _stateSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _deviceSub;
  String? _reportedSession;
  bool _loggingOut = false;

  /// Starts reporting sessions and watching for remote log-outs.
  void start() {
    _authSub ??= FirebaseAuth.instance.idTokenChanges().listen(_onUser);
  }

  Future<void> _onUser(User? user) async {
    if (user == null || user.isAnonymous) {
      _stateSub?.cancel();
      _deviceSub?.cancel();
      _stateSub = null;
      _deviceSub = null;
      _reportedSession = null;
      return;
    }
    try {
      final token = await user.getIdTokenResult();
      final authTime = token.authTime;
      final key = '${user.uid}|${authTime?.millisecondsSinceEpoch}';
      if (_reportedSession == key) return;
      _reportedSession = key;

      final deviceId = await LoginSecurity.instance.deviceId();
      final scan = await LoginSecurity.instance.scanDevice(user.uid);
      final res = await _functions.httpsCallable('guardReportSession').call({
        'deviceId': deviceId,
        'deviceLabel': scan.label,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'networkCountry': WidgetsBinding.instance.platformDispatcher.locale.countryCode,
      });
      if ((res.data as Map?)?['loggedOut'] == true) {
        await _forceLogout();
        return;
      }
      _watch(user.uid, deviceId, authTime);
    } catch (e) {
      debugPrint('[OvaGuard] session report: $e');
    }
  }

  /// Signs this phone out when the account was secured from elsewhere or this
  /// device was logged out from the Security screen.
  void _watch(String uid, String deviceId, DateTime? authTime) {
    final since = authTime ?? DateTime.now();
    bool after(dynamic ts) => ts is Timestamp && ts.toDate().isAfter(since);
    final state = FirebaseFirestore.instance.collection('security_state').doc(uid);
    _stateSub?.cancel();
    _stateSub = state.snapshots().listen((d) {
      if (after(d.data()?['sessionsRevokedAt'])) _forceLogout();
    }, onError: (Object e) => debugPrint('[OvaGuard] state: $e'));
    _deviceSub?.cancel();
    _deviceSub = state.collection('devices').doc(deviceId).snapshots().listen((d) {
      final data = d.data();
      if (data?['revoked'] == true && after(data?['revokedAt'])) _forceLogout();
    }, onError: (Object e) => debugPrint('[OvaGuard] device: $e'));
  }

  Future<void> _forceLogout() async {
    if (_loggingOut) return;
    _loggingOut = true;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        // The server already deleted this device's key; drop the local secret.
        await _ref.read(oneovaBiometricsServiceProvider).revokeUserBiometrics(userId: uid, requireChallenge: false);
      }
      await _ref.read(secureLogoutServiceProvider).logout();
    } catch (e) {
      debugPrint('[OvaGuard] logout: $e');
    } finally {
      _loggingOut = false;
    }
  }

  /// Wrong password / SMS code on the login screen (signed out).
  Future<void> reportAuthFailure(String phone, {required bool otp}) async {
    if (phone.isEmpty) return;
    try {
      await _functions.httpsCallable('guardReportAuthFailure').call({
        'phone': phone,
        'kind': otp ? 'otp' : 'password',
      });
    } catch (e) {
      debugPrint('[OvaGuard] failure report: $e');
    }
  }

  /// "Yes, it was me".
  Future<void> confirm(String eventId) =>
      _functions.httpsCallable('guardRespond').call({'eventId': eventId, 'action': 'confirm'});

  /// "Secure my account": ends every session (this one too), removes all
  /// fingerprint keys, and sends this phone back to sign-in.
  Future<void> secureAccount({String? eventId}) async {
    await _functions.httpsCallable('guardRespond').call({'eventId': eventId, 'action': 'secure'});
    await _forceLogout();
  }

  Future<void> logOutDevice(String deviceId) =>
      _functions.httpsCallable('guardRevokeDevice').call({'deviceId': deviceId});

  /// Gemini's plain-language explanation (advisory only).
  Future<String> explain(String eventId) async {
    final res = await _functions.httpsCallable('guardExplainEvent').call({'eventId': eventId});
    return ((res.data as Map?)?['summary'] as String?) ?? '';
  }

  /// Checks a password against an old pre-Firebase-Auth hash on the server.
  static final Map<String, LinkSafety> _linkCache = {};

  /// Checks links the server cannot see (end-to-end encrypted chats): only
  /// the links are sent, never the message. Cached for this app session.
  Future<List<LinkSafety>> checkLinks(List<String> urls) async {
    final todo = urls.where((u) => !_linkCache.containsKey(u)).take(10).toList();
    if (todo.isNotEmpty) {
      try {
        final res = await FirebaseFunctions.instance.httpsCallable('guardCheckLinks').call({'urls': todo});
        final links = (res.data as Map?)?['links'] as List? ?? const [];
        for (var i = 0; i < links.length && i < todo.length; i++) {
          final m = Map<String, dynamic>.from(links[i] as Map);
          _linkCache[todo[i]] = LinkSafety(
            todo[i],
            m['verdict'] as String? ?? 'safe',
            List<String>.from(m['reasons'] as List? ?? const []),
          );
        }
      } catch (e) {
        debugPrint('[OvaGuard] link check: $e');
      }
    }
    return [for (final u in urls) if (_linkCache[u] != null) _linkCache[u]!];
  }

  Future<bool> checkLegacyPassword({required String password, String? phone}) async {
    final res = await _functions.httpsCallable('checkLegacyPassword').call({
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
    return (res.data as Map?)?['match'] == true;
  }
}
