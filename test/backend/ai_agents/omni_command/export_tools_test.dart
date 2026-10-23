import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_tool_registry.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_context_resolver.dart';
import 'package:oneova/backend/ai_agents/omni_command/tools/export_tools.dart';
import 'package:oneova/backend/projects/models/pro_project_models.dart';
import 'package:oneova/backend/project_repository.dart';
import 'package:mockito/mockito.dart';

import 'color_tools_test.mocks.dart';

void main() {
  group('Export Tools Tests', () {
    late OmniToolRegistry registry;
    late MockProjectRepository mockProjectRepo;
    late StudioProject testProject;
    late Sequence testSequence;

    setUp(() {
      registry = OmniToolRegistry();
      mockProjectRepo = MockProjectRepository();

      registerExportTools(registry, mockProjectRepo);

      testSequence = Sequence(
        id: 'seq_1',
        name: 'seq 1',
        settings: ProjectSettings(width: 1080, height: 1920, frameRate: 30),
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
    });

    test('export.preview executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
      );

      final params = {
        'resolution': '720p',
      };

      final result = await registry.execute('export.preview', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(result.data.containsKey('isSuccess'), isTrue);
      expect(result.data['resolution'], equals('720p'));
    });

    test('export.render executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
      );

      final params = {
        'codec': 'H.264',
        'resolution': '4K',
      };

      final result = await registry.execute('export.render', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(result.data.containsKey('jobId'), isTrue);
      expect(result.data['codec'], equals('H.264'));
      expect(result.data['resolution'], equals('4K'));
    });

    test('export.cancel executes successfully', () async {
      final context = OmniContext(
        sessionId: 'session_1',
        userId: 'user_1',
        projectId: 'proj_1',
        sequenceId: 'seq_1',
      );

      final params = {
        'jobId': 'job_123',
      };

      final result = await registry.execute('export.cancel', params, context);

      if (!result.success) print(result.errorMessage);
      expect(result.success, isTrue);
      expect(result.data['jobId'], equals('job_123'));
      expect(result.data['status'], equals('cancelled'));
    });
  });
}
