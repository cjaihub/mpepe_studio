import 'package:cloud_firestore/cloud_firestore.dart';
import '../../backend/unified_inbox_provider.dart' show SocialPlatform;

enum AgentMode {
  offline,
  suggestions,
  drafts,
  scheduled,
  auto
}

enum EscalationPolicy {
  pauseAndNotify,
  delayUntilNextCycle,
  silentFailure
}

class AgentConfig {
  final AgentMode mode;
  final List<String> allowedActions;
  final List<String> blockedActions;
  final List<SocialPlatform> allowedChannels;
  final List<String> allowedConversations; // List of conversation IDs
  final int dailyActionLimit;
  final int dailyTokenLimit;
  final bool isGloballyPaused;
  final EscalationPolicy escalationPolicy;
  final DateTime updatedAt;

  AgentConfig({
    this.mode = AgentMode.offline,
    this.allowedActions = const [],
    this.blockedActions = const [],
    this.allowedChannels = const [],
    this.allowedConversations = const [],
    this.dailyActionLimit = 10,
    this.dailyTokenLimit = 50000,
    this.isGloballyPaused = false,
    this.escalationPolicy = EscalationPolicy.pauseAndNotify,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  factory AgentConfig.fromMap(Map<String, dynamic> data) {
    return AgentConfig(
      mode: AgentMode.values.firstWhere((e) => e.name == data['mode'], orElse: () => AgentMode.offline),
      allowedActions: List<String>.from(data['allowedActions'] ?? []),
      blockedActions: List<String>.from(data['blockedActions'] ?? []),
      allowedChannels: (data['allowedChannels'] as List<dynamic>? ?? []).map((e) {
        return SocialPlatform.values.firstWhere((p) => p.name == e, orElse: () => SocialPlatform.system);
      }).toList(),
      allowedConversations: List<String>.from(data['allowedConversations'] ?? []),
      dailyActionLimit: data['dailyActionLimit'] ?? 10,
      dailyTokenLimit: data['dailyTokenLimit'] ?? 50000,
      isGloballyPaused: data['isGloballyPaused'] ?? false,
      escalationPolicy: EscalationPolicy.values.firstWhere((e) => e.name == data['escalationPolicy'], orElse: () => EscalationPolicy.pauseAndNotify),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mode': mode.name,
      'allowedActions': allowedActions,
      'blockedActions': blockedActions,
      'allowedChannels': allowedChannels.map((e) => e.name).toList(),
      'allowedConversations': allowedConversations,
      'dailyActionLimit': dailyActionLimit,
      'dailyTokenLimit': dailyTokenLimit,
      'isGloballyPaused': isGloballyPaused,
      'escalationPolicy': escalationPolicy.name,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  AgentConfig copyWith({
    AgentMode? mode,
    List<String>? allowedActions,
    List<String>? blockedActions,
    List<SocialPlatform>? allowedChannels,
    List<String>? allowedConversations,
    int? dailyActionLimit,
    int? dailyTokenLimit,
    bool? isGloballyPaused,
    EscalationPolicy? escalationPolicy,
    DateTime? updatedAt,
  }) {
    return AgentConfig(
      mode: mode ?? this.mode,
      allowedActions: allowedActions ?? this.allowedActions,
      blockedActions: blockedActions ?? this.blockedActions,
      allowedChannels: allowedChannels ?? this.allowedChannels,
      allowedConversations: allowedConversations ?? this.allowedConversations,
      dailyActionLimit: dailyActionLimit ?? this.dailyActionLimit,
      dailyTokenLimit: dailyTokenLimit ?? this.dailyTokenLimit,
      isGloballyPaused: isGloballyPaused ?? this.isGloballyPaused,
      escalationPolicy: escalationPolicy ?? this.escalationPolicy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
