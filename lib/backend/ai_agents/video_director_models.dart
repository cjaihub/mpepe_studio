import 'package:uuid/uuid.dart';

enum AiEditAction { cut, move, addCaption, adjustVolume, addBroll, addMusic }
enum PlanStatus { pending, previewing, applied, rejected }

class AiEditSuggestion {
  final String id;
  final AiEditAction action;
  final String description;
  final Map<String, dynamic> parameters;

  AiEditSuggestion({
    String? id,
    required this.action,
    required this.description,
    this.parameters = const {},
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap() => {
    'id': id,
    'action': action.name,
    'description': description,
    'parameters': parameters,
  };

  factory AiEditSuggestion.fromMap(Map<String, dynamic> map) {
    return AiEditSuggestion(
      id: map['id'],
      action: AiEditAction.values.byName(map['action']),
      description: map['description'],
      parameters: Map<String, dynamic>.from(map['parameters'] ?? {}),
    );
  }
}

class VideoDirectorPlan {
  final String id;
  final String projectId;
  final List<AiEditSuggestion> suggestions;
  final String? suggestedTitle;
  final String? suggestedDescription;
  PlanStatus status;
  final DateTime createdAt;
  DateTime? appliedAt;

  VideoDirectorPlan({
    String? id,
    required this.projectId,
    required this.suggestions,
    this.suggestedTitle,
    this.suggestedDescription,
    this.status = PlanStatus.pending,
    DateTime? createdAt,
    this.appliedAt,
  }) : id = id ?? const Uuid().v4(), createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'projectId': projectId,
    'suggestions': suggestions.map((s) => s.toMap()).toList(),
    'suggestedTitle': suggestedTitle,
    'suggestedDescription': suggestedDescription,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'appliedAt': appliedAt?.toIso8601String(),
  };

  factory VideoDirectorPlan.fromMap(Map<String, dynamic> map) {
    return VideoDirectorPlan(
      id: map['id'],
      projectId: map['projectId'],
      suggestions: (map['suggestions'] as List).map((s) => AiEditSuggestion.fromMap(s)).toList(),
      suggestedTitle: map['suggestedTitle'],
      suggestedDescription: map['suggestedDescription'],
      status: PlanStatus.values.byName(map['status']),
      createdAt: DateTime.parse(map['createdAt']),
      appliedAt: map['appliedAt'] != null ? DateTime.parse(map['appliedAt']) : null,
    );
  }
}

class AiAuditRecord {
  final String id;
  final String planId;
  final String projectId;
  final String action;
  final DateTime timestamp;
  final Map<String, dynamic> details;

  AiAuditRecord({
    String? id,
    required this.planId,
    required this.projectId,
    required this.action,
    DateTime? timestamp,
    this.details = const {},
  }) : id = id ?? const Uuid().v4(), timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'planId': planId,
    'projectId': projectId,
    'action': action,
    'timestamp': timestamp.toIso8601String(),
    'details': details,
  };
}
