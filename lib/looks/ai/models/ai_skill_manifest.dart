import 'package:flutter/foundation.dart';

/// Representation of an AI skill dynamically loaded from Firestore or local assets.
@immutable
class AiSkill {
  final String id;
  final int version;
  final String name;
  final String description;
  final String systemPrompt;
  final List<Map<String, dynamic>> toolDeclarations;
  final double evalScore; // 0.0 to 1.0 (from offline eval gate)
  final int minDeviceTier;
  final bool isOfflineCapable;

  const AiSkill({
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.systemPrompt,
    this.toolDeclarations = const [],
    this.evalScore = 0.95,
    this.minDeviceTier = 1,
    this.isOfflineCapable = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'name': name,
        'description': description,
        'systemPrompt': systemPrompt,
        'toolDeclarations': toolDeclarations,
        'evalScore': evalScore,
        'minDeviceTier': minDeviceTier,
        'isOfflineCapable': isOfflineCapable,
      };

  factory AiSkill.fromJson(Map<String, dynamic> json) {
    return AiSkill(
      id: json['id'] as String? ?? 'unknown_skill',
      version: (json['version'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'Unnamed Skill',
      description: json['description'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      toolDeclarations: (json['toolDeclarations'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          [],
      evalScore: (json['evalScore'] as num?)?.toDouble() ?? 0.9,
      minDeviceTier: (json['minDeviceTier'] as num?)?.toInt() ?? 1,
      isOfflineCapable: json['isOfflineCapable'] as bool? ?? true,
    );
  }
}

/// Versioned package of skills synced to the device for runtime and offline AI grading.
@immutable
class SkillPack {
  final String packId;
  final int version;
  final List<AiSkill> skills;
  final DateTime updatedAt;

  const SkillPack({
    required this.packId,
    required this.version,
    required this.skills,
    required this.updatedAt,
  });

  AiSkill? findSkill(String id) {
    for (final s in skills) {
      if (s.id == id) return s;
    }
    return null;
  }
}
