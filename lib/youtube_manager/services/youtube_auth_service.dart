import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/youtube/v3.dart' as youtube;
import 'package:googleapis/youtubeanalytics/v2.dart' as analytics;
import 'package:http/http.dart' as http;

/// Represents a connected YouTube Channel
class YouTubeChannel {
  final String id;
  final String title;
  final String thumbnailUrl;
  final int subscriberCount;

  YouTubeChannel({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.subscriberCount,
  });
}

/// Service to handle Google OAuth 2.0 and YouTube API scopes (google_sign_in v7)
class YouTubeAuthService extends Notifier<GoogleSignInAccount?> {
  // google_sign_in v7: use the singleton GoogleSignIn.instance
  GoogleSignIn get _googleSignIn => GoogleSignIn.instance;

  static const List<String> _ytScopes = [
    youtube.YouTubeApi.youtubeScope,
    youtube.YouTubeApi.youtubeReadonlyScope,
    youtube.YouTubeApi.youtubeUploadScope,
    youtube.YouTubeApi.youtubeForceSslScope,
    youtube.YouTubeApi.youtubepartnerScope,
    analytics.YouTubeAnalyticsApi.ytAnalyticsReadonlyScope,
  ];

  final _secureStorage = const FlutterSecureStorage();
  static const _activeChannelKey = 'active_yt_channel_id';

  @override
  GoogleSignInAccount? build() {
    _initAuth();
    return null;
  }

  bool get isAuthenticated => state != null;

  Future<void> _initAuth() async {
    // v7: subscribe to auth state changes via the events stream
    _googleSignIn.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn) {
        state = event.user;
      } else if (event is GoogleSignInAuthenticationEventSignOut) {
        state = null;
      }
    });
  }

  /// Initiates the interactive OAuth flow (v7: authenticate())
  Future<bool> signIn() async {
    try {
      final account = await _googleSignIn.authenticate(
        scopeHint: _ytScopes,
      );

      // Force the authorization flow immediately so the user sees the YouTube scopes consent screen
      try {
        await account.authorizationClient.authorizeScopes(_ytScopes);
      } catch (e) {
        debugPrint('YouTubeAuthService: User denied scopes or error occurred: $e');
        await signOut(); // Prevent half-connected state
        return false;
      }

      state = account;
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      debugPrint('Error signing in to YouTube: $e');
      return false;
    } catch (e) {
      debugPrint('Error signing in to YouTube: $e');
      return false;
    }
  }

  /// Signs the user out
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _secureStorage.delete(key: _activeChannelKey);
  }

  /// Retrieves the authenticated HTTP Client for YouTube Google APIs (v7)
  Future<http.Client?> getAuthClient() async {
    final account = state;
    if (account == null) return null;
    try {
      // v7: use authorizationClient.authorizeScopes() to get the access token
      final authorization =
          await account.authorizationClient.authorizeScopes(_ytScopes).timeout(const Duration(seconds: 15));
      final headers = <String, String>{
        'Authorization': 'Bearer ${authorization.accessToken}',
        'X-Goog-AuthUser': '0',
      };
      return _GoogleAuthClient(headers);
    } catch (e) {
      debugPrint('YouTubeAuthService: Failed to get auth client — $e');
      return null;
    }
  }

  /// Extracts the access token string directly
  Future<String?> getAccessToken() async {
    final account = state;
    if (account == null) return null;
    try {
      final authorization = await account.authorizationClient.authorizeScopes(_ytScopes).timeout(const Duration(seconds: 15));
      return authorization.accessToken;
    } catch (e) {
      debugPrint('YouTubeAuthService: Failed to get access token — $e');
      return null;
    }
  }

  /// Saves the currently selected channel ID
  Future<void> saveActiveChannelId(String channelId) async {
    await _secureStorage.write(key: _activeChannelKey, value: channelId);
  }

  /// Gets the currently selected channel ID
  Future<String?> getActiveChannelId() async {
    return await _secureStorage.read(key: _activeChannelKey);
  }
}

/// Simple HTTP client that injects Google authorization headers.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request..headers.addAll(_headers));
  }
}

final youtubeAuthProvider =
    NotifierProvider<YouTubeAuthService, GoogleSignInAccount?>(
        () => YouTubeAuthService());

final activeChannelIdProvider = FutureProvider<String?>((ref) async {
  return await ref.watch(youtubeAuthProvider.notifier).getActiveChannelId();
});



