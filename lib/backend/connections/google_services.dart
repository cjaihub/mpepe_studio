import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
// Account-specific server authorization (a chosen email) is only exposed by
// the platform interface, which google_sign_in already depends on.
// ignore: depend_on_referenced_packages
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;

/// Google services a person can keep linked to their Oneova profile
/// (Profile → Google services). Separate from signing in to Oneova.
///
/// Each service asks Google only for its own scopes. The refresh token is
/// held by the server (functions/src/googleLink.ts); the app reads status from
/// `users/{uid}/google_accounts/{sub}`. Must match `GOOGLE_SERVICES` there.
enum GoogleService {
  gmail(
    'Gmail',
    Icons.mail_rounded,
    'Read, search and send your email in Oneova and with Ova.',
    [
      'https://www.googleapis.com/auth/gmail.readonly',
      'https://www.googleapis.com/auth/gmail.send',
      'https://www.googleapis.com/auth/gmail.modify',
    ],
  ),
  youtube(
    'YouTube',
    Icons.smart_display_rounded,
    'Upload, manage comments, go live and see your channel stats.',
    [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
      'https://www.googleapis.com/auth/youtube.force-ssl',
      'https://www.googleapis.com/auth/yt-analytics.readonly',
      'https://www.googleapis.com/auth/yt-analytics-monetary.readonly',
    ],
  ),
  drive(
    'Google Drive',
    Icons.cloud_rounded,
    'Save and open files you choose with Oneova. Nothing else in your Drive.',
    ['https://www.googleapis.com/auth/drive.file'],
  ),
  calendar(
    'Google Calendar',
    Icons.calendar_month_rounded,
    'Add lives, calls and reminders to your calendar.',
    ['https://www.googleapis.com/auth/calendar.events'],
  ),
  contacts(
    'Google Contacts',
    Icons.contacts_rounded,
    'Find people you know on Oneova. Read-only.',
    ['https://www.googleapis.com/auth/contacts.readonly'],
  ),
  tasks(
    'Google Tasks',
    Icons.task_alt_rounded,
    'Let Ova add and check off your to-dos.',
    ['https://www.googleapis.com/auth/tasks'],
  );

  const GoogleService(this.label, this.icon, this.blurb, this.scopes);

  final String label;
  final IconData icon;
  final String blurb;
  final List<String> scopes;

  String get id => name;

  /// Asked with every service so the account can be named on its card.
  static const identityScopes = [
    'openid',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  List<String> get requestScopes => [...identityScopes, ...scopes];

  static GoogleService? fromId(String? id) {
    for (final s in values) {
      if (s.name == id) return s;
    }
    return null;
  }
}

enum GoogleServiceStatus {
  connected,

  /// Google said the grant is gone (removed in the Google account, password
  /// change, expiry). The person has to reconnect.
  needsReconnect,
}

/// One Google account on the person's profile and the services turned on.
class GoogleLinkedAccount {
  final String sub;
  final String email;
  final String name;
  final String photoUrl;
  final Map<GoogleService, GoogleServiceStatus> services;

  const GoogleLinkedAccount({
    required this.sub,
    required this.email,
    this.name = '',
    this.photoUrl = '',
    this.services = const {},
  });

  String get displayName => name.isNotEmpty ? name : email;

  GoogleServiceStatus? statusOf(GoogleService s) => services[s];

  bool isOn(GoogleService s) => services[s] == GoogleServiceStatus.connected;

  /// Maps a `google_accounts/{sub}` doc written by googleLink.ts. Only docs
  /// the server wrote (`tokenStore: 'server'`) count.
  static GoogleLinkedAccount? fromDoc(String id, Map<String, dynamic> data) {
    if (data['tokenStore'] != 'server') return null;
    final sub = (data['sub'] ?? id).toString();
    if (sub.isEmpty) return null;
    final raw = data['services'];
    final services = <GoogleService, GoogleServiceStatus>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final s = GoogleService.fromId(e.key.toString());
        if (s == null || e.value is! Map) continue;
        final status = (e.value as Map)['status'];
        services[s] = status == 'connected' ? GoogleServiceStatus.connected : GoogleServiceStatus.needsReconnect;
      }
    }
    return GoogleLinkedAccount(
      sub: sub,
      email: (data['email'] ?? '').toString(),
      name: (data['name'] ?? '').toString(),
      photoUrl: (data['photoUrl'] ?? '').toString(),
      services: services,
    );
  }
}

class GoogleLinkResult {
  final String email;
  final List<GoogleService> linked;
  final List<GoogleService> skipped;
  const GoogleLinkResult(this.email, this.linked, this.skipped);
}

class GoogleServicesException implements Exception {
  final String message;
  const GoogleServicesException(this.message);
  @override
  String toString() => message;
}

/// Live list of the person's linked Google accounts.
final googleAccountsProvider = StreamProvider<List<GoogleLinkedAccount>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('google_accounts')
      .snapshots()
      .map((q) => [for (final d in q.docs) ?GoogleLinkedAccount.fromDoc(d.id, d.data())]
        ..sort((a, b) => a.email.compareTo(b.email)));
});

/// Links, unlinks and hands out short-lived tokens. Static so the YouTube
/// store and Ova can use it without a [Ref].
class GoogleServices {
  GoogleServices._();

  static final _fn = FirebaseFunctions.instance;
  static final _cache = <String, (String, DateTime)>{};

  /// Turns [service] on. With [email] Google asks about that account only;
  /// without, Google's account picker opens first (adds a new account).
  /// Returns the linked email, or null if the person cancelled.
  static Future<String?> link(GoogleService service, {String? email}) async =>
      (await linkAll({service}, email: email))?.email;

  /// Turns several services on with one Google consent screen. Services
  /// whose permissions weren't all ticked come back in `skipped`.
  static Future<GoogleLinkResult?> linkAll(Set<GoogleService> services, {String? email}) async {
    if (FirebaseAuth.instance.currentUser == null) {
      throw const GoogleServicesException('Sign in to Oneova first.');
    }
    if (services.isEmpty) return null;
    final scopes = {...GoogleService.identityScopes, for (final s in services) ...s.scopes}.toList();
    String? code;
    try {
      if (email != null && email.isNotEmpty) {
        final t = await GoogleSignInPlatform.instance.serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters(
            request: AuthorizationRequestDetails(scopes: scopes, userId: null, email: email, promptIfUnauthorized: true),
          ),
        );
        code = t?.serverAuthCode;
      } else {
        final account = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
        code = (await account.authorizationClient.authorizeServer(scopes))?.serverAuthCode;
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw GoogleServicesException(e.description ?? 'Google sign-in failed. Try again.');
    }
    if (code == null || code.isEmpty) return null;
    final r = await _call('googleLinkService', {
      'services': [for (final s in services) s.id],
      'serverAuthCode': code,
    });
    List<GoogleService> parse(Object? v) => [for (final id in (v as List? ?? const [])) ?GoogleService.fromId(id.toString())];
    return GoogleLinkResult((r['email'] ?? '').toString(), parse(r['linked']), parse(r['skipped']));
  }

  /// Oneova stops using [service] for this account. Google keeps the grant
  /// until the account is removed (Google has no per-service revoke).
  static Future<void> unlink(String sub, GoogleService service) async {
    _cache.remove('$sub/${service.id}');
    await _call('googleUnlinkService', {'sub': sub, 'service': service.id});
  }

  /// Revokes Oneova's access at Google and deletes everything for [sub].
  static Future<void> removeAccount(String sub) async {
    _cache.removeWhere((k, _) => k.startsWith('$sub/'));
    await _call('googleRemoveAccount', {'sub': sub});
  }

  /// A short-lived access token for [service] on account [sub] (not Gmail,
  /// which stays on the server). Cached until shortly before it expires.
  static Future<String> accessToken(String sub, GoogleService service) async {
    final key = '$sub/${service.id}';
    final hit = _cache[key];
    if (hit != null && hit.$2.isAfter(DateTime.now())) return hit.$1;
    final r = await _call('googleAccessToken', {'sub': sub, 'service': service.id});
    final token = (r['accessToken'] ?? '').toString();
    if (token.isEmpty) throw const GoogleServicesException('Google didn\'t return access. Try again.');
    final exp = DateTime.fromMillisecondsSinceEpoch((r['expiresAt'] as num?)?.toInt() ?? 0);
    _cache[key] = (token, exp.subtract(const Duration(minutes: 2)));
    return token;
  }

  /// An HTTP client for [service], for account [sub] or else the first
  /// account that has it on. Null when no account has it on.
  static Future<http.Client?> clientFor(GoogleService service, {String? sub}) async {
    try {
      var id = sub;
      if (id == null) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return null;
        final q = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('google_accounts')
            .where('services.${service.id}.status', isEqualTo: 'connected')
            .limit(1)
            .get();
        if (q.docs.isEmpty) return null;
        id = q.docs.first.id;
      }
      final token = await accessToken(id, service);
      return _BearerClient(token);
    } catch (e) {
      debugPrint('[GoogleServices] ${service.id}: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await _fn.httpsCallable(name).call<Map<String, dynamic>>(data);
      return Map<String, dynamic>.from(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw GoogleServicesException(e.message ?? 'Google request failed. Try again.');
    }
  }
}

class _BearerClient extends http.BaseClient {
  _BearerClient(this.token);
  final String token;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
