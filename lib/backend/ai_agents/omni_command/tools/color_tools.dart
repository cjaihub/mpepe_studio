import 'package:uuid/uuid.dart';
import '../../../../backend/projects/models/pro_project_models.dart';
import '../../../../backend/project_repository.dart';
import '../omni_tool_registry.dart';
import '../omni_context_resolver.dart';
import '../omni_risk_engine.dart';
import '../../../../backend/projects/services/color_libraries.dart';

void registerColorTools(OmniToolRegistry registry, ProjectRepository projectRepo) {
  // Audit will be handled by OmniCommandService

  Future<ToolResult> handleColorMutation(
    String toolId,
    Map<String, dynamic> params,
    OmniContext context,
    String operationName,
    void Function(ColorState colorState) mutate,
    Map<String, dynamic> Function(ColorState oldState, ColorState newState) buildData,
    String Function(ColorState oldState, ColorState newState) buildMessage,
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

      final sequence = project.sequences.cast<Sequence?>().firstWhere((s) => s?.id == sequenceId, orElse: () => null);
      if (sequence == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: toolId,
          success: false,
          data: {},
          statusMessage: 'Sequence not found.',
          errorMessage: 'SEQUENCE_NOT_FOUND',
          executionState: ToolExecutionState.failed,
        );
      }

      final clip = sequence.tracks.expand((dynamic t) => (t.clips as Iterable).cast<dynamic>()).cast<Clip?>().firstWhere((c) => c?.id == clipId, orElse: () => null);
      if (clip == null) {
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

      // Clone ColorState for rollback or old value diffing
      final oldColorState = ColorState.fromJson(clip.color.toJson());
      
      // Apply mutation
      mutate(clip.color);

      // Persist
      await projectRepo.updateProject(project);

      // Audit handled generically outside.

      final data = buildData(oldColorState, clip.color);
      final message = buildMessage(oldColorState, clip.color);
      
      return ToolResult(
        executionId: const Uuid().v4(),
        toolId: toolId,
        success: true,
        data: {
          ...data,
          'clipId': clipId,
          'changedObjects': [
            {'type': 'clip', 'id': clipId}
          ],
          'undoAvailable': true,
        },
        statusMessage: message,
        executionState: ToolExecutionState.completed,
      );
    } catch (e) {
      return ToolResult(
        executionId: const Uuid().v4(),
        toolId: toolId,
        success: false,
        data: {},
        statusMessage: 'Failed to update project.',
        errorMessage: 'PROJECT_SAVE_FAILED: $e',
        executionState: ToolExecutionState.failed,
      );
    }
  }

  // 1. color.set_exposure
  registry.register(
    const OmniToolDefinition(
      toolId: 'color.set_exposure',
      name: 'Set Exposure',
      description: 'Adjusts the exposure of a clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'value'],
        'properties': {
          'clipId': {'type': 'string'},
          'value': {'type': 'number'},
          'sequenceId': {'type': 'string'},
          'projectId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
    ),
    (params, context) async {
      double value = (params['value'] as num).toDouble();
      if (value < -5.0) value = -5.0;
      if (value > 5.0) value = 5.0;

      return handleColorMutation(
        'color.set_exposure',
        params,
        context,
        'Set Exposure',
        (color) => color.exposure = value,
        (oldState, newState) => {
          'oldValue': oldState.exposure,
          'newValue': newState.exposure,
        },
        (oldState, newState) => 'Exposure changed from ${oldState.exposure} to ${newState.exposure}.',
      );
    },
  );

  // 2. color.set_contrast
  registry.register(
    const OmniToolDefinition(
      toolId: 'color.set_contrast',
      name: 'Set Contrast',
      description: 'Adjusts the contrast of a clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'value'],
        'properties': {
          'clipId': {'type': 'string'},
          'value': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
    ),
    (params, context) async {
      double value = (params['value'] as num).toDouble();
      if (value < 0.0) value = 0.0;
      if (value > 2.0) value = 2.0;

      return handleColorMutation(
        'color.set_contrast',
        params,
        context,
        'Set Contrast',
        (color) => color.contrast = value,
        (oldState, newState) => {
          'oldValue': oldState.contrast,
          'newValue': newState.contrast,
        },
        (oldState, newState) => 'Contrast changed from ${oldState.contrast} to ${newState.contrast}.',
      );
    },
  );

  // 3. color.set_highlights
  registry.register(
    const OmniToolDefinition(
      toolId: 'color.set_highlights',
      name: 'Set Highlights',
      description: 'Adjusts the highlights of a clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'value'],
        'properties': {
          'clipId': {'type': 'string'},
          'value': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
    ),
    (params, context) async {
      double value = (params['value'] as num).toDouble();
      if (value < -1.0) value = -1.0;
      if (value > 1.0) value = 1.0;

      return handleColorMutation(
        'color.set_highlights',
        params,
        context,
        'Set Highlights',
        (color) => color.highlights = value,
        (oldState, newState) => {
          'oldValue': oldState.highlights,
          'newValue': newState.highlights,
        },
        (oldState, newState) => 'Highlights changed from ${oldState.highlights} to ${newState.highlights}.',
      );
    },
  );

  // 4. color.apply_lut
  registry.register(
    const OmniToolDefinition(
      toolId: 'color.apply_lut',
      name: 'Apply LUT',
      description: 'Applies a LUT to a clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'lutId'],
        'properties': {
          'clipId': {'type': 'string'},
          'lutId': {'type': 'string'},
          'intensity': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
    ),
    (params, context) async {
      final lutId = params['lutId'] as String;
      double intensity = ((params['intensity'] ?? 1.0) as num).toDouble();
      
      if (!LutLibrary.exists(lutId)) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'color.apply_lut',
          success: false,
          data: {},
          statusMessage: 'LUT not found.',
          errorMessage: 'LUT_NOT_FOUND',
          executionState: ToolExecutionState.failed,
        );
      }

      final lutPath = LutLibrary.getPath(lutId)!;
      final stageId = const Uuid().v4();

      return handleColorMutation(
        'color.apply_lut',
        params,
        context,
        'Apply LUT',
        (color) {
          color.lutStack ??= [];
          color.lutStack.add(LutStage(
            id: stageId,
            name: 'Applied LUT $lutId',
            path: lutPath,
            intensity: intensity,
            isEnabled: true,
          ));
        },
        (oldState, newState) => {
          'lutId': lutId,
          'lutName': 'Applied LUT $lutId',
          'intensity': intensity,
          'stageId': stageId,
        },
        (oldState, newState) => 'Applied LUT $lutId at intensity $intensity.',
      );
    },
  );

  // 5. color.apply_preset
  registry.register(
    const OmniToolDefinition(
      toolId: 'color.apply_preset',
      name: 'Apply Preset',
      description: 'Applies a color preset to a clip.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'presetId'],
        'properties': {
          'clipId': {'type': 'string'},
          'presetId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
    ),
    (params, context) async {
      final presetId = params['presetId'] as String;
      
      final preset = PresetLibrary.getPreset(presetId);
      if (preset == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'color.apply_preset',
          success: false,
          data: {},
          statusMessage: 'Preset not found.',
          errorMessage: 'PRESET_NOT_FOUND',
          executionState: ToolExecutionState.failed,
        );
      }

      return handleColorMutation(
        'color.apply_preset',
        params,
        context,
        'Apply Preset',
        (color) {
          color.exposure = preset.state.exposure;
          color.contrast = preset.state.contrast;
          color.highlights = preset.state.highlights;
          color.shadows = preset.state.shadows;
          color.temperature = preset.state.temperature;
          color.tint = preset.state.tint;
        },
        (oldState, newState) => {
          'presetId': preset.id,
          'presetName': preset.name,
          'changedProperties': ['exposure', 'contrast', 'highlights', 'shadows', 'temperature', 'tint'],
        },
        (oldState, newState) => 'Applied preset ${preset.name}.',
      );
    },
  );

  // 6. color.create_secondary_grade
  registry.register(
    const OmniToolDefinition(
      toolId: 'color.create_secondary_grade',
      name: 'Create Secondary Grade',
      description: 'Creates a secondary color grade targeting a specific mask.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'targetMaskId'],
        'properties': {
          'clipId': {'type': 'string'},
          'targetMaskId': {'type': 'string'},
          'name': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'creator_studio', 'photo_studio'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final clipId = params['clipId'];
      final targetMaskId = params['targetMaskId'];
      final name = params['name'] ?? 'Secondary Grade';

      if (projectId == null || sequenceId == null || clipId == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'color.create_secondary_grade',
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
            toolId: 'color.create_secondary_grade',
            success: false,
            data: {},
            statusMessage: 'Project not found.',
            errorMessage: 'PROJECT_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        final sequence = project.sequences.cast<Sequence?>().firstWhere((s) => s?.id == sequenceId, orElse: () => null);
        if (sequence == null) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'color.create_secondary_grade',
            success: false,
            data: {},
            statusMessage: 'Sequence not found.',
            errorMessage: 'SEQUENCE_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        final clip = sequence.tracks.expand((dynamic t) => (t.clips as Iterable).cast<dynamic>()).cast<Clip?>().firstWhere((c) => c?.id == clipId, orElse: () => null);
        if (clip == null) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'color.create_secondary_grade',
            success: false,
            data: {},
            statusMessage: 'Clip not found.',
            errorMessage: 'CLIP_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        // Validate mask exists
        final maskExists = clip.masks.any((m) => m.id == targetMaskId);
        if (!maskExists && targetMaskId != 'semantic_face' && targetMaskId != 'semantic_sky') {
          // For now, accept semantic references or verify actual masks
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'color.create_secondary_grade',
            success: false,
            data: {},
            statusMessage: 'Mask not found.',
            errorMessage: 'MASK_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        final secondaryGradeId = const Uuid().v4();
        
        clip.secondaryColorStates.add(ColorState(
          targetMaskId: targetMaskId,
        ));

        await projectRepo.updateProject(project);



        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'color.create_secondary_grade',
          success: true,
          data: {
            'secondaryGradeId': secondaryGradeId,
            'clipId': clipId,
            'targetMaskId': targetMaskId,
            'name': name,
            'changedObjects': [
              {'type': 'clip', 'id': clipId}
            ],
            'undoAvailable': true,
          },
          statusMessage: 'Created secondary grade "$name".',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'color.create_secondary_grade',
          success: false,
          data: {},
          statusMessage: 'Failed to update project.',
          errorMessage: 'PROJECT_SAVE_FAILED: $e',
          executionState: ToolExecutionState.failed,
        );
      }
    },
  );
}
