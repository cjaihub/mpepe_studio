import 'package:cloud_firestore/cloud_firestore.dart';

enum AiComposerAction {
  improve,
  shorten,
  expand,
  makeProfessional,
  makeFriendly,
  translate,
  reply,
  summarize,
  rewrite,
  voiceDraft,
}

enum AiSuggestionStatus {
  pending,
  accepted,
  edited,
  rejected,
  regenerated,
}

class AiSuggestion {
  final String id;
  final String originalText;
  final String suggestedText;
  final AiComposerAction action;
  final AiSuggestionStatus status;
  final DateTime createdAt;
  final String conversationId;
  final String messageId; // Might be null if drafted for a new message

  AiSuggestion({
    required this.id,
    required this.originalText,
    required this.suggestedText,
    required this.action,
    required this.status,
    required this.createdAt,
    required this.conversationId,
    required this.messageId,
  });

  factory AiSuggestion.fromMap(Map<String, dynamic> map, String id) {
    return AiSuggestion(
      id: id,
      originalText: map['originalText'] as String? ?? '',
      suggestedText: map['suggestedText'] as String? ?? '',
      action: AiComposerAction.values.firstWhere(
        (e) => e.name == map['action'],
        orElse: () => AiComposerAction.improve,
      ),
      status: AiSuggestionStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => AiSuggestionStatus.pending,
      ),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      conversationId: map['conversationId'] as String? ?? '',
      messageId: map['messageId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'originalText': originalText,
      'suggestedText': suggestedText,
      'action': action.name,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'conversationId': conversationId,
      'messageId': messageId,
    };
  }

  AiSuggestion copyWith({
    String? suggestedText,
    AiSuggestionStatus? status,
  }) {
    return AiSuggestion(
      id: id,
      originalText: originalText,
      suggestedText: suggestedText ?? this.suggestedText,
      action: action,
      status: status ?? this.status,
      createdAt: createdAt,
      conversationId: conversationId,
      messageId: messageId,
    );
  }
}
