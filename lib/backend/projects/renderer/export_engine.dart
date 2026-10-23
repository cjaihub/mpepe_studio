import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../project_repository.dart';
import 'render_models.dart';
import 'media_render_service.dart';
import '../editor/timeline_time.dart';

enum ExportStatus {
  queued,
  preparing,
  rendering,
  encoding,
  completed,
  failed,
  cancelled,
}

class ExportSettings {
  final int outputWidth;
  final int outputHeight;
  final double frameRate;
  final String codec;
  final int bitrate;
  final String audioCodec;
  final String colorOutput;
  final bool isHDR;
  final String outputPath;

  const ExportSettings({
    required this.outputWidth,
    required this.outputHeight,
    required this.frameRate,
    required this.codec,
    required this.bitrate,
    required this.audioCodec,
    required this.colorOutput,
    required this.isHDR,
    required this.outputPath,
  });
}

class ExportJob {
  final String id;
  final StudioProject project;
  final String sequenceId;
  final double startTime;
  final double endTime;
  final ExportSettings settings;
  
  ExportStatus status = ExportStatus.queued;
  double progress = 0.0; // 0.0 to 1.0
  List<RenderDiagnostic> diagnostics = [];

  ExportJob({
    required this.id,
    required this.project,
    required this.sequenceId,
    required this.startTime,
    required this.endTime,
    required this.settings,
  });
}

class ExportEngine {
  final MediaRenderService renderService;
  final List<ExportJob> _queue = [];
  bool _isProcessing = false;

  ExportEngine(this.renderService);

  void enqueue(ExportJob job) {
    _queue.add(job);
    _processNext();
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    final job = _queue.firstWhere((j) => j.status == ExportStatus.queued, orElse: () => _queue.first);
    if (job.status != ExportStatus.queued) {
      _isProcessing = false;
      return;
    }

    job.status = ExportStatus.preparing;
    
    // Simulate export pipeline
    // In a real implementation:
    // 1. Setup encoder
    // 2. Iterate frames:
    //    request = RenderRequest(..., target: RenderTarget.export, quality: PreviewQuality.full, useProxy: false)
    //    frame = await renderService.render(request)
    //    encoder.encodeFrame(frame)
    // 3. Finalize encoder
    // 4. Update status and progress

    debugPrint('Export Engine starting job: \${job.id} - \${job.settings.outputWidth}x\${job.settings.outputHeight}');
    job.status = ExportStatus.rendering;

    try {
      final file = File(job.settings.outputPath);
      if (file.existsSync()) {
        file.deleteSync();
      }
      file.createSync(recursive: true);

      // Simple mock encoder that just writes some bytes to represent frames
      final sink = file.openWrite();
      sink.add('MOCK_VIDEO_HEADER\\n'.codeUnits);

      double frameTime = job.startTime;
      final step = 1.0 / job.settings.frameRate;

      int totalFrames = ((job.endTime - job.startTime) * job.settings.frameRate).round();
      if (totalFrames <= 0) totalFrames = 1;

      int framesRendered = 0;

      while (frameTime <= job.endTime) {
        if (job.status == ExportStatus.cancelled) break;

        final request = RenderRequest(
          projectId: job.project.id,
          sequenceId: job.sequenceId,
          sequenceTime: TimelineTime.fromSeconds(frameTime, job.settings.frameRate),
          target: RenderTarget.export,
          quality: PreviewQuality.full,
          useProxy: false,
        );

        final result = await renderService.render(job.project, request);
        
        if (!result.isSuccess) {
          job.diagnostics.addAll(result.diagnostics);
          job.status = ExportStatus.failed;
          break;
        }

        // Write a "frame"
        sink.add('FRAME \$framesRendered\\n'.codeUnits);

        framesRendered++;
        job.progress = framesRendered / totalFrames;
        frameTime += step;
      }

      await sink.close();

      if (job.status != ExportStatus.cancelled && job.status != ExportStatus.failed) {
        job.status = ExportStatus.completed;
      }
    } catch (e) {
      job.diagnostics.add(RenderDiagnostic('EXPORT_ENCODER_FAILURE', e.toString()));
      job.status = ExportStatus.failed;
    }

    _queue.remove(job);
    _isProcessing = false;
    _processNext();

  }

  void cancelJob(String id) {
    final job = _queue.firstWhere((j) => j.id == id, orElse: () => _queue.first);
    if (job.id == id) {
      job.status = ExportStatus.cancelled;
    }
  }

  void retryFailed() {
    for (var job in _queue.where((j) => j.status == ExportStatus.failed)) {
      job.status = ExportStatus.queued;
      job.progress = 0.0;
      job.diagnostics.clear();
    }
    _processNext();
  }
}
