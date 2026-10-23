import 'package:uuid/uuid.dart';
import '../../../../backend/projects/models/pro_project_models.dart';
import '../../../../backend/projects/models/effect_models.dart';
import '../../../../backend/projects/models/effect_registry.dart';
import '../../../../backend/project_repository.dart';
import '../omni_tool_registry.dart';
import '../omni_context_resolver.dart';
import '../omni_risk_engine.dart';

void registerEffectTools(OmniToolRegistry registry, ProjectRepository projectRepo) {
  
  Future<ToolResult> handleEffectMutation(
    String toolId,
    Map<String, dynamic> params,
    OmniContext context,
    String operationName,
    void Function(Clip clip, String executionId) mutate,
    Map<String, dynamic> Function() buildData,
    String Function(String executionId) buildMessage,
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
        errorMessage: 'projectId, sequenceId, and clipId are required.',
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

      final sequence = project.sequences.firstWhere((s) => s.id == sequenceId);
      Clip? targetClip;
      for (var track in sequence.tracks) {
        final idx = track.clips.indexWhere((c) => c.id == clipId);
        if (idx != -1) {
          targetClip = track.clips[idx];
          break;
        }
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

      final executionId = const Uuid().v4();
      
      mutate(targetClip, executionId);

      await projectRepo.updateProject(project);

      return ToolResult(
        executionId: executionId,
        toolId: toolId,
        success: true,
        data: buildData(),
        statusMessage: buildMessage(executionId),
        executionState: ToolExecutionState.completed,
      );
    } catch (e) {
      return ToolResult(
        executionId: const Uuid().v4(),
        toolId: toolId,
        success: false,
        data: {},
        statusMessage: 'Failed operation.',
        errorMessage: e.toString(),
        executionState: ToolExecutionState.failed,
      );
    }
  }

  // effect.add
  registry.register(
    const OmniToolDefinition(
      toolId: 'effect.add',
      name: 'Add Effect',
      description: 'Adds an effect to the clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'effectType'],
        'properties': {
          'clipId': {'type': 'string'},
          'effectType': {'type': 'string'},
          'maskId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final effectType = params['effectType'] as String;
      final maskId = params['maskId'] as String?;
      
      final def = EffectRegistry().getEffectById(effectType);
      if (def == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'effect.add',
          success: false,
          data: {},
          statusMessage: 'Effect not supported.',
          errorMessage: 'INVALID_EFFECT_TYPE',
          executionState: ToolExecutionState.failed,
        );
      }

      String newEffectId = const Uuid().v4();

      return handleEffectMutation(
        'effect.add',
        params,
        context,
        'Add Effect',
        (clip, executionId) {
          final effect = EffectRegistry().createEffect(effectType);
          final finalEffect = effect.copyWith(
            id: newEffectId,
            maskId: maskId,
            order: clip.effects.length,
          );
          clip.effects.add(finalEffect);
        },
        () => {'effectId': newEffectId, 'type': effectType},
        (execId) => 'Added $effectType effect.',
      );
    },
  );

  // effect.remove
  registry.register(
    const OmniToolDefinition(
      toolId: 'effect.remove',
      name: 'Remove Effect',
      description: 'Removes an effect from the clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'effectId'],
        'properties': {
          'clipId': {'type': 'string'},
          'effectId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final effectId = params['effectId'];
      return handleEffectMutation(
        'effect.remove',
        params,
        context,
        'Remove Effect',
        (clip, executionId) {
          clip.effects.removeWhere((e) => e.id == effectId);
        },
        () => {'effectId': effectId},
        (execId) => 'Removed effect.',
      );
    },
  );

  // effect.enable
  registry.register(
    const OmniToolDefinition(
      toolId: 'effect.enable',
      name: 'Enable Effect',
      description: 'Enables an effect on the clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'effectId'],
        'properties': {
          'clipId': {'type': 'string'},
          'effectId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final effectId = params['effectId'];
      return handleEffectMutation(
        'effect.enable',
        params,
        context,
        'Enable Effect',
        (clip, executionId) {
          final idx = clip.effects.indexWhere((e) => e.id == effectId);
          if (idx != -1) {
            clip.effects[idx] = clip.effects[idx].copyWith(enabled: true);
          }
        },
        () => {'effectId': effectId},
        (execId) => 'Enabled effect.',
      );
    },
  );

  // effect.disable
  registry.register(
    const OmniToolDefinition(
      toolId: 'effect.disable',
      name: 'Disable Effect',
      description: 'Disables an effect on the clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'effectId'],
        'properties': {
          'clipId': {'type': 'string'},
          'effectId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final effectId = params['effectId'];
      return handleEffectMutation(
        'effect.disable',
        params,
        context,
        'Disable Effect',
        (clip, executionId) {
          final idx = clip.effects.indexWhere((e) => e.id == effectId);
          if (idx != -1) {
            clip.effects[idx] = clip.effects[idx].copyWith(enabled: false);
          }
        },
        () => {'effectId': effectId},
        (execId) => 'Disabled effect.',
      );
    },
  );

  // effect.reorder
  registry.register(
    const OmniToolDefinition(
      toolId: 'effect.reorder',
      name: 'Reorder Effect',
      description: 'Reorders an effect within the clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'effectId', 'newOrder'],
        'properties': {
          'clipId': {'type': 'string'},
          'effectId': {'type': 'string'},
          'newOrder': {'type': 'integer'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final effectId = params['effectId'];
      final newOrder = params['newOrder'] as int;
      return handleEffectMutation(
        'effect.reorder',
        params,
        context,
        'Reorder Effect',
        (clip, executionId) {
          final idx = clip.effects.indexWhere((e) => e.id == effectId);
          if (idx != -1) {
            final effect = clip.effects.removeAt(idx);
            int insertIndex = newOrder;
            if (insertIndex < 0) insertIndex = 0;
            if (insertIndex > clip.effects.length) insertIndex = clip.effects.length;
            clip.effects.insert(insertIndex, effect);
            
            // Reassign orders
            for (int i = 0; i < clip.effects.length; i++) {
              clip.effects[i] = clip.effects[i].copyWith(order: i);
            }
          }
        },
        () => {'effectId': effectId, 'newOrder': newOrder},
        (execId) => 'Reordered effect.',
      );
    },
  );

  // effect.duplicate
  registry.register(
    const OmniToolDefinition(
      toolId: 'effect.duplicate',
      name: 'Duplicate Effect',
      description: 'Duplicates an effect within the clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'effectId'],
        'properties': {
          'clipId': {'type': 'string'},
          'effectId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final effectId = params['effectId'];
      String newEffectId = const Uuid().v4();
      
      return handleEffectMutation(
        'effect.duplicate',
        params,
        context,
        'Duplicate Effect',
        (clip, executionId) {
          final idx = clip.effects.indexWhere((e) => e.id == effectId);
          if (idx != -1) {
            final effect = clip.effects[idx];
            final duplicated = effect.copyWith(
              id: newEffectId,
              order: clip.effects.length,
            );
            clip.effects.add(duplicated);
          }
        },
        () => {'originalEffectId': effectId, 'newEffectId': newEffectId},
        (execId) => 'Duplicated effect.',
      );
    },
  );

  // effect.set_parameter
  registry.register(
    const OmniToolDefinition(
      toolId: 'effect.set_parameter',
      name: 'Set Effect Parameter',
      description: 'Sets a specific parameter on an effect.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'effectId', 'parameter', 'value'],
        'properties': {
          'clipId': {'type': 'string'},
          'effectId': {'type': 'string'},
          'parameter': {'type': 'string'},
          'value': {},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final effectId = params['effectId'];
      final parameter = params['parameter'] as String;
      final value = params['value'];
      
      return handleEffectMutation(
        'effect.set_parameter',
        params,
        context,
        'Set Effect Parameter',
        (clip, executionId) {
          final idx = clip.effects.indexWhere((e) => e.id == effectId);
          if (idx != -1) {
            final effect = clip.effects[idx];
            final json = effect.parameters.toJson();
            json[parameter] = value;
            
            EffectParameters newParams;
            switch (effect.type) {
              case 'gaussian_blur':
                newParams = GaussianBlurParameters.fromJson(json);
                break;
              case 'glow':
                newParams = GlowParameters.fromJson(json);
                break;
              case 'chroma_key':
                newParams = ChromaKeyParameters.fromJson(json);
                break;
              case 'sharpen':
                newParams = SharpenParameters.fromJson(json);
                break;
              case 'motion_preset_zoom':
                newParams = MotionPresetParameters.fromJson(json);
                break;
              default:
                newParams = GenericEffectParameters.fromJson(json);
                break;
            }
            
            clip.effects[idx] = effect.copyWith(parameters: newParams);
          }
        },
        () => {'effectId': effectId, 'parameter': parameter, 'value': value},
        (execId) => 'Updated effect parameter.',
      );
    },
  );

}
