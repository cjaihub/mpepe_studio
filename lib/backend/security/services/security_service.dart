import 'package:oneova/backend/security/models/security_models.dart';
import 'package:oneova/backend/privacy/services/privacy_service.dart';
import 'package:oneova/backend/privacy/models/privacy_models.dart';
import 'package:oneova/backend/ai_personalization/services/ai_content_memory_service.dart';

class SecurityService {
  final Map<String, List<DeviceSession>> _sessions = {};
  final Map<String, List<ConnectedAccount>> _connectedAccounts = {};
  final Map<String, List<ApiToken>> _apiTokens = {};
  
  final PrivacyService _privacyService;
  final AiContentMemoryService _aiMemoryService;

  SecurityService(this._privacyService, this._aiMemoryService);

  void registerSession(String userId, DeviceSession session) {
    _sessions.putIfAbsent(userId, () => []).add(session);
  }

  void revokeSession(String userId, String sessionId) {
    final userSessions = _sessions[userId] ?? [];
    for (var session in userSessions) {
      if (session.id == sessionId) {
        session.isRevoked = true;
      }
    }
  }

  void signOutAllDevices(String userId, String currentSessionId) {
    final userSessions = _sessions[userId] ?? [];
    for (var session in userSessions) {
      if (session.id != currentSessionId) {
        session.isRevoked = true;
      }
    }
  }

  void disconnectAccount(String userId, String providerId) {
    final accounts = _connectedAccounts[userId] ?? [];
    accounts.removeWhere((acc) => acc.providerId == providerId);
  }

  void revokeAi(String userId) {
    // 1. Immediately purge all AI memory clusters to prevent profiling
    _aiMemoryService.updateSettings(userId, isAiOrganizationEnabled: false);
    
    // 2. Lock down the central privacy center preventing data harvesting
    final privacySettings = _privacyService.getSettings(userId);
    privacySettings.ai.whoCanUseAiContext = PrivacyVisibility.none;
    _privacyService.updateSettings(userId, privacySettings);
  }

  // Helper method for testing the data store
  void registerConnectedAccount(String userId, ConnectedAccount account) {
    _connectedAccounts.putIfAbsent(userId, () => []).add(account);
  }

  // Returns trailing characters only. Never the secret.
  String generateApiToken(String userId, String name) {
    // Mock secret generation
    final secret = 'oneova_${DateTime.now().microsecondsSinceEpoch}_abcdefgh1234';
    final trailing = secret.substring(secret.length - 4);

    final token = ApiToken(
      id: 'token_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      createdAt: DateTime.now(),
      trailingChars: trailing,
    );
    
    _apiTokens.putIfAbsent(userId, () => []).add(token);

    // Return the secret ONCE. After this, it's gone from our systems forever.
    return secret;
  }
}
