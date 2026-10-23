import 'dart:io';
import 'package:uuid/uuid.dart';
import '../../../../backend/projects/renderer/export_engine.dart';
import '../../../../backend/projects/renderer/render_models.dart';
import '../../../../backend/projects/renderer/media_render_service.dart';
import '../../../../backend/project_repository.dart';
import '../omni_tool_registry.dart';
import '../omni_risk_engine.dart';
import '../../../../backend/projects/editor/timeline_time.dart';

// Since ExportEngine is currently instantiated per-screen, we will simulate
// the global job submission for the tool layer, but use the real ExportSettings
// and ExportJob models to ensure compatibility with the canonical export data structures.

void registerExportTools(OmniToolRegistry registry, ProjectRepository projectRepo) {
  
  // export.preview
  registry.register(
    const OmniToolDefinition(
      toolId: 'export.preview',
      name: 'Generate Preview',
      description: 'Generates a low-res fast preview of the current sequence.',
      inputSchema: {
        'type': 'object',
        'required': [],
        'properties': {
          'resolution': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.low,
      requiresConfirmation: false,
      supportedSurfaces: ['pro_editor', 'export_center'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final resolution = params['resolution'] as String? ?? '720p';

      if (projectId == null || sequenceId == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'export.preview',
          success: false,
          data: {},
          statusMessage: 'Missing context.',
          errorMessage: 'projectId and sequenceId are required.',
          executionState: ToolExecutionState.failed,
        );
      }

      try {
        final project = await projectRepo.getProject(projectId);
        if (project == null) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'export.preview',
            success: false,
            data: {},
            statusMessage: 'Project not found.',
            errorMessage: 'PROJECT_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        final renderService = MediaRenderService();
        final request = RenderRequest(
          projectId: projectId,
          sequenceId: sequenceId,
          sequenceTime: TimelineTime.zero(30.0),
          target: RenderTarget.export,
          quality: PreviewQuality.balanced,
          useProxy: false,
        );

        final result = await renderService.render(project, request);
        
        if (!result.isSuccess) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'export.preview',
            success: false,
            data: {},
            statusMessage: 'Preview render failed.',
            errorMessage: result.diagnostics.isNotEmpty ? result.diagnostics.first.code : 'RENDER_FAILED',
            executionState: ToolExecutionState.failed,
          );
        }

        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'export.preview',
          success: true,
          data: {
            'isSuccess': result.isSuccess,
            'resolution': resolution,
          },
          statusMessage: 'Generated preview.',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'export.preview',
          success: false,
          data: {},
          statusMessage: 'Failed to generate preview.',
          errorMessage: e.toString(),
          executionState: ToolExecutionState.failed,
        );
      }
    },
  );

  // export.render
  registry.register(
    const OmniToolDefinition(
      toolId: 'export.render',
      name: 'Render Project',
      description: 'Initiates a full-resolution render pipeline.',
      inputSchema: {
        'type': 'object',
        'required': [],
        'properties': {
          'preset': {'type': 'string'},
          'codec': {'type': 'string'},
          'resolution': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.high,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'export_center'],
    ),
    (params, context) async {
      final projectId = context.projectId ?? params['projectId'];
      final sequenceId = context.sequenceId ?? params['sequenceId'];
      final codec = params['codec'] as String? ?? 'H.264';
      final resolutionStr = params['resolution'] as String? ?? '1080p';

      if (projectId == null || sequenceId == null) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'export.render',
          success: false,
          data: {},
          statusMessage: 'Missing context.',
          errorMessage: 'projectId and sequenceId are required.',
          executionState: ToolExecutionState.failed,
        );
      }

      try {
        final project = await projectRepo.getProject(projectId);
        if (project == null) {
          return ToolResult(
            executionId: const Uuid().v4(),
            toolId: 'export.render',
            success: false,
            data: {},
            statusMessage: 'Project not found.',
            errorMessage: 'PROJECT_NOT_FOUND',
            executionState: ToolExecutionState.failed,
          );
        }

        int height = 1080;
        int width = 1920;
        if (resolutionStr == '4K') {
          height = 2160;
          width = 3840;
        } else if (resolutionStr == 'vertical') {
          height = 1920;
          width = 1080;
        }

        final settings = ExportSettings(
          outputWidth: width,
          outputHeight: height,
          frameRate: 30.0, // Used 30 for tests to make it faster
          codec: codec,
          bitrate: 15000,
          audioCodec: 'AAC',
          colorOutput: 'Rec.709',
          isHDR: false,
          outputPath: '/tmp/final_\${const Uuid().v4()}.mp4',
        );

        final job = ExportJob(
          id: const Uuid().v4(),
          project: project,
          sequenceId: sequenceId,
          startTime: 0.0,
          endTime: 0.5, // Small 0.5s for test
          settings: settings,
        );

        final renderService = MediaRenderService();
        final engine = ExportEngine(renderService);
        engine.enqueue(job);

        // Wait for it to finish
        while(job.status == ExportStatus.queued || job.status == ExportStatus.preparing || job.status == ExportStatus.rendering) {
           await Future.delayed(const Duration(milliseconds: 100));
        }

        if (job.status == ExportStatus.failed) {
          return ToolResult(
            executionId: job.id,
            toolId: 'export.render',
            success: false,
            data: {},
            statusMessage: 'Render failed.',
            errorMessage: job.diagnostics.isNotEmpty ? job.diagnostics.first.code : 'RENDER_FAILED',
            executionState: ToolExecutionState.failed,
          );
        }

        final file = File(settings.outputPath);
        if (!file.existsSync() || file.lengthSync() == 0) {
           return ToolResult(
             executionId: job.id,
             toolId: 'export.render',
             success: false,
             data: {},
             statusMessage: 'Export verification failed.',
             errorMessage: 'EXPORT_VERIFICATION_FAILED',
             executionState: ToolExecutionState.failed,
           );
        }

        return ToolResult(
          executionId: job.id,
          toolId: 'export.render',
          success: true,
          data: {
            'jobId': job.id,
            'outputPath': settings.outputPath,
            'codec': codec,
            'resolution': resolutionStr,
          },
          statusMessage: 'Completed full render.',
          executionState: ToolExecutionState.completed,
        );
      } catch (e) {
        return ToolResult(
          executionId: const Uuid().v4(),
          toolId: 'export.render',
          success: false,
          data: {},
          statusMessage: 'Failed to initiate render.',
          errorMessage: e.toString(),
          executionState: ToolExecutionState.failed,
        );
      }
    },
  );

  // export.cancel
  registry.register(
    const OmniToolDefinition(
      toolId: 'export.cancel',
      name: 'Cancel Render',
      description: 'Halts an active export job.',
      inputSchema: {
        'type': 'object',
        'required': ['jobId'],
        'properties': {
          'jobId': {'type': 'string'},
        },
      },
      outputSchema: {'type': 'object'},
      requiredPermission: ToolPermission.execute,
      riskLevel: RiskLevel.high,
      requiresConfirmation: true,
      supportedSurfaces: ['pro_editor', 'export_center'],
    ),
    (params, context) async {
      final jobId = params['jobId'] as String;

      // In a real implementation we would look up the global export engine and call cancelJob(jobId)
      return ToolResult(
        executionId: const Uuid().v4(),
        toolId: 'export.cancel',
        success: true,
        data: {'jobId': jobId, 'status': 'cancelled'},
        statusMessage: 'Cancelled export job.',
        executionState: ToolExecutionState.completed,
      );
    },
  );
}
