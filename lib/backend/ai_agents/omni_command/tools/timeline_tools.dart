import 'package:uuid/uuid.dart';
import '../../../../backend/projects/models/pro_project_models.dart';
import '../../../../backend/projects/models/keyframe_models.dart';
import '../../../../backend/project_repository.dart';
import '../omni_tool_registry.dart';
import '../omni_risk_engine.dart';

void registerTimelineTools(OmniToolRegistry registry, ProjectRepository projectRepo) {

  // timeline.split_clip
  registry.register(
    const OmniToolDefinition(
      toolId: 'timeline.split_clip',
      name: 'Split Clip',
      description: 'Splits a clip at the given playhead time.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'playhead'],
        'properties': {
          'clipId': {'type': 'string'},
          'playhead': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final clipId = params['clipId'];
      final playhead = (params['playhead'] as num?)?.toDouble();

      if (projectId == null || sequenceId == null || clipId == null || playhead == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.split_clip',
          success: false,
          data: {},
          statusMessage: 'Missing context.',
          errorMessage: 'projectId, sequenceId, clipId, and playhead are required.',
          executionState: ToolExecutionState.failed,
        );
      }

      try {
        final project = await projectRepo.getProject(projectId);
        if (project == null) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'timeline.split_clip',
            success: false,
            data: {},
            statusMessage: 'Project not found.',
            errorMessage: 'PROJECT_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        final sequence = project.sequences.firstWhere((s) => s.id == sequenceId);
        
        Track? targetTrack;
        int targetClipIndex = -1;
        
        for (var track in sequence.tracks) {
          final idx = track.clips.indexWhere((c) => c.id == clipId);
          if (idx != -1) {
            targetTrack = track;
            targetClipIndex = idx;
            break;
          }
        }

        if (targetTrack == null || targetClipIndex == -1) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'timeline.split_clip',
            success: false,
            data: {},
            statusMessage: 'Clip not found.',
            errorMessage: 'CLIP_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        final clip = targetTrack.clips[targetClipIndex];
        
        if (playhead <= clip.startTime || playhead >= clip.startTime + clip.duration) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'timeline.split_clip',
            success: false,
            data: {},
            statusMessage: 'Playhead is outside the clip bounds.',
            errorMessage: 'INVALID_PLAYHEAD',
            executionState: ToolExecutionState.failed,
          );
        }

        final rightClipJson = clip.toJson();
        final newRightClipId = const Uuid().v4();
        rightClipJson['id'] = newRightClipId;
        
        final rightClip = Clip.fromJson(rightClipJson);
        final splitOffset = playhead - clip.startTime;
        
        rightClip.startTime = playhead;
        rightClip.sourceStart = clip.sourceStart + splitOffset;
        rightClip.duration = clip.duration - splitOffset;
        
        clip.duration = splitOffset;

        targetTrack.clips.insert(targetClipIndex + 1, rightClip);

        await projectRepo.updateProject(project);

        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.split_clip',
          success: true,
          data: {
            'leftClipId': clip.id,
            'rightClipId': rightClip.id,
            'splitTime': playhead,
          },
          statusMessage: 'Split clip at playhead.',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.split_clip',
          success: false,
          data: {},
          statusMessage: 'Failed to split clip.',
          errorMessage: e.toString(),
          executionState: ToolExecutionState.failed,
        );
      }
    },
  );

  // timeline.trim_clip
  registry.register(
    const OmniToolDefinition(
      toolId: 'timeline.trim_clip',
      name: 'Trim Clip',
      description: 'Trims the clip to a new start or end time.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId'],
        'properties': {
          'clipId': {'type': 'string'},
          'newStart': {'type': 'number'},
          'newEnd': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final clipId = params['clipId'];
      final newStart = (params['newStart'] as num?)?.toDouble();
      final newEnd = (params['newEnd'] as num?)?.toDouble();

      if (projectId == null || sequenceId == null || clipId == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.trim_clip',
          success: false,
          data: {},
          statusMessage: 'Missing context.',
          errorMessage: 'projectId, sequenceId, and clipId are required.',
          executionState: ToolExecutionState.failed,
        );
      }

      try {
        final project = await projectRepo.getProject(projectId);
        if (project == null) return _projectNotFound('timeline.trim_clip');

        final sequence = project.sequences.firstWhere((s) => s.id == sequenceId);
        Clip? targetClip;
        for (var track in sequence.tracks) {
          final idx = track.clips.indexWhere((c) => c.id == clipId);
          if (idx != -1) {
            targetClip = track.clips[idx];
            break;
          }
        }

        if (targetClip == null) return _clipNotFound('timeline.trim_clip');

        if (newStart != null) {
          if (newStart >= targetClip.startTime + targetClip.duration) {
            return _invalidTrim('timeline.trim_clip');
          }
          final offset = newStart - targetClip.startTime;
          targetClip.startTime = newStart;
          targetClip.sourceStart += offset;
          targetClip.duration -= offset;
        }

        if (newEnd != null) {
          if (newEnd <= targetClip.startTime) {
            return _invalidTrim('timeline.trim_clip');
          }
          targetClip.duration = newEnd - targetClip.startTime;
        }

        await projectRepo.updateProject(project);

        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.trim_clip',
          success: true,
          data: {
            'clipId': clipId,
            'startTime': targetClip.startTime,
            'duration': targetClip.duration,
          },
          statusMessage: 'Trimmed clip.',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return _errorResult('timeline.trim_clip', e.toString());
      }
    },
  );

  // timeline.move_clip
  registry.register(
    const OmniToolDefinition(
      toolId: 'timeline.move_clip',
      name: 'Move Clip',
      description: 'Moves the clip by a given delta time or to a specific time.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId'],
        'properties': {
          'clipId': {'type': 'string'},
          'delta': {'type': 'number'},
          'newTime': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final clipId = params['clipId'];
      final delta = (params['delta'] as num?)?.toDouble();
      final newTime = (params['newTime'] as num?)?.toDouble();

      if (projectId == null || sequenceId == null || clipId == null) {
        return _missingContext('timeline.move_clip');
      }

      try {
        final project = await projectRepo.getProject(projectId);
        if (project == null) return _projectNotFound('timeline.move_clip');

        final sequence = project.sequences.firstWhere((s) => s.id == sequenceId);
        Clip? targetClip;
        for (var track in sequence.tracks) {
          final idx = track.clips.indexWhere((c) => c.id == clipId);
          if (idx != -1) {
            targetClip = track.clips[idx];
            break;
          }
        }

        if (targetClip == null) return _clipNotFound('timeline.move_clip');

        if (delta != null) {
          targetClip.startTime += delta;
        } else if (newTime != null) {
          targetClip.startTime = newTime;
        } else {
          return _errorResult('timeline.move_clip', 'Must provide delta or newTime.');
        }

        if (targetClip.startTime < 0) {
          targetClip.startTime = 0;
        }

        await projectRepo.updateProject(project);

        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.move_clip',
          success: true,
          data: {
            'clipId': clipId,
            'startTime': targetClip.startTime,
          },
          statusMessage: 'Moved clip.',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return _errorResult('timeline.move_clip', e.toString());
      }
    },
  );

  // timeline.add_keyframe
  registry.register(
    const OmniToolDefinition(
      toolId: 'timeline.add_keyframe',
      name: 'Add Keyframe',
      description: 'Adds a keyframe to a property of the clip at the specified time.',
      inputSchema: {
        'type': 'object',
        'required': ['clipId', 'property', 'time', 'value'],
        'properties': {
          'clipId': {'type': 'string'},
          'property': {'type': 'string'},
          'time': {'type': 'number'},
          'value': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final clipId = params['clipId'];
      final property = params['property'] as String?;
      final time = (params['time'] as num?)?.toDouble();
      final value = (params['value'] as num?)?.toDouble();

      if (projectId == null || sequenceId == null || clipId == null || property == null || time == null || value == null) {
        return _missingContext('timeline.add_keyframe');
      }

      try {
        final project = await projectRepo.getProject(projectId);
        if (project == null) return _projectNotFound('timeline.add_keyframe');

        final sequence = project.sequences.firstWhere((s) => s.id == sequenceId);
        Clip? targetClip;
        for (var track in sequence.tracks) {
          final idx = track.clips.indexWhere((c) => c.id == clipId);
          if (idx != -1) {
            targetClip = track.clips[idx];
            break;
          }
        }

        if (targetClip == null) return _clipNotFound('timeline.add_keyframe');

        targetClip.keyframes.add(Keyframe(
          id: const Uuid().v4(),
          property: property,
          time: time,
          value: value,
          easing: KeyframeEasing.linear,
        ));

        await projectRepo.updateProject(project);

        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.add_keyframe',
          success: true,
          data: {
            'clipId': clipId,
            'property': property,
            'time': time,
            'value': value,
          },
          statusMessage: 'Added keyframe.',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return _errorResult('timeline.add_keyframe', e.toString());
      }
    },
  );

  // timeline.add_transition
  registry.register(
    const OmniToolDefinition(
      toolId: 'timeline.add_transition',
      name: 'Add Transition',
      description: 'Adds a transition between two clips on a track.',
      inputSchema: {
        'type': 'object',
        'required': ['outgoingClipId', 'incomingClipId', 'type'],
        'properties': {
          'outgoingClipId': {'type': 'string'},
          'incomingClipId': {'type': 'string'},
          'type': {'type': 'string'},
          'duration': {'type': 'number'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final outgoingClipId = params['outgoingClipId'] as String?;
      final incomingClipId = params['incomingClipId'] as String?;
      final typeStr = params['type'] as String?;
      final duration = (params['duration'] as num?)?.toDouble() ?? 1.0;

      if (projectId == null || sequenceId == null || outgoingClipId == null || incomingClipId == null || typeStr == null) {
        return _missingContext('timeline.add_transition');
      }

      TransitionType tType;
      try {
        tType = TransitionType.values.firstWhere((e) => e.name.toLowerCase() == typeStr.toLowerCase());
      } catch (_) {
        return _errorResult('timeline.add_transition', 'Invalid transition type.');
      }

      try {
        final project = await projectRepo.getProject(projectId);
        if (project == null) return _projectNotFound('timeline.add_transition');

        final sequence = project.sequences.firstWhere((s) => s.id == sequenceId);
        Track? targetTrack;
        
        for (var track in sequence.tracks) {
          final outIdx = track.clips.indexWhere((c) => c.id == outgoingClipId);
          final inIdx = track.clips.indexWhere((c) => c.id == incomingClipId);
          if (outIdx != -1 && inIdx != -1) {
            targetTrack = track;
            break;
          }
        }

        if (targetTrack == null) {
          return _errorResult('timeline.add_transition', 'Clips not found on the same track.');
        }

        targetTrack.transitions.add(TimelineTransition(
          id: const Uuid().v4(),
          fromClipId: outgoingClipId,
          toClipId: incomingClipId,
          type: tType,
          duration: duration,
        ));

        await projectRepo.updateProject(project);

        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'timeline.add_transition',
          success: true,
          data: {
            'outgoingClipId': outgoingClipId,
            'incomingClipId': incomingClipId,
            'type': typeStr,
            'duration': duration,
          },
          statusMessage: 'Added transition.',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return _errorResult('timeline.add_transition', e.toString());
      }
    },
  );
}

ToolResult _missingContext(String toolId) => ToolResult(
  executionId: const Uuid().v4(),
  toolId: toolId,
  success: false,
  data: {},
  statusMessage: 'Missing context.',
  errorMessage: 'projectId, sequenceId, and clipId are required.',
  executionState: ToolExecutionState.failed,
);

ToolResult _projectNotFound(String toolId) => ToolResult(
  executionId: const Uuid().v4(),
  toolId: toolId,
  success: false,
  data: {},
  statusMessage: 'Project not found.',
  errorMessage: 'PROJECT_NOT_FOUND',
  executionState: ToolExecutionState.failed,
);

ToolResult _clipNotFound(String toolId) => ToolResult(
  executionId: const Uuid().v4(),
  toolId: toolId,
  success: false,
  data: {},
  statusMessage: 'Clip not found.',
  errorMessage: 'CLIP_NOT_FOUND',
  executionState: ToolExecutionState.failed,
);

ToolResult _invalidTrim(String toolId) => ToolResult(
  executionId: const Uuid().v4(),
  toolId: toolId,
  success: false,
  data: {},
  statusMessage: 'Invalid trim bounds.',
  errorMessage: 'INVALID_TRIM',
  executionState: ToolExecutionState.failed,
);

ToolResult _errorResult(String toolId, String errorMessage) => ToolResult(
  executionId: const Uuid().v4(),
  toolId: toolId,
  success: false,
  data: {},
  statusMessage: 'Failed operation.',
  errorMessage: errorMessage,
  executionState: ToolExecutionState.failed,
);
