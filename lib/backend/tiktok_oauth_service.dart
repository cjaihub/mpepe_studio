import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────
//  Data Models
// ─────────────────────────────────────────────

class TikTokAccount {
  final String openId;
  final String unionId;
  final String displayName;
  final String? avatarUrl;

  const TikTokAccount({
    required this.openId,
    required this.unionId,
    required this.displayName,
    this.avatarUrl,
  });

  factory TikTokAccount.fromJson(Map<String, dynamic> json) {
    return TikTokAccount(
      openId: json['open_id'] ?? '',
      unionId: json['union_id'] ?? '',
      displayName: json['display_name'] ?? 'TikTok User',
      avatarUrl: json['avatar_url'],
    );
  }
}

class TikTokOAuthState {
  final bool isLoading;
  final String? statusMessage;
  final String? accessToken;
  final TikTokAccount? account;
  final bool isConnected;
  final String? error;

  const TikTokOAuthState({
    this.isLoading = false,
    this.statusMessage,
    this.accessToken,
    this.account,
    this.isConnected = false,
    this.error,
  });

  TikTokOAuthState copyWith({
    bool? isLoading,
    String? statusMessage,
    String? accessToken,
    TikTokAccount? account,
    bool? isConnected,
    String? error,
  }) {
    return TikTokOAuthState(
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      accessToken: accessToken ?? this.accessToken,
      account: account ?? this.account,
      isConnected: isConnected ?? this.isConnected,
      error: error,
    );
  }
}

// ─────────────────────────────────────────────
//  Service
// ─────────────────────────────────────────────

class TikTokOAuthService extends Notifier<TikTokOAuthState> {
  final _secureStorage = const FlutterSecureStorage();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String _authUrl = 'https://www.tiktok.com/v2/auth/authorize/';
  static const String _userInfoUrl = 'https://open.tiktokapis.com/v2/user/info/';

  String get _clientKey => dotenv.env['TIKTOK_CLIENT_KEY'] ?? '';
  String get _redirectUri => dotenv.env['TIKTOK_REDIRECT_URI'] ?? 'oneova://tiktok-callback';
  String get _userId => _auth.currentUser?.uid ?? '';

  Completer<String?>? _oauthCompleter;

  @override
  TikTokOAuthState build() => const TikTokOAuthState();

  // ── Step 1: Launch OAuth flow ──────────────────────────────────────────

  Future<void> startOAuth() async {
    if (_clientKey.isEmpty) {
      state = state.copyWith(
        error: 'TIKTOK_CLIENT_KEY is not configured. Please add it to your .env file.',
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      statusMessage: 'Opening TikTok…',
      error: null,
    );

    // TikTok v2 scopes
    final scopeString = 'user.info.basic,video.list';
    final csrfState = 'oneova_tiktok_${DateTime.now().millisecondsSinceEpoch}';

    final uri = Uri.parse(_authUrl).replace(queryParameters: {
      'client_key': _clientKey,
      'response_type': 'code',
      'scope': scopeString,
      'redirect_uri': _redirectUri,
      'state': csrfState,
    });

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not open TikTok. Please try again.',
        );
        return;
      }

      _oauthCompleter = Completer<String?>();
      state = state.copyWith(statusMessage: 'Waiting for you to authorize…');

      final code = await _oauthCompleter!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () => null,
      );

      if (code == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Authorization timed out. Please try again.',
        );
        return;
      }

      await _exchangeCodeForToken(code);
    } catch (e) {
      debugPrint('TikTok OAuth error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred: ${e.toString()}',
      );
    }
  }

  // ── Step 2: Receive deep-link callback ────────────────────────────────

  void handleOAuthCallback(Uri callbackUri) {
    final code = callbackUri.queryParameters['code'];
    final error = callbackUri.queryParameters['errCode']; // TikTok passes errCode instead of error sometimes

    if (code == null || error != null) {
      _oauthCompleter?.complete(null);
      state = state.copyWith(
        isLoading: false,
        error: 'Authorization denied or failed: ${error ?? "No code received"}',
      );
      return;
    }

    _oauthCompleter?.complete(code);
  }

  // ── Step 3: Exchange code for long-lived token ─────────────────────────

  Future<void> _exchangeCodeForToken(String code) async {
    state = state.copyWith(statusMessage: 'Exchanging secure tokens…');

    try {
      // The client secret stays in Secret Manager; the exchange runs server-side.
      final result = await FirebaseFunctions.instance
          .httpsCallable('tiktokExchangeCode')
          .call<Map<String, dynamic>>({'code': code});
      final data = Map<String, dynamic>.from(result.data);
      final accessToken = data['access_token'] as String?;

      if (accessToken == null) {
        throw Exception('No access_token in response');
      }

      state = state.copyWith(
        accessToken: accessToken,
        statusMessage: 'Loading your TikTok account…',
      );

      await _fetchUserInfo(accessToken);
    } catch (e) {
      debugPrint('TikTok token exchange error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to exchange token: ${e.toString()}',
      );
    }
  }

  // ── Step 4: Fetch user account info ─────────────────────────────

  Future<void> _fetchUserInfo(String token) async {
    try {
      final response = await http.get(
        Uri.parse(_userInfoUrl).replace(queryParameters: {
          'fields': 'open_id,union_id,avatar_url,display_name',
        }),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch user info: ${response.body}');
      }

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final data = responseData['data'] as Map<String, dynamic>?;
      
      if (data == null || data['user'] == null) {
          throw Exception('User data not found in response');
      }
      
      final account = TikTokAccount.fromJson(data['user']);

      state = state.copyWith(
        account: account,
        statusMessage: null,
      );
    } catch (e) {
      debugPrint('TikTok fetch user error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load your account: ${e.toString()}',
      );
    }
  }

  // ── Step 5: Confirm connection ─────────────────────────────────────────

  Future<void> confirmConnection() async {
    final account = state.account;
    final token = state.accessToken;

    if (account == null || token == null || _userId.isEmpty) return;

    state = state.copyWith(isLoading: true, statusMessage: 'Saving connection…');

    try {
      final tokenKey = 'tiktok_token_${account.openId}';
      await _secureStorage.write(key: tokenKey, value: token);

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .doc('tiktok')
          .set({
        'platform': 'tiktok',
        'accountName': account.displayName,
        'openId': account.openId,
        'unionId': account.unionId,
        'profilePictureUrl': account.avatarUrl,
        'tokenKey': tokenKey,
        'connectedAt': FieldValue.serverTimestamp(),
      });

      state = state.copyWith(
        isLoading: false,
        isConnected: true,
        statusMessage: null,
      );
    } catch (e) {
      debugPrint('Confirm connection error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to save connection: ${e.toString()}',
      );
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .doc('tiktok')
          .get();

      final tokenKey = doc.data()?['tokenKey'] as String?;
      if (tokenKey != null) {
        await _secureStorage.delete(key: tokenKey);
      }

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .doc('tiktok')
          .delete();

      state = const TikTokOAuthState();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
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
