import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

class DesktopCloudException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const DesktopCloudException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'DesktopCloudException($code): $message';
}

class DesktopRestDoc {
  final String id;
  final Map<String, dynamic> data;

  /// Firestore `updateTime` of the document (RFC 3339), when known. Pollers
  /// use it to tell whether a collection changed between two reads.
  final String? updateTime;

  const DesktopRestDoc({
    required this.id,
    required this.data,
    this.updateTime,
  });
}

/// What kind of failure a poll hit; decides how long to wait before retrying.
enum DesktopPollErrorKind { permissionDenied, quota, unauthenticated, transient }

/// Exponential back-off with jitter for REST polling.
///
/// * transient / auth errors: [base] doubling up to [max].
/// * quota (HTTP 429, `RESOURCE_EXHAUSTED`, "Quota exceeded"): starts at
///   [quotaBase] and doubles up to [quotaMax] — the quota is shared by the
///   whole project, so hammering it hurts the live app too.
/// * permission-denied: [onError] returns `null`, meaning stop polling until
///   the watcher is bound again.
///
/// Jitter keeps each delay between 50% and 100% of the computed value so
/// several watchers don't retry in lock-step.
class DesktopPollBackoff {
  DesktopPollBackoff({
    this.base = const Duration(seconds: 2),
    this.max = const Duration(minutes: 2),
    this.quotaBase = const Duration(seconds: 30),
    this.quotaMax = const Duration(minutes: 15),
    double Function()? random,
  }) : _random = random ?? Random().nextDouble;

  final Duration base;
  final Duration max;
  final Duration quotaBase;
  final Duration quotaMax;
  final double Function() _random;

  int _failures = 0;

  /// Consecutive failures since the last successful poll.
  int get failures => _failures;

  void reset() => _failures = 0;

  static DesktopPollErrorKind classify(Object error) {
    if (error is DesktopCloudException) {
      final status = error.statusCode;
      if (error.code == 'permission-denied' || status == 403) {
        return DesktopPollErrorKind.permissionDenied;
      }
      if (error.code == 'resource-exhausted' ||
          status == 429 ||
          error.message.toLowerCase().contains('quota exceeded')) {
        return DesktopPollErrorKind.quota;
      }
      if (error.code == 'unauthenticated' ||
          error.code == 'token-refresh-failed' ||
          status == 401) {
        return DesktopPollErrorKind.unauthenticated;
      }
      return DesktopPollErrorKind.transient;
    }
    if (error.toString().toLowerCase().contains('quota exceeded')) {
      return DesktopPollErrorKind.quota;
    }
    return DesktopPollErrorKind.transient;
  }

  /// Records a failure and returns how long to wait before the next poll, or
  /// `null` when polling must pause (permission-denied).
  Duration? onError(Object error) {
    _failures++;
    final kind = classify(error);
    if (kind == DesktopPollErrorKind.permissionDenied) return null;
    final quota = kind == DesktopPollErrorKind.quota;
    final start = quota ? quotaBase : base;
    final cap = quota ? quotaMax : max;
    final exp = (_failures - 1).clamp(0, 20);
    final rawMs = start.inMilliseconds * pow(2, exp);
    final cappedMs = min(rawMs.toDouble(), cap.inMilliseconds.toDouble());
    final jitter = 0.5 + 0.5 * _random().clamp(0.0, 1.0);
    return Duration(milliseconds: (cappedMs * jitter).round());
  }
}

/// Project-wide pause for polling after Firestore reports its quota is used
/// up. Every poller checks it before reading, so one quota error slows all
/// of them instead of each finding out on its own.
class DesktopPollGate {
  DesktopPollGate({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _quotaCooldownUntil;

  Duration remainingCooldown() {
    final until = _quotaCooldownUntil;
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  void noteQuotaExceeded(Duration cooldown) {
    final until = _now().add(cooldown);
    if (_quotaCooldownUntil == null || until.isAfter(_quotaCooldownUntil!)) {
      _quotaCooldownUntil = until;
    }
  }

  void clear() => _quotaCooldownUntil = null;
}

/// One subscriber of a [DesktopCollectionPoller].
class _PollListener {
  _PollListener({
    required this.controller,
    required this.interval,
    required this.idleInterval,
    this.keepFast,
  });

  final StreamController<List<DesktopRestDoc>> controller;
  final Duration interval;
  final Duration idleInterval;
  final bool Function()? keepFast;
}

/// Polls one collection for any number of subscribers.
///
/// * Only one read of the path is ever in flight; the next one is scheduled
///   after the previous finishes (no `Timer.periodic` pile-ups).
/// * Subscribers share each read; a new subscriber gets the last snapshot
///   right away.
/// * While nothing changes the delay grows from the fastest subscriber's
///   `interval` towards its `idleInterval`; any change (or a subscriber's
///   `keepFast()` returning true) drops it back to `interval`.
/// * Errors back off via [DesktopPollBackoff]; permission-denied pauses until
///   a new subscriber attaches (the agent rebinding).
/// * When the last subscriber leaves, the poller stops after [disposeGrace]
///   (so an immediate rebind reuses it) and calls [onDispose].
class DesktopCollectionPoller {
  DesktopCollectionPoller({
    required this.path,
    required this.fetch,
    DesktopPollGate? gate,
    DesktopPollBackoff? backoff,
    this.disposeGrace = const Duration(seconds: 3),
    this.onDispose,
  })  : _gate = gate ?? DesktopPollGate(),
        backoff = backoff ?? DesktopPollBackoff();

  final String path;

  /// Reads the collection once.
  final Future<List<DesktopRestDoc>> Function() fetch;
  final DesktopPollGate _gate;
  final DesktopPollBackoff backoff;
  final Duration disposeGrace;
  final void Function(DesktopCollectionPoller poller)? onDispose;

  static const double _idleRamp = 1.6;

  final List<_PollListener> _listeners = [];
  List<DesktopRestDoc>? _lastDocs;
  String? _lastFingerprint;
  int _unchangedPolls = 0;
  bool _inFlight = false;
  bool _paused = false;
  bool _disposed = false;
  Timer? _timer;
  Timer? _graceTimer;

  bool get isPaused => _paused;
  bool get isDisposed => _disposed;
  int get listenerCount => _listeners.length;

  Stream<List<DesktopRestDoc>> watch({
    required Duration interval,
    Duration? idleInterval,
    bool Function()? keepFast,
  }) {
    late final _PollListener listener;
    final controller = StreamController<List<DesktopRestDoc>>(
      onListen: () => _attach(listener),
      onCancel: () => _detach(listener),
    );
    listener = _PollListener(
      controller: controller,
      interval: interval,
      idleInterval: (idleInterval == null || idleInterval < interval)
          ? interval * 3
          : idleInterval,
      keepFast: keepFast,
    );
    return controller.stream;
  }

  void _attach(_PollListener listener) {
    if (_disposed) {
      listener.controller.addError(
        StateError('Poller for $path was disposed'),
      );
      return;
    }
    _graceTimer?.cancel();
    _graceTimer = null;
    _listeners.add(listener);
    final cached = _lastDocs;
    if (cached != null) {
      listener.controller.add(cached);
    }
    if (_paused) {
      // A fresh bind is the signal to try again after permission-denied.
      _paused = false;
      backoff.reset();
      _schedule(Duration.zero);
      return;
    }
    if (_timer == null && !_inFlight) {
      _schedule(cached == null ? Duration.zero : _nextDelay(changed: false));
    }
  }

  void _detach(_PollListener listener) {
    _listeners.remove(listener);
    if (_listeners.isNotEmpty || _disposed) return;
    _graceTimer?.cancel();
    _graceTimer = Timer(disposeGrace, () {
      if (_listeners.isEmpty) dispose();
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    onDispose?.call(this);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed || _paused || _listeners.isEmpty) {
      _timer = null;
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_poll());
    });
  }

  Duration _nextDelay({required bool changed}) {
    if (_listeners.isEmpty) return const Duration(seconds: 1);
    var fast = _listeners.first.interval;
    var idle = _listeners.first.idleInterval;
    var keepFast = false;
    for (final l in _listeners) {
      if (l.interval < fast) fast = l.interval;
      if (l.idleInterval < idle) idle = l.idleInterval;
      if (l.keepFast?.call() ?? false) keepFast = true;
    }
    if (changed || keepFast || _unchangedPolls == 0) return fast;
    final grown =
        fast.inMilliseconds * pow(_idleRamp, _unchangedPolls).toDouble();
    return Duration(
      milliseconds: min(grown, idle.inMilliseconds.toDouble()).round(),
    );
  }

  static String _fingerprint(List<DesktopRestDoc> docs) {
    final sb = StringBuffer();
    for (final d in docs) {
      sb
        ..write(d.id)
        ..write('@')
        ..write(d.updateTime ?? d.data.toString())
        ..write('|');
    }
    return sb.toString();
  }

  Future<void> _poll() async {
    if (_inFlight || _disposed || _paused || _listeners.isEmpty) return;
    final cooldown = _gate.remainingCooldown();
    if (cooldown > Duration.zero) {
      _schedule(cooldown);
      return;
    }
    _inFlight = true;
    try {
      final docs = await fetch();
      if (_disposed) return;
      backoff.reset();
      final fp = _fingerprint(docs);
      final changed = fp != _lastFingerprint;
      _lastFingerprint = fp;
      _unchangedPolls = changed ? 0 : _unchangedPolls + 1;
      _lastDocs = docs;
      for (final l in List.of(_listeners)) {
        if (!l.controller.isClosed) l.controller.add(docs);
      }
      _inFlight = false;
      _schedule(_nextDelay(changed: changed));
    } catch (e, st) {
      _inFlight = false;
      if (_disposed) return;
      final kind = DesktopPollBackoff.classify(e);
      final delay = backoff.onError(e);
      if (kind == DesktopPollErrorKind.quota && delay != null) {
        _gate.noteQuotaExceeded(delay);
      }
      // Tell subscribers once per error streak (and when pausing) instead of
      // on every retry, so logs and UI don't flood.
      if (backoff.failures == 1 || delay == null) {
        for (final l in List.of(_listeners)) {
          if (!l.controller.isClosed) l.controller.addError(e, st);
        }
      }
      if (delay == null) {
        _paused = true;
        _timer?.cancel();
        _timer = null;
        debugPrint(
          '[DesktopCloud] Polling paused for $path (permission denied) '
          'until it is bound again.',
        );
        return;
      }
      debugPrint(
        '[DesktopCloud] Poll of $path failed (${kind.name}, '
        'attempt ${backoff.failures}); retrying in ${delay.inSeconds}s.',
      );
      _schedule(delay);
    } finally {
      _inFlight = false;
    }
  }
}

/// Authenticated Firebase Auth + Cloud Firestore REST client for Oneova Desktop.
///
/// Uses Google IdentityToolkit, SecureToken, Callable Cloud Functions, and
/// Firestore v1 REST APIs over HTTPS while persisting credentials in
/// [SharedPreferences] so ad-hoc macOS/desktop builds never fail on Apple
/// Data Protection Keychain (`OSStatus -34018`) entitlements.
class DesktopFirebaseRestClient {
  DesktopFirebaseRestClient._internal();
  static final DesktopFirebaseRestClient instance =
      DesktopFirebaseRestClient._internal();

  static const String _prefAgentUid = 'oneova_desktop_agent_uid';
  static const String _prefAgentEmail = 'oneova_desktop_agent_email';
  static const String _prefAgentSecret = 'oneova_desktop_agent_secret';
  static const String _prefAuthUid = 'oneova_desktop_auth_uid';
  static const String _prefRefreshToken = 'oneova_desktop_refresh_token';
  static const String _prefIsAccount = 'oneova_desktop_is_account';
  static const String _prefBioRefreshToken = 'oneova_desktop_bio_refresh_token';
  static const String _prefLastAccountLabel = 'oneova_desktop_last_account_label';

  static const MethodChannel _oauthChannel = MethodChannel('oneova/desktop_oauth');

  final http.Client _http = http.Client();

  String? _uid;
  String? _idToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  bool _isAccountUser = false;
  Future<void>? _inflightAuth;

  String get projectId => DefaultFirebaseOptions.macos.projectId;
  String get apiKey => DefaultFirebaseOptions.macos.apiKey;

  String? get currentUid => _uid;
  bool get isAccountUser => _isAccountUser;
  bool get isAuthenticated => _uid != null && _idToken != null;

  String get _documentsBaseUrl =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  Future<void> ensureAuthenticated() async {
    if (_idToken != null &&
        _expiresAt != null &&
        DateTime.now().isBefore(_expiresAt!.subtract(const Duration(minutes: 4)))) {
      return;
    }
    if (_inflightAuth != null) {
      await _inflightAuth;
      return;
    }
    final completer = Completer<void>();
    _inflightAuth = completer.future;
    try {
      await _authenticateInternal();
      completer.complete();
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _inflightAuth = null;
    }
  }

  Future<void> _authenticateInternal() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRefresh = _refreshToken ?? prefs.getString(_prefRefreshToken);
    if (savedRefresh != null && savedRefresh.isNotEmpty) {
      try {
        await _refreshWithToken(savedRefresh, prefs);
        return;
      } catch (e) {
        debugPrint('[DesktopCloud] Stored refresh token invalid, re-bootstrapping: $e');
        await prefs.remove(_prefRefreshToken);
        await prefs.remove(_prefIsAccount);
        _refreshToken = null;
        _idToken = null;
      }
    }

    await _bootstrapDesktopAgent(prefs);
  }

  Future<void> _refreshWithToken(String refreshToken, SharedPreferences prefs) async {
    final uri = Uri.parse(
      'https://securetoken.googleapis.com/v1/token?key=${Uri.encodeQueryComponent(apiKey)}',
    );
    final resp = await _http.post(
      uri,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );

    if (resp.statusCode != 200) {
      throw DesktopCloudException(
        code: 'token-refresh-failed',
        message: 'Token refresh failed (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final idToken = body['id_token'] as String?;
    final nextRefresh = body['refresh_token'] as String?;
    final userId = body['user_id'] as String?;
    final expiresInSec = int.tryParse((body['expires_in'] ?? '3600').toString()) ?? 3600;

    if (idToken == null || userId == null) {
      throw const DesktopCloudException(
        code: 'invalid-token-response',
        message: 'Missing id_token or user_id from SecureToken.',
      );
    }

    _uid = userId;
    _idToken = idToken;
    _refreshToken = nextRefresh ?? refreshToken;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresInSec));
    _isAccountUser =
        (prefs.getBool(_prefIsAccount) ?? false) && !userId.startsWith('desktop_agent_');

    await prefs.setString(_prefAuthUid, userId);
    await prefs.setString(_prefRefreshToken, _refreshToken!);
  }

  Future<void> _bootstrapDesktopAgent(
    SharedPreferences prefs, {
    bool forceNewEnrollment = false,
  }) async {
    String? existingUid = forceNewEnrollment ? null : prefs.getString(_prefAgentUid);
    String? existingEmail = forceNewEnrollment ? null : prefs.getString(_prefAgentEmail);
    String? secret = forceNewEnrollment ? null : prefs.getString(_prefAgentSecret);

    if (!forceNewEnrollment &&
        existingUid != null &&
        existingEmail != null &&
        secret != null &&
        secret.length >= 64) {
      try {
        await _signInAgentCredentials(
          agentUid: existingUid,
          agentEmail: existingEmail,
          secret: secret,
          prefs: prefs,
        );
        return;
      } catch (e) {
        debugPrint('[DesktopCloud] Existing agent credentials rejected, re-enrolling: $e');
      }
    }

    secret = _generateHexSecret(32);
    final callableUri = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/desktopAgentBootstrap',
    );
    final payload = <String, dynamic>{
      'secret': secret,
      'computerName': Platform.localHostname,
      'os': Platform.operatingSystem,
    };

    final resp = await _http.post(
      callableUri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'data': payload}),
    );

    if (resp.statusCode != 200) {
      throw DesktopCloudException(
        code: 'bootstrap-failed',
        message: _extractCallableError(resp.body, resp.statusCode),
        statusCode: resp.statusCode,
      );
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = (decoded['result'] ?? decoded['data']) as Map<String, dynamic>?;
    final agentUid = result?['agentUid'] as String?;
    final agentEmail = result?['agentEmail'] as String?;

    if (agentUid == null || agentEmail == null) {
      throw const DesktopCloudException(
        code: 'bootstrap-invalid',
        message: 'Desktop bootstrap returned incomplete credentials.',
      );
    }

    await prefs.setString(_prefAgentUid, agentUid);
    await prefs.setString(_prefAgentEmail, agentEmail);
    await prefs.setString(_prefAgentSecret, secret);

    await _signInAgentCredentials(
      agentUid: agentUid,
      agentEmail: agentEmail,
      secret: secret,
      prefs: prefs,
    );
  }

  Future<void> _signInAgentCredentials({
    required String agentUid,
    required String agentEmail,
    required String secret,
    required SharedPreferences prefs,
  }) async {
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${Uri.encodeQueryComponent(apiKey)}',
    );
    final resp = await _http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': agentEmail,
        'password': secret,
        'returnSecureToken': true,
      }),
    );

    if (resp.statusCode != 200) {
      throw DesktopCloudException(
        code: 'agent-signin-failed',
        message: _extractAuthError(resp.body, resp.statusCode),
        statusCode: resp.statusCode,
      );
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final idToken = body['idToken'] as String?;
    final refreshToken = body['refreshToken'] as String?;
    final localId = (body['localId'] as String?) ?? agentUid;
    final expiresInSec = int.tryParse((body['expiresIn'] ?? '3600').toString()) ?? 3600;

    if (idToken == null || refreshToken == null) {
      throw const DesktopCloudException(
        code: 'agent-signin-missing-fields',
        message: 'Agent sign-in returned incomplete fields.',
      );
    }

    _uid = localId;
    _idToken = idToken;
    _refreshToken = refreshToken;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresInSec));
    _isAccountUser = false;

    await prefs.setString(_prefAuthUid, localId);
    await prefs.setString(_prefRefreshToken, refreshToken);
    await prefs.setBool(_prefIsAccount, false);
  }

  Future<String> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${Uri.encodeQueryComponent(apiKey)}',
    );
    final resp = await _http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    if (resp.statusCode != 200) {
      throw DesktopCloudException(
        code: 'auth-failed',
        message: _extractAuthError(resp.body, resp.statusCode),
        statusCode: resp.statusCode,
      );
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final uid = body['localId'] as String?;
    final idToken = body['idToken'] as String?;
    final refreshToken = body['refreshToken'] as String?;
    final expiresInSec = int.tryParse((body['expiresIn'] ?? '3600').toString()) ?? 3600;

    if (uid == null || idToken == null || refreshToken == null) {
      throw const DesktopCloudException(
        code: 'auth-incomplete',
        message: 'Sign-in succeeded but token response was incomplete.',
      );
    }

    _uid = uid;
    _idToken = idToken;
    _refreshToken = refreshToken;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresInSec));
    _isAccountUser = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAuthUid, uid);
    await prefs.setString(_prefRefreshToken, refreshToken);
    await prefs.setBool(_prefIsAccount, true);
    await prefs.setString(_prefBioRefreshToken, refreshToken);
    final displayEmail = (body['email'] as String?) ?? email;
    if (!displayEmail.endsWith('@agent.oneova.internal')) {
      await prefs.setString(_prefLastAccountLabel, displayEmail);
    }
    return uid;
  }

  /// Launches native macOS `ASWebAuthenticationSession` with PKCE against
  /// Google's OAuth 2.0 endpoint and exchanges the resulting Google `id_token`
  /// with Firebase IdentityToolkit (`accounts:signInWithIdp`).
  Future<String> signInWithGoogle() async {
    final iosClientId = DefaultFirebaseOptions.macos.iosClientId;
    if (iosClientId == null || iosClientId.isEmpty) {
      throw const DesktopCloudException(
        code: 'missing-client-id',
        message: 'Google OAuth client ID is not configured.',
      );
    }

    final prefix = iosClientId.replaceAll('.apps.googleusercontent.com', '');
    final callbackScheme = 'com.googleusercontent.apps.$prefix';
    final redirectUri = '$callbackScheme:/oauthredirect';

    final codeVerifier = _generatePkceVerifier();
    final challengeBytes = sha256.convert(ascii.encode(codeVerifier)).bytes;
    final codeChallenge = base64UrlEncode(challengeBytes).replaceAll('=', '');
    final stateNonce = _generateHexSecret(12);

    final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': iosClientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': stateNonce,
      'prompt': 'select_account',
    });

    final String? callbackUrlStr;
    try {
      callbackUrlStr = await _oauthChannel.invokeMethod<String>(
        'launchWebAuth',
        {
          'url': authUri.toString(),
          'callbackScheme': callbackScheme,
        },
      );
    } on PlatformException catch (e) {
      throw DesktopCloudException(
        code: e.code,
        message: e.message ?? 'Google Sign-In canceled.',
      );
    }

    if (callbackUrlStr == null || callbackUrlStr.isEmpty) {
      throw const DesktopCloudException(
        code: 'canceled',
        message: 'Google Sign-In was canceled.',
      );
    }

    final callbackUri = Uri.parse(callbackUrlStr);
    final authCode = callbackUri.queryParameters['code'];
    final returnedState = callbackUri.queryParameters['state'];
    if (authCode == null || authCode.isEmpty || returnedState != stateNonce) {
      final errDesc = callbackUri.queryParameters['error'] ?? 'Authorization failed';
      throw DesktopCloudException(
        code: 'oauth-error',
        message: 'Google Sign-In error: $errDesc',
      );
    }

    final tokenResp = await _http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': iosClientId,
        'code': authCode,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri,
      },
    );

    if (tokenResp.statusCode != 200) {
      throw DesktopCloudException(
        code: 'google-token-failed',
        message: 'Google token exchange failed (${tokenResp.statusCode}).',
        statusCode: tokenResp.statusCode,
      );
    }

    final tokenMap = jsonDecode(tokenResp.body) as Map<String, dynamic>;
    final googleIdToken = tokenMap['id_token'] as String?;
    final googleAccessToken = tokenMap['access_token'] as String?;
    if (googleIdToken == null && googleAccessToken == null) {
      throw const DesktopCloudException(
        code: 'missing-google-token',
        message: 'Google did not return an ID token.',
      );
    }

    final postBody = googleIdToken != null
        ? 'id_token=${Uri.encodeQueryComponent(googleIdToken)}&providerId=google.com'
        : 'access_token=${Uri.encodeQueryComponent(googleAccessToken!)}&providerId=google.com';

    final idpResp = await _http.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${Uri.encodeQueryComponent(apiKey)}',
      ),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'postBody': postBody,
        'requestUri': 'http://localhost',
        'returnIdpCredential': true,
        'returnSecureToken': true,
      }),
    );

    if (idpResp.statusCode != 200) {
      throw DesktopCloudException(
        code: 'firebase-idp-failed',
        message: _extractAuthError(idpResp.body, idpResp.statusCode),
        statusCode: idpResp.statusCode,
      );
    }

    final idpBody = jsonDecode(idpResp.body) as Map<String, dynamic>;
    final uid = idpBody['localId'] as String?;
    final idToken = idpBody['idToken'] as String?;
    final refreshToken = idpBody['refreshToken'] as String?;
    final expiresInSec =
        int.tryParse((idpBody['expiresIn'] ?? '3600').toString()) ?? 3600;
    final emailLabel =
        (idpBody['email'] ?? idpBody['displayName'] ?? 'Oneova Account').toString();

    if (uid == null || idToken == null || refreshToken == null) {
      throw const DesktopCloudException(
        code: 'idp-incomplete',
        message: 'Google sign-in succeeded but Firebase session was incomplete.',
      );
    }

    _uid = uid;
    _idToken = idToken;
    _refreshToken = refreshToken;
    _expiresAt = DateTime.now().add(Duration(seconds: expiresInSec));
    _isAccountUser = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefAuthUid, uid);
    await prefs.setString(_prefRefreshToken, refreshToken);
    await prefs.setBool(_prefIsAccount, true);
    await prefs.setString(_prefBioRefreshToken, refreshToken);
    await prefs.setString(_prefLastAccountLabel, emailLabel);
    return uid;
  }

  Future<String?> getBiometricQuickAccountLabel() async {
    final prefs = await SharedPreferences.getInstance();
    final bioToken = prefs.getString(_prefBioRefreshToken);
    if (bioToken == null || bioToken.isEmpty) return null;
    return prefs.getString(_prefLastAccountLabel);
  }

  Future<String> signInWithRememberedBiometricToken() async {
    final prefs = await SharedPreferences.getInstance();
    final bioToken = prefs.getString(_prefBioRefreshToken);
    if (bioToken == null || bioToken.isEmpty) {
      throw const DesktopCloudException(
        code: 'no-biometric-session',
        message: 'Sign in once with your password or Google to enable Touch ID.',
      );
    }
    await prefs.setBool(_prefIsAccount, true);
    await _refreshWithToken(bioToken, prefs);
    if (_refreshToken != null) {
      await prefs.setString(_prefBioRefreshToken, _refreshToken!);
    }
    return _uid!;
  }

  Future<void> setRememberedAccountLabel(String label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastAccountLabel, label);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final uri = Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${Uri.encodeQueryComponent(apiKey)}',
    );
    final resp = await _http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requestType': 'PASSWORD_RESET',
        'email': email.trim(),
      }),
    );
    if (resp.statusCode != 200) {
      throw DesktopCloudException(
        code: 'reset-failed',
        message: _extractAuthError(resp.body, resp.statusCode),
        statusCode: resp.statusCode,
      );
    }
  }

  /// Calls the `accountLookup` callable function used by `MainLoginScreen`
  /// on mobile to preview `displayName`, `username`, and `photoUrl`.
  Future<Map<String, dynamic>?> lookupAccount({
    String? phone,
    String? email,
  }) async {
    final uri = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/accountLookup',
    );
    final data = <String, dynamic>{
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (email != null && email.isNotEmpty) 'email': email.trim().toLowerCase(),
    };
    if (data.isEmpty) return null;

    try {
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (_idToken != null) {
        headers['Authorization'] = 'Bearer $_idToken';
      }
      final resp = await _http
          .post(uri, headers: headers, body: jsonEncode({'data': data}))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final result = (decoded['result'] ?? decoded['data']) as Map<String, dynamic>?;
      if (result != null && result['found'] == true) {
        return result;
      }
    } catch (e) {
      debugPrint('[DesktopCloud] accountLookup notice: $e');
    }
    return null;
  }

  /// Invokes an authenticated Gen 2 Firebase Callable Function over HTTPS,
  /// automatically attaching `Authorization: Bearer <idToken>` and retrying
  /// once on token expiration.
  Future<Map<String, dynamic>> callCallable(
    String functionName,
    Map<String, dynamic> data, {
    Duration timeout = const Duration(seconds: 65),
  }) async {
    final uri = Uri.parse(
      'https://us-central1-$projectId.cloudfunctions.net/$functionName',
    );
    final payload = jsonEncode({'data': data});
    final resp = await _authorizedRequest(
      (headers) => _http.post(uri, headers: headers, body: payload).timeout(timeout),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw DesktopCloudException(
        code: 'callable-failed',
        message: _extractCallableError(resp.body, resp.statusCode),
        statusCode: resp.statusCode,
      );
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = decoded['result'] ?? decoded['data'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{'value': raw};
  }

  Future<void> signOutAccount() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefRefreshToken);
    await prefs.setBool(_prefIsAccount, false);
    _idToken = null;
    _refreshToken = null;
    _uid = null;
    _expiresAt = null;
    _isAccountUser = false;
  }

  Future<String> getValidIdToken({bool forceRefresh = false}) async {
    if (forceRefresh) {
      _expiresAt = null;
    }
    await ensureAuthenticated();
    return _idToken!;
  }

  // ---------------------------------------------------------------------------
  // Firestore v1 REST CRUD & Streaming
  // ---------------------------------------------------------------------------

  Future<http.Response> _authorizedRequest(
    Future<http.Response> Function(Map<String, String> headers) send,
  ) async {
    var token = await getValidIdToken();
    var response = await send({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    });
    if (response.statusCode == 401) {
      token = await getValidIdToken(forceRefresh: true);
      response = await send({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      });
    }
    return response;
  }

  Future<void> setDocument(
    String docPath,
    Map<String, dynamic> data, {
    bool merge = false,
  }) async {
    final cleanPath = _cleanPath(docPath);
    final queryParams = <String, List<String>>{};
    if (merge && data.isNotEmpty) {
      queryParams['updateMask.fieldPaths'] =
          data.keys.map(_escapeFieldPath).toList();
    }
    final uri = _buildUri('$_documentsBaseUrl/$cleanPath', queryParams);
    final body = jsonEncode({'fields': _encodeMapFields(data)});

    final resp = await _authorizedRequest(
      (headers) => _http.patch(uri, headers: headers, body: body),
    );
    _ensureSuccess(resp, 'setDocument($cleanPath)');
  }

  Future<void> updateDocument(String docPath, Map<String, dynamic> data) async {
    if (data.isEmpty) return;
    final cleanPath = _cleanPath(docPath);
    final queryParams = <String, List<String>>{
      'updateMask.fieldPaths': data.keys.map(_escapeFieldPath).toList(),
      'currentDocument.exists': ['true'],
    };
    final uri = _buildUri('$_documentsBaseUrl/$cleanPath', queryParams);
    final body = jsonEncode({'fields': _encodeMapFields(data)});

    final resp = await _authorizedRequest(
      (headers) => _http.patch(uri, headers: headers, body: body),
    );
    _ensureSuccess(resp, 'updateDocument($cleanPath)');
  }

  Future<String> addDocument(
    String collectionPath,
    Map<String, dynamic> data,
  ) async {
    final cleanPath = _cleanPath(collectionPath);
    final uri = Uri.parse('$_documentsBaseUrl/$cleanPath');
    final body = jsonEncode({'fields': _encodeMapFields(data)});

    final resp = await _authorizedRequest(
      (headers) => _http.post(uri, headers: headers, body: body),
    );
    _ensureSuccess(resp, 'addDocument($cleanPath)');

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final name = (decoded['name'] ?? '').toString();
    return name.split('/').last;
  }

  Future<Map<String, dynamic>?> getDocument(String docPath) async {
    final cleanPath = _cleanPath(docPath);
    final uri = Uri.parse('$_documentsBaseUrl/$cleanPath');
    final resp = await _authorizedRequest(
      (headers) => _http.get(uri, headers: headers),
    );
    if (resp.statusCode == 404) return null;
    _ensureSuccess(resp, 'getDocument($cleanPath)');

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    return _decodeDocumentFields(decoded);
  }

  Future<List<DesktopRestDoc>> listDocuments(
    String collectionPath, {
    int pageSize = 200,
  }) async {
    final cleanPath = _cleanPath(collectionPath);
    // Firestore lists by document id (random for auto-ids), so a new doc can
    // land on any page. Follow nextPageToken so nothing past the first page
    // is missed — a missed offer meant the phone could never connect.
    const maxPages = 10;
    final out = <DesktopRestDoc>[];
    String? pageToken;
    for (var page = 0; page < maxPages; page++) {
      final tokenParam = pageToken == null
          ? ''
          : '&pageToken=${Uri.encodeQueryComponent(pageToken)}';
      final uri = Uri.parse(
        '$_documentsBaseUrl/$cleanPath?pageSize=$pageSize$tokenParam',
      );
      final resp = await _authorizedRequest(
        (headers) => _http.get(uri, headers: headers),
      );
      if (resp.statusCode == 404) return out;
      _ensureSuccess(resp, 'listDocuments($cleanPath)');

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawDocs = decoded['documents'] as List<dynamic>? ?? const [];
      for (final raw in rawDocs) {
        final docMap = Map<String, dynamic>.from(raw as Map);
        final name = (docMap['name'] ?? '').toString();
        out.add(DesktopRestDoc(
          id: name.split('/').last,
          data: _decodeDocumentFields(docMap),
          updateTime: docMap['updateTime']?.toString(),
        ));
      }
      pageToken = decoded['nextPageToken'] as String?;
      if (pageToken == null || pageToken.isEmpty) break;
    }
    return out;
  }

  Future<void> deleteDocument(String docPath) async {
    final cleanPath = _cleanPath(docPath);
    final uri = Uri.parse('$_documentsBaseUrl/$cleanPath');
    final resp = await _authorizedRequest(
      (headers) => _http.delete(uri, headers: headers),
    );
    if (resp.statusCode == 404) return;
    _ensureSuccess(resp, 'deleteDocument($cleanPath)');
  }

  final DesktopPollGate _pollGate = DesktopPollGate();
  final Map<String, DesktopCollectionPoller> _pollers = {};

  /// Polls [collectionPath] and emits its documents.
  ///
  /// Watchers of the same path share one poller, so the path is never read
  /// twice at once. Polls run every [interval] while the collection is
  /// changing (or while [keepFast] returns true) and slow down towards
  /// [idleInterval] (default 3 × [interval]) while it is quiet. Errors back
  /// off exponentially with jitter; quota errors pause every watcher of this
  /// client; permission-denied pauses the path until it is watched again.
  Stream<List<DesktopRestDoc>> watchCollection(
    String collectionPath, {
    Duration interval = const Duration(milliseconds: 900),
    Duration? idleInterval,
    bool Function()? keepFast,
    int pageSize = 200,
  }) {
    final cleanPath = _cleanPath(collectionPath);
    final key = '$cleanPath|$pageSize';
    var poller = _pollers[key];
    if (poller == null || poller.isDisposed) {
      poller = DesktopCollectionPoller(
        path: cleanPath,
        fetch: () => listDocuments(cleanPath, pageSize: pageSize),
        gate: _pollGate,
        onDispose: (p) {
          if (identical(_pollers[key], p)) _pollers.remove(key);
        },
      );
      _pollers[key] = poller;
    }
    return poller.watch(
      interval: interval,
      idleInterval: idleInterval,
      keepFast: keepFast,
    );
  }

  // ---------------------------------------------------------------------------
  // Encoding / Decoding Helpers
  // ---------------------------------------------------------------------------

  static String _cleanPath(String p) =>
      p.trim().replaceAll(RegExp(r'^/+|/+$'), '');

  static String _escapeFieldPath(String key) {
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      return key;
    }
    return '`${key.replaceAll('`', r'\`')}`';
  }

  static Uri _buildUri(String base, Map<String, List<String>> multiParams) {
    if (multiParams.isEmpty) return Uri.parse(base);
    final parts = <String>[];
    multiParams.forEach((key, values) {
      for (final val in values) {
        parts.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(val)}',
        );
      }
    });
    return Uri.parse('$base?${parts.join('&')}');
  }

  static Map<String, dynamic> _encodeMapFields(Map<String, dynamic> map) {
    final out = <String, dynamic>{};
    map.forEach((k, v) {
      out[k] = _encodeValue(v);
    });
    return out;
  }

  static Map<String, dynamic> _encodeValue(dynamic value) {
    if (value == null) return const {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': value.toString()};
    if (value is double) return {'doubleValue': value};
    if (value is num) return {'doubleValue': value.toDouble()};
    if (value is String) return {'stringValue': value};
    if (value is DateTime) {
      return {'timestampValue': value.toUtc().toIso8601String()};
    }
    if (value is Timestamp) {
      return {'timestampValue': value.toDate().toUtc().toIso8601String()};
    }
    if (value is List) {
      return {
        'arrayValue': {
          'values': value.map(_encodeValue).toList(),
        },
      };
    }
    if (value is Map) {
      final fields = <String, dynamic>{};
      value.forEach((k, v) {
        fields[k.toString()] = _encodeValue(v);
      });
      return {
        'mapValue': {'fields': fields},
      };
    }
    return {'stringValue': value.toString()};
  }

  static Map<String, dynamic> _decodeDocumentFields(Map<String, dynamic> doc) {
    final rawFields = doc['fields'] as Map<String, dynamic>?;
    if (rawFields == null) return <String, dynamic>{};
    final out = <String, dynamic>{};
    rawFields.forEach((k, v) {
      if (v is Map) {
        out[k] = _decodeValue(Map<String, dynamic>.from(v));
      }
    });
    return out;
  }

  static dynamic _decodeValue(Map<String, dynamic> raw) {
    if (raw.containsKey('nullValue')) return null;
    if (raw.containsKey('booleanValue')) return raw['booleanValue'] as bool;
    if (raw.containsKey('integerValue')) {
      return int.tryParse(raw['integerValue'].toString()) ?? 0;
    }
    if (raw.containsKey('doubleValue')) {
      return (raw['doubleValue'] as num).toDouble();
    }
    if (raw.containsKey('stringValue')) return raw['stringValue'] as String;
    if (raw.containsKey('timestampValue')) {
      final parsed = DateTime.tryParse(raw['timestampValue'].toString());
      return parsed != null ? Timestamp.fromDate(parsed) : null;
    }
    if (raw.containsKey('arrayValue')) {
      final arr = raw['arrayValue'] as Map<String, dynamic>?;
      final values = arr?['values'] as List<dynamic>? ?? const [];
      return values
          .map((e) => _decodeValue(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    if (raw.containsKey('mapValue')) {
      final mapVal = raw['mapValue'] as Map<String, dynamic>?;
      return _decodeDocumentFields(mapVal ?? const {});
    }
    return null;
  }

  static void _ensureSuccess(http.Response resp, String op) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return;
    String code = 'firestore-error';
    String message = '$op failed with HTTP ${resp.statusCode}';
    try {
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final err = decoded['error'] as Map<String, dynamic>?;
      if (err != null) {
        final status = (err['status'] ?? '').toString();
        if (status == 'PERMISSION_DENIED' || resp.statusCode == 403) {
          code = 'permission-denied';
        } else if (status == 'NOT_FOUND' || resp.statusCode == 404) {
          code = 'not-found';
        } else if (status == 'UNAUTHENTICATED' || resp.statusCode == 401) {
          code = 'unauthenticated';
        } else if (status == 'RESOURCE_EXHAUSTED' || resp.statusCode == 429) {
          code = 'resource-exhausted';
        } else if (status == 'UNAVAILABLE' || resp.statusCode == 503) {
          code = 'unavailable';
        }
        message = (err['message'] ?? message).toString();
      }
    } catch (_) {}
    throw DesktopCloudException(
      code: code,
      message: message,
      statusCode: resp.statusCode,
    );
  }

  static String _extractAuthError(String rawBody, int statusCode) {
    try {
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      final err = decoded['error'] as Map<String, dynamic>?;
      final rawMsg = (err?['message'] ?? '').toString();
      switch (rawMsg) {
        case 'INVALID_LOGIN_CREDENTIALS':
        case 'INVALID_PASSWORD':
        case 'EMAIL_NOT_FOUND':
          return 'Incorrect email or password.';
        case 'USER_DISABLED':
          return 'This account has been disabled.';
        case 'TOO_MANY_ATTEMPTS_TRY_LATER':
          return 'Too many attempts. Please wait a moment and try again.';
        default:
          if (rawMsg.isNotEmpty) return rawMsg;
      }
    } catch (_) {}
    return 'Authentication failed (HTTP $statusCode).';
  }

  static String _extractCallableError(String rawBody, int statusCode) {
    try {
      final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
      final err = decoded['error'] as Map<String, dynamic>?;
      final msg = (err?['message'] ?? '').toString();
      if (msg.isNotEmpty) return msg;
    } catch (_) {}
    return 'Bootstrap request failed (HTTP $statusCode).';
  }

  static String _generateHexSecret(int byteLength) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => rng.nextInt(256));
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _generatePkceVerifier() {
    const charset =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rng = Random.secure();
    return List.generate(64, (_) => charset[rng.nextInt(charset.length)]).join();
  }
}
