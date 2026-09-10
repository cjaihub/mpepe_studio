import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────
//  Enums
// ─────────────────────────────────────────────

enum MetaApp {
  facebook,
  instagram,
  whatsapp;

  String get displayName {
    switch (this) {
      case MetaApp.facebook:
        return 'Facebook';
      case MetaApp.instagram:
        return 'Instagram';
      case MetaApp.whatsapp:
        return 'WhatsApp Business';
    }
  }

  String get logoAsset {
    switch (this) {
      case MetaApp.facebook:
        return 'assets/logos/facebook.svg';
      case MetaApp.instagram:
        return 'assets/logos/instagram.svg';
      case MetaApp.whatsapp:
        return 'assets/logos/whatsapp.svg';
    }
  }

  /// OAuth scopes required per platform
  List<String> get scopes {
    switch (this) {
      case MetaApp.facebook:
        return [
          'pages_read_engagement',
          'pages_manage_posts',
          'pages_read_user_content',
          'pages_show_list',
          'public_profile',
          'email',
        ];
      case MetaApp.instagram:
        return [
          'instagram_basic',
          'instagram_content_publish',
          'instagram_manage_comments',
          'instagram_manage_insights',
          'pages_read_engagement',
          'pages_show_list',
          'public_profile',
        ];
      case MetaApp.whatsapp:
        return [
          'whatsapp_business_management',
          'whatsapp_business_messaging',
        ];
    }
  }

  static MetaApp fromString(String value) {
    return MetaApp.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => MetaApp.facebook,
    );
  }
}

// ─────────────────────────────────────────────
//  Data Models
// ─────────────────────────────────────────────

class MetaPage {
  final String id;
  final String name;
  final String? category;
  final String? pictureUrl;
  final int? fanCount;
  final String? accessToken;
  final String? instagramBusinessAccountId;

  const MetaPage({
    required this.id,
    required this.name,
    this.category,
    this.pictureUrl,
    this.fanCount,
    this.accessToken,
    this.instagramBusinessAccountId,
  });

  factory MetaPage.fromJson(Map<String, dynamic> json) {
    return MetaPage(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'],
      pictureUrl: json['picture']?['data']?['url'],
      fanCount: json['fan_count'],
      accessToken: json['access_token'],
      instagramBusinessAccountId: json['instagram_business_account']?['id'],
    );
  }
}

class MetaOAuthState {
  final bool isLoading;
  final String? statusMessage;
  final String? userAccessToken;
  final List<MetaPage> availablePages;
  final MetaPage? selectedPage;
  final bool isConnected;
  final String? error;

  const MetaOAuthState({
    this.isLoading = false,
    this.statusMessage,
    this.userAccessToken,
    this.availablePages = const [],
    this.selectedPage,
    this.isConnected = false,
    this.error,
  });

  MetaOAuthState copyWith({
    bool? isLoading,
    String? statusMessage,
    String? userAccessToken,
    List<MetaPage>? availablePages,
    MetaPage? selectedPage,
    bool? isConnected,
    String? error,
  }) {
    return MetaOAuthState(
      isLoading: isLoading ?? this.isLoading,
      statusMessage: statusMessage ?? this.statusMessage,
      userAccessToken: userAccessToken ?? this.userAccessToken,
      availablePages: availablePages ?? this.availablePages,
      selectedPage: selectedPage ?? this.selectedPage,
      isConnected: isConnected ?? this.isConnected,
      error: error,
    );
  }
}

// ─────────────────────────────────────────────
//  Service
// ─────────────────────────────────────────────

class MetaOAuthService extends Notifier<MetaOAuthState> {
  final _secureStorage = const FlutterSecureStorage();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String _metaGraphBase = 'https://graph.facebook.com/v22.0';
  static const String _metaOAuthBase =
      'https://www.facebook.com/v22.0/dialog/oauth';
  static const String _metaTokenBase =
      'https://graph.facebook.com/v22.0/oauth/access_token';

  String get _appId => dotenv.env['META_APP_ID'] ?? '';
  String get _appSecret => dotenv.env['META_APP_SECRET'] ?? '';
  String get _redirectUri =>
      dotenv.env['META_REDIRECT_URI'] ?? 'mstudio://meta-callback';
  String get _userId => _auth.currentUser?.uid ?? '';

  /// Completer used to receive the OAuth code from the deep-link callback.
  Completer<String?>? _oauthCompleter;

  @override
  MetaOAuthState build() => const MetaOAuthState();

  // ── Step 1: Launch OAuth flow ──────────────────────────────────────────

  Future<void> startOAuth(MetaApp app) async {
    if (_appId.isEmpty) {
      state = state.copyWith(
        error:
            'META_APP_ID is not configured. Please add it to your .env file.',
        isLoading: false,
      );
      return;
    }

    state = state.copyWith(
      isLoading: true,
      statusMessage: 'Opening ${app.displayName}…',
      error: null,
    );

    final scopeString = app.scopes.join(',');
    final uri = Uri.parse(_metaOAuthBase).replace(queryParameters: {
      'client_id': _appId,
      'redirect_uri': _redirectUri,
      'scope': scopeString,
      'response_type': 'code',
      'state': app.name,
    });

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        state = state.copyWith(
          isLoading: false,
          error: 'Could not open ${app.displayName}. Please try again.',
        );
        return;
      }

      _oauthCompleter = Completer<String?>();
      state = state.copyWith(statusMessage: 'Waiting for you to sign in…');

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

      await _exchangeCodeForToken(code, app);
    } catch (e) {
      debugPrint('Meta OAuth error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred: ${e.toString()}',
      );
    }
  }

  // ── Step 2: Receive deep-link callback ────────────────────────────────

  /// Called from the app's deep-link handler when
  /// `mstudio://meta-callback?code=...` fires.
  void handleOAuthCallback(Uri callbackUri) {
    final code = callbackUri.queryParameters['code'];
    final error = callbackUri.queryParameters['error'];

    if (error != null) {
      _oauthCompleter?.complete(null);
      state = state.copyWith(
        isLoading: false,
        error: 'Authorization denied: $error',
      );
      return;
    }

    _oauthCompleter?.complete(code);
  }

  // ── Step 3: Exchange code for long-lived token ─────────────────────────

  Future<void> _exchangeCodeForToken(String code, MetaApp app) async {
    state = state.copyWith(statusMessage: 'Exchanging secure tokens…');

    try {
      // Short-lived token exchange
      final shortTokenResponse = await http.get(
        Uri.parse(_metaTokenBase).replace(queryParameters: {
          'client_id': _appId,
          'client_secret': _appSecret,
          'redirect_uri': _redirectUri,
          'code': code,
        }),
      );

      if (shortTokenResponse.statusCode != 200) {
        throw Exception('Token exchange failed: ${shortTokenResponse.body}');
      }

      final shortTokenData =
          jsonDecode(shortTokenResponse.body) as Map<String, dynamic>;
      final shortToken = shortTokenData['access_token'] as String?;

      if (shortToken == null) {
        throw Exception('No access_token in response');
      }

      // Exchange for long-lived token (60-day)
      final longTokenResponse = await http.get(
        Uri.parse(_metaTokenBase).replace(queryParameters: {
          'grant_type': 'fb_exchange_token',
          'client_id': _appId,
          'client_secret': _appSecret,
          'fb_exchange_token': shortToken,
        }),
      );

      if (longTokenResponse.statusCode != 200) {
        throw Exception(
            'Long-lived token exchange failed: ${longTokenResponse.body}');
      }

      final longTokenData =
          jsonDecode(longTokenResponse.body) as Map<String, dynamic>;
      final longToken = longTokenData['access_token'] as String?;

      if (longToken == null) {
        throw Exception('No long-lived access_token in response');
      }

      state = state.copyWith(
        userAccessToken: longToken,
        statusMessage: 'Loading your accounts…',
      );

      await _fetchPages(longToken, app);
    } catch (e) {
      debugPrint('Token exchange error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to exchange token: ${e.toString()}',
      );
    }
  }

  // ── Step 4: Fetch user's pages / accounts ─────────────────────────────

  Future<void> _fetchPages(String userToken, MetaApp app) async {
    try {
      final fields = app == MetaApp.instagram
          ? 'id,name,category,picture,fan_count,access_token,instagram_business_account'
          : 'id,name,category,picture,fan_count,access_token';

      final response = await http.get(
        Uri.parse('$_metaGraphBase/me/accounts').replace(queryParameters: {
          'access_token': userToken,
          'fields': fields,
          'limit': '20',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch accounts: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pagesData = (data['data'] as List<dynamic>?) ?? [];
      final pages = pagesData
          .map((p) => MetaPage.fromJson(p as Map<String, dynamic>))
          .toList();

      // For Instagram: filter only pages that have a linked IG Business Account
      final filteredPages = app == MetaApp.instagram
          ? pages
              .where((p) => p.instagramBusinessAccountId != null)
              .toList()
          : pages;

      state = state.copyWith(
        isLoading: false,
        availablePages: filteredPages,
        statusMessage: null,
      );
    } catch (e) {
      debugPrint('Fetch pages error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Could not load your accounts: ${e.toString()}',
      );
    }
  }

  // ── Step 5: Select a page ─────────────────────────────────────────────

  void selectPage(MetaPage page) {
    state = state.copyWith(selectedPage: page);
  }

  // ── Step 6: Confirm connection ─────────────────────────────────────────

  Future<void> confirmConnection(MetaApp app, {String niche = 'General/Other'}) async {
    final page = state.selectedPage;
    final userToken = state.userAccessToken;

    if (page == null || userToken == null || _userId.isEmpty) return;

    state = state.copyWith(isLoading: true, statusMessage: 'Saving connection…');

    try {
      // Store page access token securely — NEVER in Firestore
      final tokenKey = 'meta_token_${app.name}_${page.id}';
      await _secureStorage.write(
          key: tokenKey, value: page.accessToken ?? userToken);

      // Determine the actual account ID to store
      final accountId = app == MetaApp.instagram
          ? (page.instagramBusinessAccountId ?? page.id)
          : page.id;

      // Write minimal, non-sensitive data to Firestore
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .doc(app.name)
          .set({
        'platform': app.name,
        'accountName': page.name,
        'pageId': accountId,
        'profilePictureUrl': page.pictureUrl,
        'followerCount': page.fanCount,
        'tokenKey': tokenKey,
        'niche': niche,
        'connectedAt': FieldValue.serverTimestamp(),
        'tokenExpiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 60)),
        ),
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

  Future<void> disconnect(MetaApp app) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .doc(app.name)
          .get();

      final tokenKey = doc.data()?['tokenKey'] as String?;
      if (tokenKey != null) {
        await _secureStorage.delete(key: tokenKey);
      }

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('social_connections')
          .doc(app.name)
          .delete();

      state = const MetaOAuthState();
    } catch (e) {
      debugPrint('Disconnect error: $e');
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────

  void reset() {
    _oauthCompleter = null;
    state = const MetaOAuthState();
  }
}

// ─────────────────────────────────────────────
//  Providers
// ─────────────────────────────────────────────

final metaOAuthProvider =
    NotifierProvider<MetaOAuthService, MetaOAuthState>(MetaOAuthService.new);

/// Stream that tells you if a given MetaApp is currently connected.
final metaConnectionStatusProvider =
    StreamProvider.family<Map<String, dynamic>?, MetaApp>((ref, app) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('social_connections')
      .doc(app.name)
      .snapshots()
      .map((snap) => snap.exists ? snap.data() : null);
});
