import 'dart:async';
import '../models/ai_messaging_models.dart';

class AiMessagingService {
  // Singleton pattern for simplicity, though normally injected via Riverpod/GetIt
  static final AiMessagingService _instance = AiMessagingService._internal();
  factory AiMessagingService() => _instance;
  AiMessagingService._internal();

  AutoModeConfig _currentConfig = const AutoModeConfig();

  AutoModeConfig get config => _currentConfig;

  // Stream for UI to listen to config changes
  final _configController = StreamController<AutoModeConfig>.broadcast();
  Stream<AutoModeConfig> get configStream => _configController.stream;

  /// Update Auto Mode Level with EXPLICIT user confirmation requirement.
  /// In the real UI, this should only be called after a confirmation dialog returns true.
  Future<bool> updateAutoModeLevel(AutoModeLevel newLevel, bool userConfirmed) async {
    if (!userConfirmed && newLevel != AutoModeLevel.off) {
      // Must have explicit confirmation for any level above 'off'
      return false;
    }

    _currentConfig = _currentConfig.copyWith(level: newLevel);
    _configController.add(_currentConfig);
    return true;
  }

  /// Update other configuration settings (e.g. allowed contacts, limits)
  void updateConfig(AutoModeConfig newConfig) {
    _currentConfig = newConfig;
    _configController.add(_currentConfig);
  }

  /// Check if a generated AI response contains sensitive topics that must NEVER be auto-sent.
  bool containsSensitiveTopic(String messageContent, List<SensitiveTopicCategory> detectedTopics) {
    // If the AI detects any topic that isn't 'none', it's sensitive
    return detectedTopics.any((topic) => topic != SensitiveTopicCategory.none);
  }

  /// Determines if a specific message can be auto-sent or auto-drafted based on the current AutoModeConfig.
  bool canAutoProcess({
    required String contactId,
    required String conversationId,
    required String channel,
    required List<SensitiveTopicCategory> detectedTopics,
    bool isE2EE = false, // Explicit architecture boundary: AI cannot read E2EE content
  }) {
    // SECURITY HARD LINE: Never process E2EE messages on the backend/AI models
    if (isE2EE) {
      return false;
    }

    if (_currentConfig.level == AutoModeLevel.off || _currentConfig.level == AutoModeLevel.suggestionsOnly) {
      return false; // No automated drafting or sending
    }

    // 1. Sensitive actions must never be automatically executed
    if (containsSensitiveTopic('', detectedTopics)) {
      return false;
    }

    // 2. Check Contact Allow/Block lists
    if (_currentConfig.blockedContacts.contains(contactId)) {
      return false;
    }
    if (_currentConfig.allowedContacts.isNotEmpty && !_currentConfig.allowedContacts.contains(contactId)) {
      return false;
    }

    // 3. Check Conversation Allow/Block lists
    if (_currentConfig.blockedConversations.contains(conversationId)) {
      return false;
    }
    if (_currentConfig.allowedConversations.isNotEmpty && !_currentConfig.allowedConversations.contains(conversationId)) {
      return false;
    }

    // 4. Check Channel constraints
    if (_currentConfig.allowedChannels.isNotEmpty && !_currentConfig.allowedChannels.contains(channel)) {
      return false;
    }

    // Note: Time-based (allowedHours) and limits (maxMessagesPerDay) would be evaluated here
    // using DateTime.now() and persistent counters.

    return true;
  }

  void dispose() {
    _configController.close();
  }
}
