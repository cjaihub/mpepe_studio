import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_tool_registry.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_context_resolver.dart';
import 'package:oneova/backend/ai_agents/omni_command/tools/color_tools.dart';
import 'package:oneova/backend/projects/models/pro_project_models.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

import 'color_tools_test.mocks.dart';

@GenerateMocks([ProjectRepository])
void main() {
  group('Color Tools Tests', () {
    late OmniToolRegistry registry;
    late MockProjectRepository mockProjectRepo;
    late StudioProject testProject;
    late Sequence testSequence;
    late Clip testClip;

    setUp(() {
      registry = OmniToolRegistry();
      mockProjectRepo = MockProjectRepository();

      registerColorTools(registry, mockProjectRepo);

      testClip = Clip(
        id: 'clip_1',
        sourceMediaId: 'asset_1',
        type: MediaType.video,
        startTime: 0,
        duration: 5000,
        sourceStart: 0,
        color: ColorState(
          exposure: 0.0,
          contrast: 1.0,
          highlights: 0.0,
          lutStack: [],
        ),
        secondaryColorStates: [],
      );

      testSequence = Sequence(
        id: 'seq_1',
        name: 'seq 1',
        settings: ProjectSettings(width: 1080, height: 1920, frameRate: 30),
        tracks: [
          Track(
            name: 'main',
            type: TrackType.video,
            clips: [testClip],
          ),
        ],
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

    test('color.set_exposure executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'projectId': 'proj_1',
        'sequenceId': 'seq_1',
        'clipId': 'clip_1',
        'value': 1.5,
      };

      final result = await registry.execute('color.set_exposure', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(testClip.color.exposure, equals(1.5));
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });

    test('color.set_contrast executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'projectId': 'proj_1',
        'sequenceId': 'seq_1',
        'clipId': 'clip_1',
        'value': 1.8,
      };

      final result = await registry.execute('color.set_contrast', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(testClip.color.contrast, equals(1.8));
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });

    test('color.apply_lut executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'projectId': 'proj_1',
        'sequenceId': 'seq_1',
        'clipId': 'clip_1',
        'lutId': 'cinematic',
        'intensity': 0.8,
      };

      final result = await registry.execute('color.apply_lut', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(testClip.color.lutStack.length, equals(1));
      expect(testClip.color.lutStack.first.intensity, equals(0.8));
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });

    test('color.create_secondary_grade executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'projectId': 'proj_1',
        'sequenceId': 'seq_1',
        'clipId': 'clip_1',
        'targetMaskId': 'semantic_face',
      };

      final result = await registry.execute('color.create_secondary_grade', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(testClip.secondaryColorStates.length, equals(1));
      expect(testClip.secondaryColorStates.first.targetMaskId, equals('semantic_face'));
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });
    test('color.set_highlights executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'projectId': 'proj_1',
        'sequenceId': 'seq_1',
        'clipId': 'clip_1',
        'value': -0.5,
      };

      final result = await registry.execute('color.set_highlights', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(testClip.color.highlights, equals(-0.5));
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });

    test('color.apply_preset executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'projectId': 'proj_1',
        'sequenceId': 'seq_1',
        'clipId': 'clip_1',
        'presetId': 'cinematic',
      };

      final result = await registry.execute('color.apply_preset', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(testClip.color.exposure, equals(0.1));
      expect(testClip.color.contrast, equals(1.1));
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });
  });
}
