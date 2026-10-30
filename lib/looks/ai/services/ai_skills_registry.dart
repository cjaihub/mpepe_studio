import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ai_skill_manifest.dart';

/// Registry holding active AI skills loaded dynamically from Firestore or offline bundled cache.
class AiSkillsRegistry {
  SkillPack _currentPack = _defaultStarterPack;
  SkillPack get currentPack => _currentPack;

  static final SkillPack _defaultStarterPack = SkillPack(
    packId: 'starter_pack_v1',
    version: 1,
    updatedAt: DateTime(2026, 10, 1),
    skills: const [
      AiSkill(
        id: 'gradeCommand',
        version: 1,
        name: 'Conversational Color Grader',
        description: 'Translates natural language instructions into precise GLSL Look graph parameter adjustments.',
        systemPrompt:
            'You are Oneova AI Color Grader. Modify look nodes (primary, wheels, color, curves, film, optics) with artistic restraint.',
        evalScore: 0.98,
        isOfflineCapable: true,
      ),
      AiSkill(
        id: 'createLook',
        version: 1,
        name: 'Look Synthesizer',
        description: 'Creates a complete OneovaLook from conceptual or stylistic text prompts.',
        systemPrompt:
            'You are Oneova LookSmith. Synthesize complete OneovaLook JSON configurations capturing lighting, tone, and film stock.',
        evalScore: 0.96,
        isOfflineCapable: true,
      ),
      AiSkill(
        id: 'analyzeFrame',
        version: 1,
        name: 'Scope & Frame Critic',
        description: 'Analyzes luminance, chroma, and gamut histograms to recommend restorative fixes.',
        systemPrompt:
            'You are Oneova Scope Sentinel Critic. Identify clipping, crushed shadows, and skin tone casts.',
        evalScore: 0.95,
        isOfflineCapable: true,
      ),
    ],
  );

  /// Retrieves an active skill by identifier.
  AiSkill getSkill(String skillId) {
    return _currentPack.findSkill(skillId) ??
        _defaultStarterPack.findSkill(skillId) ??
        _defaultStarterPack.skills.first;
  }

  /// Updates the active pack (e.g. after receiving server update from Firestore).
  void registerPack(SkillPack pack) {
    if (pack.version >= _currentPack.version) {
      _currentPack = pack;
      debugPrint('[AiSkillsRegistry] Loaded SkillPack "${pack.packId}" version ${pack.version}');
    }
  }

  /// Rollbacks to starter bundle in case of runtime evaluation degradation.
  void rollbackToStarter() {
    _currentPack = _defaultStarterPack;
  }
}

final aiSkillsRegistryProvider = Provider<AiSkillsRegistry>((ref) {
  return AiSkillsRegistry();
});
