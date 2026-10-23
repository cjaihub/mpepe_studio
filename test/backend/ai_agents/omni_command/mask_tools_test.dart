import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_tool_registry.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_context_resolver.dart';
import 'package:oneova/backend/ai_agents/omni_command/tools/mask_tools.dart';
import 'package:oneova/backend/projects/models/pro_project_models.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:oneova/backend/mask_engine/universal_mask_models.dart';
import 'package:mockito/mockito.dart';

import 'color_tools_test.mocks.dart';

void main() {
  group('Mask Tools Registry Tests', () {
    late OmniToolRegistry registry;
    late MockProjectRepository mockRepo;
    late StudioProject testProject;
    late Sequence testSequence;
    late Clip testClip;

    setUp(() {
      registry = OmniToolRegistry();
      mockRepo = MockProjectRepository();

      registerMaskTools(registry, mockRepo);

      testClip = Clip(
        id: 'clip-1',
        sourceMediaId: 'media-1',
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
        masks: [],
      );

      testSequence = Sequence(
        id: 'seq-1',
        name: 'Main Sequence',
        settings: ProjectSettings(width: 1080, height: 1920, frameRate: 30),
        tracks: [
          Track(
            name: 'track-1',
            type: TrackType.video,
            clips: [testClip],
          ),
        ],
      );

      testProject = StudioProject(
        id: 'proj-1',
        ownerId: 'user-1',
        title: 'Test Project',
        category: 'Video',
        status: 'Editing',
        completedSteps: 0,
        createdAt: DateTime.now(),
        sequences: [testSequence],
      );

      when(mockRepo.getProject('proj-1')).thenAnswer((_) async => testProject);
      when(mockRepo.updateProject(any)).thenAnswer((_) async {});
    });

    test('select_subject creates a semantic mask', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user-1',
        surface: 'pro_editor',
        projectId: 'proj-1',
        sequenceId: 'seq-1',
        clipId: 'clip-1',
      );

      final result = await registry.execute('mask.select_subject', {
        'projectId': 'proj-1',
        'sequenceId': 'seq-1',
        'clipId': 'clip-1',
      }, context);

      expect(result.success, isTrue);
      
      expect(testClip.masks.length, 1);
      final newMask = testClip.masks.first;
      expect(newMask.maskType, MaskType.SUBJECT);
      expect(newMask.sourceType, MaskSourceType.ai);
      expect(result.statusMessage, 'Created Select Subject mask.');
      
      verify(mockRepo.updateProject(testProject)).called(1);
    });

    test('track enables tracking on an existing mask', () async {
      final initialMask = UniversalMask(
        id: 'mask-to-track',
        projectId: 'proj-1',
        mediaId: 'media-1',
        maskType: MaskType.PERSON,
        sourceType: MaskSourceType.manual,
        createdBy: 'omni_command',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      testClip.masks.add(initialMask);
      
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user-1',
        surface: 'pro_editor',
        projectId: 'proj-1',
        sequenceId: 'seq-1',
        clipId: 'clip-1',
      );

      final result = await registry.execute('mask.track', {
        'projectId': 'proj-1',
        'sequenceId': 'seq-1',
        'clipId': 'clip-1',
        'targetMaskId': 'mask-to-track',
      }, context);

      expect(result.success, isTrue);
      
      expect(testClip.masks.first.trackingReference, startsWith('auto_tracked_'));
      verify(mockRepo.updateProject(testProject)).called(1);
    });

    test('invert toggles mask inversion', () async {
      final initialMask = UniversalMask(
        id: 'mask-to-invert',
        projectId: 'proj-1',
        mediaId: 'media-1',
        maskType: MaskType.FACE,
        sourceType: MaskSourceType.manual,
        inversion: false,
        createdBy: 'omni_command',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      testClip.masks.add(initialMask);
      
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user-1',
        surface: 'pro_editor',
        projectId: 'proj-1',
        sequenceId: 'seq-1',
        clipId: 'clip-1',
      );

      final result = await registry.execute('mask.invert', {
        'projectId': 'proj-1',
        'sequenceId': 'seq-1',
        'clipId': 'clip-1',
        'targetMaskId': 'mask-to-invert',
      }, context);

      expect(result.success, isTrue);
      
      expect(testClip.masks.first.inversion, isTrue);
      verify(mockRepo.updateProject(testProject)).called(1);
    });

    test('refine_subtract sets operation to subtract', () async {
      final initialMask = UniversalMask(
        id: 'mask-to-subtract',
        projectId: 'proj-1',
        mediaId: 'media-1',
        maskType: MaskType.SKY,
        sourceType: MaskSourceType.manual,
        operation: MaskOperation.add,
        createdBy: 'omni_command',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      testClip.masks.add(initialMask);
      
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user-1',
        surface: 'pro_editor',
        projectId: 'proj-1',
        sequenceId: 'seq-1',
        clipId: 'clip-1',
      );

      final result = await registry.execute('mask.refine_subtract', {
        'projectId': 'proj-1',
        'sequenceId': 'seq-1',
        'clipId': 'clip-1',
        'targetMaskId': 'mask-to-subtract',
      }, context);

      expect(result.success, isTrue);
      
      expect(testClip.masks.first.operation, MaskOperation.subtract);
      verify(mockRepo.updateProject(testProject)).called(1);
    });

  });
}
