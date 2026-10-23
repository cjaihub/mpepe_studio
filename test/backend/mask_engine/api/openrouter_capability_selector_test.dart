import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/mask_engine/api/openrouter_capability_selector.dart';

void main() {
  group('OpenRouterCapabilitySelector', () {
    
    test('Selects fast preview model based on latency constraint', () {
      final constraints = AiTaskConstraints(
        taskType: 'fast preview',
        requestedWidth: 512,
        requestedHeight: 512,
        numberOfReferences: 0,
        requiresEditing: false,
        maxLatencySeconds: 1.0, // Strictly requires fast proxy
        prioritizeQuality: false,
        maxBudgetPerGeneration: 0.05,
        requiresStrictPrivacy: true,
      );

      final selectedModel = OpenRouterCapabilitySelector.resolveOptimalModel(constraints);
      expect(selectedModel, 'openrouter/fast-proxy-model/v1');
    });

    test('Throws CAPABILITY_NOT_AVAILABLE when constraints are impossible', () {
      final constraints = AiTaskConstraints(
        taskType: 'high quality generation',
        requestedWidth: 8000, // Impossibly large
        requestedHeight: 8000,
        numberOfReferences: 4,
        requiresEditing: true,
        maxLatencySeconds: 0.5, // Impossibly fast
        prioritizeQuality: true,
        maxBudgetPerGeneration: 0.0001,
        requiresStrictPrivacy: true,
      );

      expect(
        () => OpenRouterCapabilitySelector.resolveOptimalModel(constraints),
        throwsA(isA<CapabilityNotAvailableException>()),
      );
    });

    test('Selects correct model for reference edit', () {
      final constraints = AiTaskConstraints(
        taskType: 'reference edit',
        requestedWidth: 1024,
        requestedHeight: 1024,
        numberOfReferences: 1,
        requiresEditing: true, // Requires editing capability
        maxLatencySeconds: 10.0,
        prioritizeQuality: true,
        maxBudgetPerGeneration: 0.1,
        requiresStrictPrivacy: true,
      );

      final selectedModel = OpenRouterCapabilitySelector.resolveOptimalModel(constraints);
      expect(selectedModel, 'openrouter/stabilityai/stable-diffusion-xl');
    });
  });
}
