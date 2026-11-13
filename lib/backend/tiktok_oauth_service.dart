import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────
//  Data Models
// ─────────────────────────────────────────────

class TikTokAccount {
  final String openId;
  final String unionId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final String? profileUrl;
  final bool isVerified;
  final int followerCount;
  final int followingCount;
  final int likesCount;
  final int videoCount;

  const TikTokAccount({
    required this.openId,
    required this.unionId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.bio,
    this.profileUrl,
    this.isVerified = false,
    this.followerCount = 0,
    this.followingCount = 0,
    this.likesCount = 0,
    this.videoCount = 0,
  });

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// From the server's profile shape (functions/src/tiktokOAuth.ts).
  factory TikTokAccount.fromJson(Map<String, dynamic> json) {
    return TikTokAccount(
      openId: json['openId']?.toString() ?? '',
      unionId: json['unionId']?.toString() ?? '',
      displayName: _str(json['displayName']) ?? 'TikTok user',
      username: _str(json['username']),
      avatarUrl: _str(json['avatarUrl']),
      bio: _str(json['bio']),
      profileUrl: _str(json['profileUrl']),
      isVerified: json['isVerified'] == true,
      followerCount: _int(json['followerCount']),
      followingCount: _int(json['followingCount']),
      likesCount: _int(json['likesCount']),
      videoCount: _int(json['videoCount']),
    );
  }
}

class TikTokOAuthState {
  final bool isLoading;
  final String? statusMessage;
  final TikTokAccount? account;
  final bool isConnected;
  final String? error;

  const TikTokOAuthState({
    this.isLoading = false,
    this.statusMessage,
    this.account,
    this.isConnected = false,
    this.error,
  });

  TikTokOAuthState copyWith({
    bool? isLoading,
    String? statusMessage,
    TikTokAccount? account,
    bool? isConnected,
    String? error,
  }) {
    return TikTokOAuthState(
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      account: account ?? this.account,
      isConnected: isConnected ?? this.isConnected,
      error: error,
    );
  }
}

// ─────────────────────────────────────────────
//  Service
// ─────────────────────────────────────────────

/// TikTok Login Kit. The app only opens TikTok's consent page and passes the
/// one-time code to `tiktokExchangeCode`; the tokens stay on the server.
class TikTokOAuthService extends Notifier<TikTokOAuthState> {
  static const String _authUrl = 'https://www.tiktok.com/v2/auth/authorize/';

  /// Everything Oneova uses: sign-in, profile + stats, the creator's videos,
  /// and posting (draft or direct).
  static const List<String> scopes = [
    'user.info.basic',
    'user.info.profile',
    'user.info.stats',
    'video.list',
    'video.upload',
    'video.publish',
  ];

  String get _clientKey => dotenv.env['TIKTOK_CLIENT_KEY'] ?? '';
  // TikTok only redirects to HTTPS; public/tiktok-callback.html hands the code
  // on to oneova://tiktok-callback. Must match the function's redirect URI.
  String get _redirectUri =>
      dotenv.env['TIKTOK_REDIRECT_URI'] ?? 'https://oneova.web.app/tiktok-callback';
  String? _csrfState;

  Completer<String?>? _oauthCompleter;

  @override
  TikTokOAuthState build() => const TikTokOAuthState();

  // ── Step 1: Launch OAuth flow ──────────────────────────────────────────

  Future<void> startOAuth() async {
    if (_clientKey.isEmpty) {
      state = state.copyWith(error: 'TikTok is not set up in this build.', isLoading: false);
      return;
    }

    state = state.copyWith(isLoading: true, statusMessage: 'Opening TikTok…', error: null);

    final csrfState = 'oneova_tiktok_${DateTime.now().microsecondsSinceEpoch}';
    _csrfState = csrfState;

    final uri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_key': _clientKey,
      'response_type': 'code',
      'scope': scopes.join(','),
      'redirect_uri': _redirectUri,
      'state': csrfState,
    });

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        state = state.copyWith(isLoading: false, error: 'Could not open TikTok. Please try again.');
        return;
      }

      _oauthCompleter = Completer<String?>();
      state = state.copyWith(statusMessage: 'Waiting for you to authorize…');

      final code = await _oauthCompleter!.future.timeout(const Duration(minutes: 5), onTimeout: () => null);
      if (code == null) {
        if (state.error == null) {
          state = state.copyWith(isLoading: false, error: 'Authorization timed out. Please try again.');
        }
        return;
      }

      await _exchangeCode(code);
    } catch (e) {
      debugPrint('TikTok OAuth error: $e');
      state = state.copyWith(isLoading: false, error: 'Something went wrong. Please try again.');
    }
  }

  // ── Step 2: Receive deep-link callback ────────────────────────────────

  void handleOAuthCallback(Uri callbackUri) {
    final returnedState = callbackUri.queryParameters['state'];
    if (_csrfState != null && returnedState != _csrfState) {
      debugPrint('TikTok OAuth: state mismatch, callback ignored');
      return;
    }
    final code = callbackUri.queryParameters['code'];
    final error = callbackUri.queryParameters['error'] ?? callbackUri.queryParameters['errCode'];

    if (code == null || error != null) {
      state = state.copyWith(isLoading: false, error: 'TikTok sign-in was cancelled.');
      _oauthCompleter?.complete(null);
      return;
    }

    _oauthCompleter?.complete(code);
  }

  // ── Step 3: Server exchanges the code and saves the connection ─────────

  Future<void> _exchangeCode(String code) async {
    state = state.copyWith(statusMessage: 'Connecting your TikTok account…');
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('tiktokExchangeCode')
          .call<Map<String, dynamic>>({'code': code});
      final data = Map<String, dynamic>.from(result.data);
      final account = TikTokAccount.fromJson(Map<String, dynamic>.from(data['account'] as Map));
      state = state.copyWith(account: account, statusMessage: null);
    } on FirebaseFunctionsException catch (e) {
      state = state.copyWith(isLoading: false, error: e.message ?? 'TikTok sign-in failed.');
    } catch (e) {
      debugPrint('TikTok exchange error: $e');
      state = state.copyWith(isLoading: false, error: 'TikTok sign-in failed. Please try again.');
    }
  }

  // ── Step 4: Confirm (the server already saved the connection) ──────────

  Future<void> confirmConnection() async {
    if (state.account == null) return;
    state = state.copyWith(isLoading: false, isConnected: true, statusMessage: null);
  }

  // ── Disconnect ─────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    try {
      await FirebaseFunctions.instance.httpsCallable('tiktokDisconnect').call<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('TikTok disconnect error: $e');
    }
    state = const TikTokOAuthState();
  }

  // ── Reset ─────────────────────────────────────────────────────────────

  void reset() {
    _oauthCompleter = null;
    state = const TikTokOAuthState();
  }
}

// ─────────────────────────────────────────────
//  Providers
// ─────────────────────────────────────────────

final tiktokOAuthProvider =
    NotifierProvider<TikTokOAuthService, TikTokOAuthState>(TikTokOAuthService.new);

final tiktokConnectionStatusProvider =
    StreamProvider<Map<String, dynamic>?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('social_connections')
      .doc('tiktok')
      .snapshots()
      .map((snap) => snap.exists ? snap.data() : null);
});
