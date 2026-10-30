import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../models/oneova_look.dart';
import '../models/photo_grading_models.dart';
import 'photo_export_service.dart';

/// Progress event emitted during batch grading operations.
@immutable
class BatchProgressUpdate {
  final int completed;
  final int total;
  final double fraction;
  final BatchGradingItem currentItem;

  const BatchProgressUpdate({
    required this.completed,
    required this.total,
    required this.fraction,
    required this.currentItem,
  });
}

/// Professional Batch Grading Service.
///
/// Applies an active OneovaLook across an arbitrary queue of photos,
/// preserving individual native resolutions and emitting real-time progress.
class PhotoBatchGradingService {
  final PhotoExportService _exportService;

  PhotoBatchGradingService({PhotoExportService? exportService})
      : _exportService = exportService ?? PhotoExportService();

  /// Executes batch grading on [photoPaths] applying [look].
  ///
  /// Emits updates on [onProgress] as each photo completes.
  Future<BatchGradingReport> executeBatch({
    required List<String> photoPaths,
    required OneovaLook look,
    void Function(BatchProgressUpdate update)? onProgress,
  }) async {
    final overallStopwatch = Stopwatch()..start();
    final items = <BatchGradingItem>[];
    int successCount = 0;
    int failedCount = 0;

    for (int i = 0; i < photoPaths.length; i++) {
      final path = photoPaths[i];
      final itemStopwatch = Stopwatch()..start();

      BatchGradingItem currentItem = BatchGradingItem(
        sourcePath: path,
        status: BatchItemStatus.processing,
      );

      onProgress?.call(
        BatchProgressUpdate(
          completed: i,
          total: photoPaths.length,
          fraction: i / photoPaths.length,
          currentItem: currentItem,
        ),
      );

      try {
        final result = await _exportService.exportOriginalResolution(
          sourcePath: path,
          look: look,
        );

        itemStopwatch.stop();
        currentItem = currentItem.copyWith(
          status: BatchItemStatus.completed,
          outputPath: result.outputPath,
          durationMs: itemStopwatch.elapsedMilliseconds,
        );
        successCount++;
      } catch (e) {
        itemStopwatch.stop();
        currentItem = currentItem.copyWith(
          status: BatchItemStatus.failed,
          errorMessage: e.toString(),
          durationMs: itemStopwatch.elapsedMilliseconds,
        );
        failedCount++;
      }

      items.add(currentItem);

      onProgress?.call(
        BatchProgressUpdate(
          completed: i + 1,
          total: photoPaths.length,
          fraction: (i + 1) / photoPaths.length,
          currentItem: currentItem,
        ),
      );
    }

    overallStopwatch.stop();

    return BatchGradingReport(
      totalCount: photoPaths.length,
      successCount: successCount,
      failedCount: failedCount,
      items: items,
      totalDuration: overallStopwatch.elapsed,
    );
  }
}
