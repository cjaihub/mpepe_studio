import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_tool_registry.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_context_resolver.dart';
import 'package:oneova/backend/ai_agents/omni_command/tools/effect_tools.dart';
import 'package:oneova/backend/projects/models/pro_project_models.dart';
import 'package:oneova/backend/projects/models/effect_models.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:mockito/mockito.dart';

import 'color_tools_test.mocks.dart';

void main() {
  group('Effect Tools Tests', () {
    late OmniToolRegistry registry;
    late MockProjectRepository mockProjectRepo;
    late StudioProject testProject;
    late Sequence testSequence;
    late Track testTrack;
    late Clip testClip;

    setUp(() {
      registry = OmniToolRegistry();
      mockProjectRepo = MockProjectRepository();

      registerEffectTools(registry, mockProjectRepo);

      testClip = Clip(
        id: 'clip_1',
        sourceMediaId: 'asset_1',
        type: MediaType.video,
        startTime: 10,
        duration: 5,
        sourceStart: 0,
      );

      testTrack = Track(
        id: 'track_1',
        name: 'main',
        type: TrackType.video,
        clips: [testClip],
      );

      testSequence = Sequence(
        id: 'seq_1',
        name: 'seq 1',
        settings: ProjectSettings(width: 1080, height: 1920, frameRate: 30),
        tracks: [testTrack],
      );

      testProject = StudioProject(
        id: 'proj_1',
        ownerId: 'user_1',
        title: 'Test Project',
        category: 'Video',
        status: 'Editing',
        completedSteps: 0,
        createdAt: DateTime.now(),
        sequences: [testSequence],
      );

      when(mockProjectRepo.getProject('proj_1')).thenAnswer((_) async => testProject);
      when(mockProjectRepo.updateProject(any)).thenAnswer((_) async {});
    });

    test('effect.add executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'clipId': 'clip_1',
        'effectType': 'gaussian_blur',
      };

      final result = await registry.execute('effect.add', params, context);

      expect(result.success, isTrue);
      expect(testClip.effects.length, equals(1));
      expect(testClip.effects[0].type, equals('gaussian_blur'));
      
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });

    test('effect.set_parameter executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      testClip.effects.add(EffectState(
        id: 'effect_1',
        type: 'gaussian_blur',
        name: 'Gaussian Blur',
        parameters: GaussianBlurParameters(radius: 10.0),
      ));

      final params = {
        'clipId': 'clip_1',
        'effectId': 'effect_1',
        'parameter': 'radius',
        'value': 25.0,
      };

      final result = await registry.execute('effect.set_parameter', params, context);

      expect(result.success, isTrue);
      expect((testClip.effects[0].parameters as GaussianBlurParameters).radius, equals(25.0));
      
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });
  });
}
