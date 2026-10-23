import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/media_processing_models.dart';
import '../../observability/telemetry_service.dart';

final mediaPipelineServiceProvider = Provider<MediaPipelineService>((ref) {
  return MediaPipelineService(ref.read(telemetryServiceProvider));
});

class MediaPipelineService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TelemetryService _telemetry;

  MediaPipelineService(this._telemetry);

  /// 1. Upload
  /// Registers a raw file into the pipeline queue.
  Future<String> enqueueMedia(String ownerId, String rawStoragePath) async {
    final span = _telemetry.startSpan('media.enqueue', attributes: {'ownerId': ownerId});
    try {
      final asset = MediaAsset(
        id: '',
        ownerId: ownerId,
        type: MediaType.video,
        originalFilename: rawStoragePath.split('/').last,
        mimeType: 'application/octet-stream',
        sizeBytes: 0,
        storageLocation: rawStoragePath,
        processingState: MediaProcessingStatus.uploaded,
        visibility: MediaVisibility.private,
        createdAt: DateTime.now(),
      );

      final doc = await _firestore.collection('media_assets').add(asset.toMap());
      span.end();
      return doc.id;
    } catch (e, stack) {
      span.recordException(e);
      _telemetry.recordException(e, stack, fatal: true);
      _telemetry.recordMetric('upload_failures_total', 1);
      span.end();
      rethrow;
    }
  }

  /// Streams the status of a given asset.
  /// Used by the client to track "processing", "ready", or "failed".
  Stream<MediaAsset?> streamAssetStatus(String assetId) {
    return _firestore
        .collection('media_assets')
        .doc(assetId)
        .snapshots()
        .map((doc) => doc.exists ? MediaAsset.fromFirestore(doc) : null);
  }

  /// [Simulated Backend Pipeline]
  /// In production, a Cloud Function triggers on the GCS upload bucket.
  /// It runs validation, virus/content scanning (e.g. Google Cloud Video Intelligence),
  /// extracts metadata, and fires up a transcoding job (e.g. AWS Elemental MediaConvert).
  // ignore: unused_element
  Future<void> _simulatePipeline(String assetId) async {
    final span = _telemetry.startSpan('media.processingPipeline', attributes: {'assetId': assetId});
    
    try {
      final ref = _firestore.collection('media_assets').doc(assetId);
      
      // Status: Processing
      span.addEvent('phase.processing_started');
      await ref.update({'status': MediaProcessingStatus.processing.name});

      await Future.delayed(const Duration(seconds: 2));
      span.addEvent('phase.transcoding_completed');

    // Generating standard resolutions supported by the infrastructure
    final variants = [
      MediaVariant(
        resolution: const MediaResolution(label: '240p', height: 240, width: 426, bitrateKbps: 400),
        storagePath: 'processed/$assetId/video_240p.mp4',
        fileSize: 1024 * 1024 * 5,
      ),
      MediaVariant(
        resolution: const MediaResolution(label: '360p', height: 360, width: 640, bitrateKbps: 800),
        storagePath: 'processed/$assetId/video_360p.mp4',
        fileSize: 1024 * 1024 * 12,
      ),
      MediaVariant(
        resolution: const MediaResolution(label: '480p', height: 480, width: 854, bitrateKbps: 1200),
        storagePath: 'processed/$assetId/video_480p.mp4',
        fileSize: 1024 * 1024 * 20,
      ),
      MediaVariant(
        resolution: const MediaResolution(label: '720p', height: 720, width: 1280, bitrateKbps: 2500),
        storagePath: 'processed/$assetId/video_720p.mp4',
        fileSize: 1024 * 1024 * 45,
      ),
      MediaVariant(
        resolution: const MediaResolution(label: '1080p', height: 1080, width: 1920, bitrateKbps: 4500),
        storagePath: 'processed/$assetId/video_1080p.mp4',
        fileSize: 1024 * 1024 * 90,
      ),
    ];

    // Status: Ready (Once CDN delivery and adaptive bitrate HLS playlist is confirmed)
    await ref.update({
      'status': MediaProcessingStatus.ready.name,
      'variants': variants.map((v) => v.toMap()).toList(),
      'hlsPlaylistUrl': 'https://cdn.onerova.studio/master.m3u8',
      'thumbnailUrl': 'https://cdn.onerova.studio/thumb.jpg',
      'posterUrl': 'https://cdn.onerova.studio/poster.jpg',
      'metadata': {
        'durationMs': 120000,
        'codec': 'h264',
        'safeContentScanned': true,
      }
    });
    
    span.addEvent('phase.delivery_ready');
    _telemetry.recordMetric('media_processed_total', 1);
    span.end();
    
    } catch (e, stack) {
      span.recordException(e);
      _telemetry.recordException(e, stack, fatal: true);
      span.end();
      rethrow;
    }
  }

  /// Initiates a deletion flow adhering to retention policies
  Future<void> deleteAsset(String assetId) async {
    // In production, this would mark the asset as 'deleted' in DB
    // and queue a job to wipe the raw storage and CDN edges.
    await _firestore.collection('media_assets').doc(assetId).delete();
  }
}
