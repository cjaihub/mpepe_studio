import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/ai/models/ai_grade_command.dart';
import 'package:oneova/looks/ai/services/ai_color_grader_service.dart';
import 'package:oneova/looks/ai/controllers/conversational_grader_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Conversational AI Grader Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('OnDeviceLlmRunner interprets warmth instruction and shifts temperature', () async {
      final grader = container.read(aiColorGraderServiceProvider);
      const baseLook = OneovaLook(id: 'base', name: 'Neutral');

      final result = await grader.grade(
        prompt: 'Make the scene warmer and golden',
        currentLook: baseLook,
        region: SemanticGradeRegion.entireFrame,
        forceOffline: true,
      );

      expect(result.updatedLook.color?.temperature, greaterThan(0.0));
      expect(result.diffReport.modifiedNodes, contains('color'));
      expect(result.diffReport.visualDeltaSummary, contains('temperature'));
      expect(result.isOfflineInference, true);
    });

    test('OnDeviceLlmRunner adds film grain and halation on vintage prompt', () async {
      final grader = container.read(aiColorGraderServiceProvider);
      const baseLook = OneovaLook(id: 'base', name: 'Neutral');

      final result = await grader.grade(
        prompt: 'Give it 35mm film grain and vintage halation',
        currentLook: baseLook,
        forceOffline: true,
      );

      expect(result.updatedLook.film?.grain, greaterThan(0.2));
      expect(result.updatedLook.film?.halation, greaterThan(0.2));
      expect(result.diffReport.modifiedNodes, contains('film'));
    });

    test('createLookFromPrompt synthesizes a complete OneovaLook', () async {
      final grader = container.read(aiColorGraderServiceProvider);

      final synthesized = await grader.createLookFromPrompt(
        prompt: 'Cyberpunk Tokyo neon nights',
        category: 'cinematic',
      );

      expect(synthesized.name, contains('Cyberpunk'));
      expect(synthesized.categories, contains('cinematic'));
    });

    test('ConversationalGraderController manages undo and redo stack', () async {
      final controller = container.read(conversationalGraderControllerProvider.notifier);

      expect(container.read(conversationalGraderControllerProvider).canUndo, false);
      expect(container.read(conversationalGraderControllerProvider).canRedo, false);

      // Submit first prompt
      await controller.submitPrompt('Make it warmer and brighter');
      final firstState = container.read(conversationalGraderControllerProvider);
      expect(firstState.canUndo, true);
      expect(firstState.canRedo, false);
      final firstTemp = firstState.activeLook.color?.temperature ?? 0.0;
      expect(firstTemp, greaterThan(0.0));

      // Submit second prompt
      await controller.submitPrompt('Add film grain');
      final secondState = container.read(conversationalGraderControllerProvider);
      expect(secondState.canUndo, true);
      expect(secondState.activeLook.film?.grain, greaterThan(0.2));

      // Undo back to first edit
      controller.undo();
      final undoneState = container.read(conversationalGraderControllerProvider);
      expect(undoneState.canRedo, true);
      expect(undoneState.activeLook.film?.grain ?? 0.0, 0.0);
      expect(undoneState.activeLook.color?.temperature, firstTemp);

      // Redo back to second edit
      controller.redo();
      final redoneState = container.read(conversationalGraderControllerProvider);
      expect(redoneState.activeLook.film?.grain, greaterThan(0.2));
    });

    test('Target region selection updates controller state', () {
      final controller = container.read(conversationalGraderControllerProvider.notifier);
      expect(container.read(conversationalGraderControllerProvider).targetRegion, SemanticGradeRegion.entireFrame);

      controller.setTargetRegion(SemanticGradeRegion.skin);
      expect(container.read(conversationalGraderControllerProvider).targetRegion, SemanticGradeRegion.skin);

      controller.setTargetRegion(SemanticGradeRegion.sky);
      expect(container.read(conversationalGraderControllerProvider).targetRegion, SemanticGradeRegion.sky);
    });
  });
}
