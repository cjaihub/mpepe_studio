import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_tool_registry.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_context_resolver.dart';
import 'package:oneova/backend/ai_agents/omni_command/tools/timeline_tools.dart';
import 'package:oneova/backend/projects/models/pro_project_models.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:mockito/mockito.dart';

import 'color_tools_test.mocks.dart'; // Reuse the mock from color tools

void main() {
  group('Timeline Tools Tests', () {
    late OmniToolRegistry registry;
    late MockProjectRepository mockProjectRepo;
    late StudioProject testProject;
    late Sequence testSequence;
    late Track testTrack;
    late Clip testClip;

    setUp(() {
      registry = OmniToolRegistry();
      mockProjectRepo = MockProjectRepository();

      registerTimelineTools(registry, mockProjectRepo);

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

    test('timeline.split_clip executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'clipId': 'clip_1',
        'playhead': 12.0,
      };

      final result = await registry.execute('timeline.split_clip', params, context);

      expect(result.success, isTrue);
      
      expect(testTrack.clips.length, equals(2));
      
      final leftClip = testTrack.clips[0];
      final rightClip = testTrack.clips[1];
      
      expect(leftClip.id, equals('clip_1'));
      expect(leftClip.startTime, equals(10.0));
      expect(leftClip.duration, equals(2.0));
      
      expect(rightClip.id, isNot(equals('clip_1')));
      expect(rightClip.startTime, equals(12.0));
      expect(rightClip.duration, equals(3.0));
      expect(rightClip.sourceStart, equals(2.0));
      
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });

    test('timeline.trim_clip executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'clipId': 'clip_1',
        'newStart': 11.0,
      };

      final result = await registry.execute('timeline.trim_clip', params, context);

      expect(result.success, isTrue);
      expect(testClip.startTime, equals(11.0));
      expect(testClip.sourceStart, equals(1.0));
      expect(testClip.duration, equals(4.0));
      
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });

    test('timeline.move_clip executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
        clipId: 'clip_1',
      );

      final params = {
        'clipId': 'clip_1',
        'delta': 2.0,
      };

      final result = await registry.execute('timeline.move_clip', params, context);

      expect(result.success, isTrue);
      expect(testClip.startTime, equals(12.0));
      
      verify(mockProjectRepo.updateProject(testProject)).called(1);
    });
  });
}
