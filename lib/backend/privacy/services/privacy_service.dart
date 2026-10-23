import 'package:oneova/backend/privacy/models/privacy_models.dart';

class PrivacyService {
  final Map<String, PrivacyCenterSettings> _userSettings = {};

  // Mock relationship database (In real app, this hits the unified social inbox/friends database)
  bool areUsersMutuals(String userA, String userB) => false;
  bool isUserFollowing(String userA, String userB) => false;

  PrivacyCenterSettings getSettings(String userId) {
    return _userSettings.putIfAbsent(userId, () => PrivacyCenterSettings(userId: userId));
  }

  void updateSettings(String userId, PrivacyCenterSettings updatedSettings) {
    _userSettings[userId] = updatedSettings;
  }

  bool _isAuthorized(String targetUserId, String requestingUserId, PrivacyVisibility visibility) {
    if (targetUserId == requestingUserId) return true;

    switch (visibility) {
      case PrivacyVisibility.everyone:
        return true;
      case PrivacyVisibility.followers:
        return isUserFollowing(requestingUserId, targetUserId);
      case PrivacyVisibility.mutuals:
        return areUsersMutuals(targetUserId, requestingUserId);
      case PrivacyVisibility.none:
        return false;
    }
  }

  // --- Profile Authorizations ---
  bool canSeeProfile(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.profile.whoCanSee);
  }

  bool canFollow(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.profile.whoCanFollow);
  }

  // --- Content Authorizations ---
  bool canComment(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.content.whoCanComment);
  }

  bool canRemix(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.content.whoCanRemix);
  }

  bool canDownload(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.content.whoCanDownload);
  }

  // --- Message Authorizations ---
  bool canMessage(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.messages.whoCanMessage);
  }

  // --- Location Authorizations ---
  bool canSeeLocation(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.location.whoCanSeeLocation);
  }

  // --- AI Authorizations ---
  bool canUseAiContext(String targetUserId, String requestingUserId) {
    final settings = getSettings(targetUserId);
    return _isAuthorized(targetUserId, requestingUserId, settings.ai.whoCanUseAiContext);
  }
}
