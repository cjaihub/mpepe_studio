import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:http/http.dart' as http;

import '../../backend/connections/google_services.dart';

/// Google API access for Ova (Gmail, YouTube) through google_sign_in v7.
/// The first use shows Google's own consent screen for exactly these scopes;
/// later calls get a fresh token silently.
class OvaGoogleAccess {
  static const gmailScopes = [
    gmail.GmailApi.gmailReadonlyScope,
    gmail.GmailApi.gmailSendScope,
    gmail.GmailApi.gmailModifyScope,
  ];
  static const youtubeScopes = [
    // Full YouTube access for reading, uploading, comment replies, live streaming and analytics
    yt.YouTubeApi.youtubeScope,
    yt.YouTubeApi.youtubeUploadScope,
    yt.YouTubeApi.youtubeReadonlyScope,
    yt.YouTubeApi.youtubeForceSslScope,
    yt.YouTubeApi.youtubepartnerScope,
    yt.YouTubeApi.youtubepartnerChannelAuditScope,
    yt.YouTubeApi.youtubeChannelMembershipsCreatorScope,
    'https://www.googleapis.com/auth/yt-analytics.readonly',
    'https://www.googleapis.com/auth/yt-analytics-monetary.readonly',
  ];

  /// Returns an authorised client, or null if the user declined.
  static Future<http.Client?> client(List<String> scopes, {bool prompt = true}) async {
    // YouTube turned on in Google services: use the server-held link, which
    // works in the background and keeps no long-lived token on the phone.
    if (identical(scopes, youtubeScopes)) {
      final server = await GoogleServices.clientFor(GoogleService.youtube);
      if (server != null) return server;
    }
    try {
      final headers = await GoogleSignIn.instance.authorizationClient.authorizationHeaders(scopes, promptIfNecessary: prompt);
      if (headers == null) return null;
      return _HeaderClient(headers);
    } on GoogleSignInException catch (e) {
      debugPrint('[OvaGoogleAccess] ${e.code}: ${e.description}');
      return null;
    } catch (e) {
      debugPrint('[OvaGoogleAccess] $e');
      return null;
    }
  }
}

class _HeaderClient extends http.BaseClient {
  final Map<String, String> headers;
  final http.Client _inner = http.Client();
  _HeaderClient(this.headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request..headers.addAll(headers));

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
