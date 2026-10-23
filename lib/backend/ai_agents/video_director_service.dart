import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'video_director_models.dart';
import 'openrouter_agent_service.dart';
import '../media_infrastructure/services/video_project_service.dart';
import '../media_infrastructure/models/video_project_models.dart';

final videoDirectorServiceProvider = Provider<VideoDirectorService>((ref) {
  return VideoDirectorService(
    ref.read(openRouterAgentServiceProvider),
    ref.read(videoProjectServiceProvider),
  );
});

class VideoDirectorService {
  // ignore: unused_field
  final OpenRouterAgentService _aiAgent;
  final VideoProjectService _projectService;
  
  // In-memory audit log for simplicity, usually persisted to Firestore or SQLite
  final List<AiAuditRecord> _auditLog = [];

  VideoDirectorService(this._aiAgent, this._projectService);

  List<AiAuditRecord> get auditLog => List.unmodifiable(_auditLog);

  /// 1. Analyze the project and generate a structured Plan
  /// Never modifies the project destructively.
  Future<VideoDirectorPlan> analyzeProject(String projectId) async {
    // Note: In reality, we would extract the timeline metadata and pass it to _aiAgent
    // For this implementation, we simulate the LLM returning a structured JSON plan.
    
    // final projectMetadata = _projectService.currentProject?.toMap() ?? {};
    // final rawResponse = await _aiAgent.generateStructuredPlan(projectMetadata);
    
    // Simulated Structured Response from AI
    final simulatedPlan = VideoDirectorPlan(
      projectId: projectId,
      suggestedTitle: "Epic Cinematic Vlog",
      suggestedDescription: "A breathtaking journey edited entirely by AI.",
      suggestions: [
        AiEditSuggestion(
          action: AiEditAction.cut,
          description: "Cut out dead air at the start",
          parameters: {'trackId': 'video_track_1', 'clipIndex': 0, 'newStartMs': 3000, 'newEndMs': 8000},
        ),
        AiEditSuggestion(
          action: AiEditAction.addCaption,
          description: "Add hook text",
          parameters: {'text': 'You won\'t believe this!', 'startMs': 3000, 'endMs': 5000},
        ),
        AiEditSuggestion(
          action: AiEditAction.adjustVolume,
          description: "Lower music during dialogue",
          parameters: {'trackType': 'audio', 'volume': 0.2, 'startMs': 5000},
        ),
      ],
    );

    _logAudit(simulatedPlan.id, projectId, 'PLAN_GENERATED', {
      'suggestionsCount': simulatedPlan.suggestions.length
    });

    return simulatedPlan;
  }

  /// 2. Apply the plan sequentially
  /// User explicitly authorizes this action.
  Future<void> applyPlan(VideoDirectorPlan plan) async {
    if (plan.status != PlanStatus.pending && plan.status != PlanStatus.previewing) {
      throw Exception('Plan is already applied or rejected.');
    }

    final project = _projectService.currentProject;
    if (project == null || project.id != plan.projectId) {
      throw Exception('Project not loaded or mismatch.');
    }

    for (final suggestion in plan.suggestions) {
      _applySuggestion(suggestion);
    }

    plan.status = PlanStatus.applied;
    plan.appliedAt = DateTime.now();

    _logAudit(plan.id, plan.projectId, 'PLAN_APPLIED', {
      'appliedCount': plan.suggestions.length
    });
  }

  void rejectPlan(VideoDirectorPlan plan) {
    plan.status = PlanStatus.rejected;
    _logAudit(plan.id, plan.projectId, 'PLAN_REJECTED', {});
  }

  void _applySuggestion(AiEditSuggestion suggestion) {
    // Translate AI actions into exact VideoProjectService methods
    // We wrap this so it uses the standard undo/redo stack
    final params = suggestion.parameters;
    final project = _projectService.currentProject!;
    
    switch (suggestion.action) {
      case AiEditAction.cut:
        if (params.containsKey('trackId') && params.containsKey('clipIndex')) {
          final track = project.timeline.tracks.firstWhere((t) => t.id == params['trackId'], orElse: () => Track(type: TrackType.video));
          if (track.clips.isNotEmpty && params['clipIndex'] < track.clips.length) {
            final clip = track.clips[params['clipIndex']];
            _projectService.trimClip(
              track.id, 
              clip.id, 
              Duration(milliseconds: params['newStartMs']), 
              Duration(milliseconds: params['newEndMs'])
            );
          }
        }
        break;
      case AiEditAction.addCaption:
        // Implementation to add a text track clip
        break;
      case AiEditAction.adjustVolume:
        // Implementation to iterate through audio track and split/lower volume
        break;
      default:
        break;
    }
  }

  void _logAudit(String planId, String projectId, String action, Map<String, dynamic> details) {
    _auditLog.add(AiAuditRecord(
      planId: planId,
      projectId: projectId,
      action: action,
      details: details,
    ));
    // Print to console for verification
    // ignore: avoid_print
    print('AI_AUDIT [$action]: Project $projectId, Plan $planId, Details: $details');
  }
}
