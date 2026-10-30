import 'package:flutter/foundation.dart';
import '../../models/oneova_look.dart';

/// Semantic target region for localized AI color grading edits.
enum SemanticGradeRegion {
  entireFrame,
  skin,
  sky,
  background,
  subject,
  hair,
  clothing,
  shadows,
  highlights,
  midtones;

  String get label => switch (this) {
        SemanticGradeRegion.entireFrame => 'Entire Frame',
        SemanticGradeRegion.skin => 'Skin Tones',
        SemanticGradeRegion.sky => 'Sky',
        SemanticGradeRegion.background => 'Background',
        SemanticGradeRegion.subject => 'Subject',
        SemanticGradeRegion.hair => 'Hair',
        SemanticGradeRegion.clothing => 'Clothing',
        SemanticGradeRegion.shadows => 'Shadows',
        SemanticGradeRegion.highlights => 'Highlights',
        SemanticGradeRegion.midtones => 'Midtones',
      };
}

/// Agent-style diff report documenting the exact parameter modifications made by AI.
@immutable
class GradeDiffReport {
  final Map<String, dynamic> previousParameters;
  final Map<String, dynamic> updatedParameters;
  final List<String> modifiedNodes;
  final String visualDeltaSummary;
  final String artisticRationale;
  final SemanticGradeRegion targetRegion;

  const GradeDiffReport({
    this.previousParameters = const {},
    this.updatedParameters = const {},
    this.modifiedNodes = const [],
    required this.visualDeltaSummary,
    required this.artisticRationale,
    this.targetRegion = SemanticGradeRegion.entireFrame,
  });

  Map<String, dynamic> toJson() => {
        'previousParameters': previousParameters,
        'updatedParameters': updatedParameters,
        'modifiedNodes': modifiedNodes,
        'visualDeltaSummary': visualDeltaSummary,
        'artisticRationale': artisticRationale,
        'targetRegion': targetRegion.name,
      };

  factory GradeDiffReport.fromJson(Map<String, dynamic> json) {
    return GradeDiffReport(
      previousParameters: (json['previousParameters'] as Map<String, dynamic>?) ?? {},
      updatedParameters: (json['updatedParameters'] as Map<String, dynamic>?) ?? {},
      modifiedNodes: (json['modifiedNodes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      visualDeltaSummary: json['visualDeltaSummary'] as String? ?? 'Adjusted look parameters',
      artisticRationale: json['artisticRationale'] as String? ?? '',
      targetRegion: SemanticGradeRegion.values.firstWhere(
        (e) => e.name == json['targetRegion'],
        orElse: () => SemanticGradeRegion.entireFrame,
      ),
    );
  }
}

/// Structured outcome of an AI grading operation.
@immutable
class AiGradeResult {
  final OneovaLook updatedLook;
  final GradeDiffReport diffReport;
  final String assistantExplanation;
  final List<String> suggestedNextPrompts;
  final bool isOfflineInference;

  const AiGradeResult({
    required this.updatedLook,
    required this.diffReport,
    required this.assistantExplanation,
    this.suggestedNextPrompts = const [],
    this.isOfflineInference = false,
  });
}

/// Version history checkpoint for undo/redo in the conversational color grader.
@immutable
class GradeHistoryEntry {
  final String entryId;
  final DateTime timestamp;
  final String userInstruction;
  final OneovaLook lookSnapshot;
  final GradeDiffReport? diffReport;

  const GradeHistoryEntry({
    required this.entryId,
    required this.timestamp,
    required this.userInstruction,
    required this.lookSnapshot,
    this.diffReport,
  });
}
