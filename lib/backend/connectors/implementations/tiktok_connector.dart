import 'package:oneova/backend/connectors/core/platform_connector.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';

class TikTokAuditException implements Exception {
  final String message;
  TikTokAuditException(this.message);
  @override
  String toString() => 'TikTokAuditException: $message';
}

class TikTokPrivacySettings {
  final String privacyLevel; // 'public', 'friends', 'private'
  final bool disableComment;
  final bool disableDuet;
  final bool disableStitch;

  TikTokPrivacySettings({
    this.privacyLevel = 'public',
    this.disableComment = false,
    this.disableDuet = false,
    this.disableStitch = false,
  });
}

class TikTokConnector extends PlatformConnector {
  TikTokConnector() : super('TikTok');

  @override
  Future<void> connect() async {
    // Initiate TikTok OAuth flow for Content Posting API
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<ConnectedAccount> authorize(Map<String, dynamic> authPayload) async {
    // Validate scopes: user.info.basic, video.upload
    final scopes = List<String>.from(authPayload['scopes'] ?? []);
    if (!scopes.contains('video.upload')) {
      throw Exception('Missing video.upload scope. Cannot authorize publishing.');
    }

    return ConnectedAccount(
      externalAccountId: authPayload['open_id'] ?? 'tk_user_1',
      platformId: platformName,
      connectorId: 'tiktok_official',
      displayName: authPayload['display_name'] ?? 'TikTok Creator',
      status: 'CONNECTED',
      capabilities: getCapabilities(),
      scopes: scopes,
      connectedAt: DateTime.now(),
      reauthRequired: false,
      metadata: {
        'avatar_url': authPayload['avatar_url'] ?? '',
      },
      credential: Credential(
        accessToken: authPayload['access_token'] ?? 'tk_token',
        refreshToken: authPayload['refresh_token'],
        expiresAt: DateTime.now().add(const Duration(hours: 24)), // TikTok access tokens usually expire in 24h
        metadata: {
          'scopes': scopes,
          'creator_info_verified': false,
        },
      ),
    );
  }

  @override
  Future<Credential> refreshCredentials(Credential current) async {
    if (DateTime.now().isAfter(current.expiresAt)) {
      if (current.refreshToken == null) {
        throw Exception('Cannot refresh TikTok token without a refresh_token.');
      }
      await Future.delayed(const Duration(milliseconds: 300));
      return Credential(
        accessToken: 'tk_token_refreshed',
        refreshToken: current.refreshToken,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        metadata: current.metadata,
      );
    }
    return current;
  }

  @override
  List<PlatformCapability> getCapabilities() {
    // TikTok Content Posting API is strictly for posting content.
    // It does not support reading arbitrary feeds, sending messages, or reading comments (without extra specific enterprise approvals).
    // We do NOT claim universal TikTok control.
    return [
      PlatformCapability.contentPublish,
      PlatformCapability.profileRead,
      PlatformCapability.mediaUpload,
    ];
  }

  /// Before publishing, query creator info to respect limits
  Future<void> _verifyCreatorStatus(ConnectedAccount account) async {
    // TikTok Content Posting API requires querying creator info to check video length limits, max followers etc if needed
    await Future.delayed(const Duration(milliseconds: 100));
    account.credential!.metadata['creator_info_verified'] = true;
  }

  @override
  Future<PublishJob> publish(ConnectedAccount account, ExternalObject object) async {
    requireCapability(PlatformCapability.contentPublish);
    
    // Do not publish without explicit user consent
    if (object.data['explicit_consent'] != true) {
      throw Exception('Explicit user consent is strictly required for TikTok Direct Post.');
    }

    // 1. Query creator information before publishing
    await _verifyCreatorStatus(account);

    // 2. Extract privacy settings
    // ignore: unused_local_variable
    final privacySettings = object.data['tiktok_privacy'] as TikTokPrivacySettings? ?? TikTokPrivacySettings();

    // 3. Initiate chunked video upload (Content Posting API logic)
    await Future.delayed(const Duration(milliseconds: 500));

    // 4. Submit for publish/audit
    // If the API requires an audit/review for public visibility, surface that state.
    final bool requiresAudit = DateTime.now().isBefore(DateTime(2030)); // Simulating TikTok's standard review pipeline
    
    return PublishJob(
      jobId: 'tk_pub_1',
      targetPlatform: platformName,
      status: requiresAudit ? 'PENDING_AUDIT' : 'PUBLISHED',
    );
  }

  @override
  Future<String> getStatus(ConnectedAccount account) async {
    // Query /v2/post/publish/status/
    final isAuditPending = DateTime.now().isBefore(DateTime(2030)); // Simulating check
    if (isAuditPending) {
      return 'PENDING_AUDIT';
    }
    return 'ACTIVE';
  }

  @override
  Future<void> disconnect(ConnectedAccount account) async {
    // Revoke token
  }
}
