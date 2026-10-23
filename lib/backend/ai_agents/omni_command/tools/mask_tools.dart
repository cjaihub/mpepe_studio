import 'package:uuid/uuid.dart';
import '../../../../backend/projects/models/pro_project_models.dart';
import '../../../../backend/project_repository.dart';
import '../omni_tool_registry.dart';
import '../omni_context_resolver.dart';
import '../omni_risk_engine.dart';
import '../../../../backend/mask_engine/universal_mask_models.dart';

void registerMaskTools(OmniToolRegistry registry, ProjectRepository projectRepo) {

  Future<ToolResult> handleMaskMutation(
    String toolId,
    Map<String, dynamic> params,
    OmniContext context,
    String operationName,
    void Function(Clip clip, String newMaskId) mutate,
    Map<String, dynamic> Function() buildData,
    String Function(String newMaskId) buildMessage,
  ) async {
    final projectId = context.projectId ?? params['projectId'];
    final sequenceId = context.sequenceId ?? params['sequenceId'];
    final clipId = params['clipId'];

    if (projectId == null || sequenceId == null || clipId == null) {
      return ToolResult(
        executionId: const Uuid().v4(),
        toolId: toolId,
        success: false,
        data: {},
        statusMessage: 'Missing context.',
        errorMessage: 'MISSING_CONTEXT: projectId, sequenceId, and clipId are required.',
        executionState: ToolExecutionState.failed,
      );
    }

    try {
      final project = await projectRepo.getProject(projectId);
      if (project == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: toolId,
          success: false,
          data: {},
          statusMessage: 'Project not found.',
          errorMessage: 'PROJECT_NOT_FOUND',
          executionState: ToolExecutionState.failed,
        );
      }

      final sequence = project.sequences.firstWhere((s) => s.id == sequenceId, orElse: () => throw Exception('Sequence not found'));
      Clip? targetClip;
      for (var track in sequence.tracks) {
        try {
          targetClip = track.clips.firstWhere((c) => c.id == clipId);
          break;
        } catch (_) {}
      }

      if (targetClip == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: toolId,
          success: false,
          data: {},
          statusMessage: 'Clip not found.',
          errorMessage: 'CLIP_NOT_FOUND',
          executionState: ToolExecutionState.failed,
        );
      }

      final newMaskId = const Uuid().v4();
      
      mutate(targetClip, newMaskId);

      await projectRepo.updateProject(project);

      return ToolResult(
        executionId: const Uuid().v4(),
        toolId: toolId,
        success: true,
        data: buildData(),
        statusMessage: buildMessage(newMaskId),
        executionState: ToolExecutionState.completed,
      );
    } catch (e) {
      return ToolResult(
        executionId: const Uuid().v4(),
        toolId: toolId,
        success: false,
        data: {},
        statusMessage: 'Failed to apply mask mutation.',
        errorMessage: e.toString(),
        executionState: ToolExecutionState.failed,
      );
    }
  }

  // Helper to create basic selection masks
  void registerSelectionTool(String toolId, String name, MaskType maskType) {
    registry.register(
      OmniToolDefinition(
        toolId: toolId,
        name: name,
        description: 'Automatically creates a semantic mask for $name.',
        inputSchema: {
          'type': 'object',
          'required': ['clipId'],
          'properties': {
            'clipId': {'type': 'string'},
          },
        },
        outputSchema: {'type': 'object'},
        requiredPermission: ToolPermission.execute,
        riskLevel: RiskLevel.low,
        requiresConfirmation: true,
        supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
      ),
      (params, context) async {
        return handleMaskMutation(
          toolId,
          params,
          context,
          name,
          (clip, newMaskId) {
            clip.masks.add(UniversalMask(
              id: newMaskId,
              name: 'Semantic $name',
              projectId: context.projectId ?? params['projectId'] ?? 'auto',
              mediaId: clip.sourceMediaId,
              maskType: maskType,
              sourceType: MaskSourceType.ai,
              createdBy: 'omni_command',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));
          },
          () => {
            'maskType': maskType.name,
            'sourceType': 'ai',
          },
          (newMaskId) => 'Created $name mask.',
        );
      },
    );
  }

  registerSelectionTool('mask.select_subject', 'Select Subject', MaskType.SUBJECT);
  registerSelectionTool('mask.select_person', 'Select Person', MaskType.PERSON);
  registerSelectionTool('mask.select_face', 'Select Face', MaskType.FACE);
  registerSelectionTool('mask.select_sky', 'Select Sky', MaskType.SKY);

  // mask.refine_add
  registry.register(
    const OmniToolDefinition(
      toolId: 'mask.refine_add',
      name: 'Refine Add',
      description: 'Adds an operation to a mask.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'targetMaskId'],
        'properties': {
          'clipId': {'type': 'string'},
          'targetMaskId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final targetMaskId = params['targetMaskId'];
      return handleMaskMutation(
        'mask.refine_add',
        params,
        context,
        'Refine Add',
        (clip, newMaskId) {
          final maskIndex = clip.masks.indexWhere((m) => m.id == targetMaskId);
          if (maskIndex != -1) {
            final old = clip.masks[maskIndex];
            clip.masks[maskIndex] = old.copyWith(
              operation: MaskOperation.add,
              updatedAt: DateTime.now(),
            );
          }
        },
        () => {'targetMaskId': targetMaskId, 'operation': 'add'},
        (newMaskId) => 'Refined mask to add mode.',
      );
    },
  );

  // mask.refine_subtract
  registry.register(
    const OmniToolDefinition(
      toolId: 'mask.refine_subtract',
      name: 'Refine Subtract',
      description: 'Subtracts from a mask.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'targetMaskId'],
        'properties': {
          'clipId': {'type': 'string'},
          'targetMaskId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final targetMaskId = params['targetMaskId'];
      return handleMaskMutation(
        'mask.refine_subtract',
        params,
        context,
        'Refine Subtract',
        (clip, newMaskId) {
          final maskIndex = clip.masks.indexWhere((m) => m.id == targetMaskId);
          if (maskIndex != -1) {
            final old = clip.masks[maskIndex];
            clip.masks[maskIndex] = old.copyWith(
              operation: MaskOperation.subtract,
              updatedAt: DateTime.now(),
            );
          }
        },
        () => {'targetMaskId': targetMaskId, 'operation': 'subtract'},
        (newMaskId) => 'Refined mask to subtract mode.',
      );
    },
  );

  // mask.invert
  registry.register(
    const OmniToolDefinition(
      toolId: 'mask.invert',
      name: 'Invert Mask',
      description: 'Inverts the mask.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'targetMaskId'],
        'properties': {
          'clipId': {'type': 'string'},
          'targetMaskId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final targetMaskId = params['targetMaskId'];
      return handleMaskMutation(
        'mask.invert',
        params,
        context,
        'Invert Mask',
        (clip, newMaskId) {
          final maskIndex = clip.masks.indexWhere((m) => m.id == targetMaskId);
          if (maskIndex != -1) {
            final old = clip.masks[maskIndex];
            clip.masks[maskIndex] = old.copyWith(
              inversion: !old.inversion,
              updatedAt: DateTime.now(),
            );
          }
        },
        () => {'targetMaskId': targetMaskId},
        (newMaskId) => 'Inverted mask $targetMaskId.',
      );
    },
  );

  // mask.track
  registry.register(
    const OmniToolDefinition(
      toolId: 'mask.track',
      name: 'Track Mask',
      description: 'Enables tracking for the mask.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'targetMaskId'],
        'properties': {
          'clipId': {'type': 'string'},
          'targetMaskId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final targetMaskId = params['targetMaskId'];
      return handleMaskMutation(
        'mask.track',
        params,
        context,
        'Track Mask',
        (clip, newMaskId) {
          final maskIndex = clip.masks.indexWhere((m) => m.id == targetMaskId);
          if (maskIndex != -1) {
            final old = clip.masks[maskIndex];
            clip.masks[maskIndex] = old.copyWith(
              trackingReference: 'auto_tracked_\${DateTime.now().millisecondsSinceEpoch}',
              updatedAt: DateTime.now(),
            );
          }
        },
        () => {'targetMaskId': targetMaskId},
        (newMaskId) => 'Enabled tracking on mask $targetMaskId.',
      );
    },
  );

}
