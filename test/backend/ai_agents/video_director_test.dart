import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oneova/backend/ai_agents/video_director_models.dart';
import 'package:oneova/backend/ai_agents/video_director_service.dart';
import 'package:oneova/backend/ai_agents/openrouter_agent_service.dart';
import 'package:oneova/backend/media_infrastructure/services/video_project_service.dart';
import 'package:oneova/backend/media_infrastructure/models/video_project_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VideoProjectService projectService;
  late OpenRouterAgentService agentService;
  late VideoDirectorService directorService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    projectService = VideoProjectService();
    agentService = OpenRouterAgentService();
    directorService = VideoDirectorService(agentService, projectService);

    // Setup dummy project
    await projectService.createProject('user123', 'Raw Footage');
    final track = Track(id: 'video_track_1', type: TrackType.video);
    projectService.addTrack(track);
    projectService.addClip(track.id, Clip(
      sourceMediaId: 'media_A',
      sourceStartTime: const Duration(seconds: 0),
      sourceEndTime: const Duration(seconds: 15),
      timelineStartTime: const Duration(seconds: 0),
    ));
  });

  test('AI Director generates structured plan without modifying project silently', () async {
    final originalClipsCount = projectService.currentProject!.timeline.tracks.first.clips.length;
    final originalDuration = projectService.currentProject!.timeline.tracks.first.clips.first.duration;

    final plan = await directorService.analyzeProject(projectService.currentProject!.id);

    // Assert plan is generated but project is UNTOUCHED
    expect(plan.status, PlanStatus.pending);
    expect(plan.suggestions.isNotEmpty, true);
    
    final currentDuration = projectService.currentProject!.timeline.tracks.first.clips.first.duration;
    final currentClipsCount = projectService.currentProject!.timeline.tracks.first.clips.length;
    expect(currentDuration, originalDuration);
    expect(currentClipsCount, originalClipsCount);
    // Assert Audit Log recorded the generation
    expect(directorService.auditLog.length, 1);
    expect(directorService.auditLog.first.action, 'PLAN_GENERATED');
  });

  test('AI Director applying a plan modifies project and creates audit log', () async {
    final plan = await directorService.analyzeProject(projectService.currentProject!.id);
    
    // Apply the plan explicitly
    await directorService.applyPlan(plan);

    expect(plan.status, PlanStatus.applied);
    
    // The dummy plan cuts from 3s to 8s (duration 5s)
    final modifiedClip = projectService.currentProject!.timeline.tracks.first.clips.first;
    expect(modifiedClip.duration.inSeconds, 5);
    
    // Audit log should have generation and application records
    expect(directorService.auditLog.length, 2);
    expect(directorService.auditLog.last.action, 'PLAN_APPLIED');
  });

  test('AI Director can reject a plan', () async {
    final plan = await directorService.analyzeProject(projectService.currentProject!.id);
    directorService.rejectPlan(plan);
    
    expect(plan.status, PlanStatus.rejected);
    expect(directorService.auditLog.last.action, 'PLAN_REJECTED');
  });
}
