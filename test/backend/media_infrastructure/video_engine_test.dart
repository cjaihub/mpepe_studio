import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:oneova/backend/media_infrastructure/services/video_engine_service.dart';
import 'package:oneova/backend/media_infrastructure/models/media_processing_models.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late VideoEngineService videoEngine;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    videoEngine = VideoEngineService(firestore: firestore);
  });

  test('Submitting a job initializes processing and tracks progress', () async {
    final assetId = 'asset_123';
    
    // Create base asset
    await firestore.collection('media_library').doc(assetId).set({
      'ownerId': 'user123',
      'processingState': MediaProcessingStatus.uploaded.name,
    });

    final jobId = await videoEngine.submitJob(
      assetId: assetId,
      format: AspectRatioFormat.vertical9x16,
      preset: PlatformExportPreset.oneovaStandard,
    );

    // Give the async worker a moment to update the state
    await Future.delayed(const Duration(milliseconds: 200));

    // Initial state check
    var jobDoc = await firestore.collection('video_jobs').doc(jobId).get();
    expect(jobDoc.data()!['status'], 'processing');
    expect(jobDoc.data()!['currentPhase'], 'ingest');

    var assetDoc = await firestore.collection('media_library').doc(assetId).get();
    expect(assetDoc.data()!['processingState'], MediaProcessingStatus.processing.name);

    // Wait for the simulated pipeline to finish
    await Future.delayed(const Duration(seconds: 5));

    jobDoc = await firestore.collection('video_jobs').doc(jobId).get();
    expect(jobDoc.data()!['status'], 'completed');
    expect(jobDoc.data()!['progress'], 1.0);

    assetDoc = await firestore.collection('media_library').doc(assetId).get();
    expect(assetDoc.data()!['processingState'], MediaProcessingStatus.ready.name);
    
    // Verify variants (240p, 360p, 480p, 720p, 1080p)
    final variants = assetDoc.data()!['variants'] as List;
    expect(variants.length, 5);
    expect(variants[0]['resolution']['label'], '240p');
    expect(variants[4]['resolution']['label'], '1080p');
  });

  test('Cancellation stops processing and updates status', () async {
    final assetId = 'asset_456';
    
    await firestore.collection('media_library').doc(assetId).set({
      'ownerId': 'user123',
      'processingState': MediaProcessingStatus.uploaded.name,
    });

    final jobId = await videoEngine.submitJob(
      assetId: assetId,
      format: AspectRatioFormat.horizontal16x9,
      preset: PlatformExportPreset.youtubeShorts,
    );

    // Give it a moment to start
    await Future.delayed(const Duration(milliseconds: 600));

    // Cancel job
    await videoEngine.cancelJob(jobId);

    // Wait to ensure worker thread actually stops and doesn't write success
    await Future.delayed(const Duration(seconds: 2));

    final jobDoc = await firestore.collection('video_jobs').doc(jobId).get();
    expect(jobDoc.data()!['status'], 'cancelled');
    
    final assetDoc = await firestore.collection('media_library').doc(assetId).get();
    expect(assetDoc.data()!['processingState'], isNot(MediaProcessingStatus.ready.name));
  });

  test('Job retry handles limits', () async {
    // Setup a failed job
    final docRef = await firestore.collection('video_jobs').add({
      'assetId': 'asset_789',
      'status': 'failed',
      'retryCount': 3, // max retries
    });

    expect(
      () => videoEngine.retryJob(docRef.id),
      throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('Max retries exceeded'))),
    );
  });
}
