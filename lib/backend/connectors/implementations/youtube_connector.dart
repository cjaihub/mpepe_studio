import 'package:oneova/backend/connectors/core/platform_connector.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';

class YouTubeQuotaException implements Exception {
  final String message;
  YouTubeQuotaException(this.message);
  @override
  String toString() => 'YouTubeQuotaException: $message';
}

class YouTubeConnector extends PlatformConnector {
  YouTubeConnector() : super('YouTube');

  @override
  Future<void> connect() async {
    // Initiate Google OAuth 2.0 flow for YouTube Data API v3
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload) async {
    // Validate scopes: youtube.readonly, youtube.upload, youtube.force-ssl (for comments)
    final scopes = List<String>.from(authPayload['scopes'] ?? []);
    if (!scopes.contains('https://www.googleapis.com/auth/youtube.readonly')) {
      throw Exception('Missing minimum required YouTube scope.');
    }

    return ConnectedAccount(
      externalAccountId: authPayload['channel_id'] ?? 'yt_channel_1',
      platformId: platformName,
      connectorId: 'youtube_core',
      displayName: authPayload['channel_title'] ?? 'YouTube Channel',
      status: 'VERIFIED',
      capabilities: getCapabilities(),
      scopes: scopes,
      connectedAt: DateTime.now(),
      reauthRequired: false,
      credential: Credential(
        accessToken: authPayload['access_token'] ?? 'yt_token',
        refreshToken: authPayload['refresh_token'],
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        metadata: {
          'scopes': scopes,
        },
      ),
    );
  }

  @override
  Future<Credential> refreshCredentials(Credential current) async {
    // YouTube tokens (Google OAuth) expire in 1 hour. Use refresh_token.
    if (DateTime.now().isAfter(current.expiresAt)) {
      if (current.refreshToken == null) {
        throw Exception('Cannot refresh YouTube token without a refresh_token. Re-authorization required.');
      }
      await Future.delayed(const Duration(milliseconds: 300));
      return Credential(
        accessToken: 'yt_token_refreshed',
        refreshToken: current.refreshToken,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        metadata: current.metadata,
      );
    }
    return current;
  }

  @override
  List<PlatformCapability> getCapabilities() {
    // YouTube Data API supports video publishing, reading comments, analytics (via YT Analytics API).
    // NO direct messages. 
    return [
      PlatformCapability.contentPublish,
      PlatformCapability.contentRead,
      PlatformCapability.commentsRead,
      PlatformCapability.commentsReply,
      PlatformCapability.analytics,
      PlatformCapability.live,
      PlatformCapability.mediaUpload,
    ];
  }

  @override
  Future<SyncJob> sync(ConnectedAccount account) async {
    requireCapability(PlatformCapability.contentRead);
    // Simulating syncing videos/playlists and mapping to canonical models
    // Does NOT duplicate the MP4 file to local storage, only stores externalId.
    
    // Simulate quota check
    _checkQuota();

    return SyncJob(
      jobId: 'sync_yt_${DateTime.now().millisecondsSinceEpoch}',
      accountId: account.externalAccountId,
      startedAt: DateTime.now(),
      status: 'completed',
    );
  }

  @override
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    requireCapability(PlatformCapability.contentPublish);
    
    // Simulate checking if we have upload scopes
    final scopes = account.credential!.metadata['scopes'] as List<String>? ?? [];
    if (!scopes.contains('https://www.googleapis.com/auth/youtube.upload')) {
      throw Exception('Missing youtube.upload scope. Publication failed.');
    }

    _checkQuota();
    
    // Simulate upload via Resumable Upload API
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Mapping back YouTube's Video ID (e.g. dQw4w9WgXcQ)
    return PublishJob(
      jobId: 'yt_pub_1',
      targetPlatform: platformName,
      status: 'published',
    );
  }

  @override
  Future<String> getStatus(ConnectedAccount account) async {
    // Ping API
    return 'ACTIVE';
  }

  void _checkQuota() {
    // Example: Throw YouTubeQuotaException if HTTP 403 quotaExceeded is encountered
    // if (quotaExceeded) { throw YouTubeQuotaException('YouTube API quota exceeded.'); }
  }

  @override
  Future<void> disconnect(ConnectedAccount account) async {
    // Revoke Google OAuth token
  }
}
