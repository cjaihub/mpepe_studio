import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/vision/models/oneova_model_registry.dart';
import 'package:oneova/looks/vision/services/model_swap_service.dart';

void main() {
  group('Phase 11: Oneova Vision Models Registry & Staged Swap-In Tests', () {
    test('OneovaModelRegistry contains production vision models with valid metrics', () {
      final models = OneovaModelRegistry.defaultModels;
      expect(models.length, equals(4));

      final faceMesh = OneovaModelRegistry.findById('oneova_face_mesh_v2');
      expect(faceMesh, isNotNull);
      expect(faceMesh!.type, equals(OneovaModelType.faceMesh));
      expect(faceMesh.version, equals('2.1.0'));
      expect(faceMesh.capabilities, contains('478_landmarks'));
      expect(faceMesh.targetLatencyMs, lessThanOrEqualTo(5.0));
      expect(faceMesh.passesAllEvalGates, isTrue);

      final seg = OneovaModelRegistry.findByType(OneovaModelType.segmentation);
      expect(seg, isNotNull);
      expect(seg!.id, equals('oneova_person_seg_v2'));
      expect(seg.capabilities, contains('person_mask'));
      expect(seg.passesAllEvalGates, isTrue);

      final hands = OneovaModelRegistry.findByType(OneovaModelType.handTracking);
      expect(hands, isNotNull);
      expect(hands!.capabilities, contains('21_joints'));

      final depth = OneovaModelRegistry.findByType(OneovaModelType.depthEstimation);
      expect(depth, isNotNull);
      expect(depth!.minComputeTier, equals(2));
    });

    test('OneovaModelDescriptor serialization preserves all fields and eval scores', () {
      final original = OneovaModelRegistry.faceMeshV2;
      final map = original.toMap();
      final restored = OneovaModelDescriptor.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.type, equals(original.type));
      expect(restored.version, equals(original.version));
      expect(restored.format, equals(original.format));
      expect(restored.sha256Checksum, equals(original.sha256Checksum));
      expect(restored.capabilities, equals(original.capabilities));
      expect(restored.evaluationScores.length, equals(original.evaluationScores.length));
      expect(restored.passesAllEvalGates, isTrue);
    });

    test('OneovaModelSwapService initializes with active default models', () {
      final service = OneovaModelSwapService();

      final faceMesh = service.getActiveModel(OneovaModelType.faceMesh);
      expect(faceMesh, isNotNull);
      expect(faceMesh!.id, equals('oneova_face_mesh_v2'));

      final seg = service.getActiveModel(OneovaModelType.segmentation);
      expect(seg, isNotNull);
      expect(seg!.id, equals('oneova_person_seg_v2'));

      service.dispose();
    });

    test('verifyIntegrity enforces cryptographic SHA-256 validation', () {
      final service = OneovaModelSwapService();
      final dummyModelBytes = utf8.encode('ONEOVA_NEURAL_WEIGHTS_MOCK_STREAM_BYTES_V3');
      final validHash = sha256.convert(dummyModelBytes).toString();

      final testDescriptor = OneovaModelDescriptor(
        id: 'test_descriptor_v1',
        type: OneovaModelType.faceMesh,
        version: '3.0.0',
        format: OneovaModelFormat.liteRt,
        downloadUrl: 'https://cdn.oneova.app/models/test.tflite',
        localFilename: 'test.tflite',
        sha256Checksum: validHash,
        sizeBytes: dummyModelBytes.length,
        minComputeTier: 1,
        targetLatencyMs: 4.0,
        capabilities: ['landmarks'],
      );

      // Positive match
      expect(service.verifyIntegrity(testDescriptor, dummyModelBytes), isTrue);

      // Negative corrupted byte stream
      final corruptedBytes = utf8.encode('CORRUPTED_BYTES');
      expect(service.verifyIntegrity(testDescriptor, corruptedBytes), isFalse);

      // Empty payload
      expect(service.verifyIntegrity(testDescriptor, const []), isFalse);

      service.dispose();
    });

    test('Staged candidate passes eval gates and swaps in atomically with rollback snapshot', () async {
      final service = OneovaModelSwapService();

      final candidate = OneovaModelDescriptor(
        id: 'oneova_face_mesh_v3_distilled',
        type: OneovaModelType.faceMesh,
        version: '3.0.0',
        format: OneovaModelFormat.liteRt,
        downloadUrl: 'https://cdn.oneova.app/models/face_mesh_v3.tflite',
        localFilename: 'face_mesh_v3.tflite',
        sha256Checksum: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        sizeBytes: 3145728,
        minComputeTier: 1,
        targetLatencyMs: 3.2,
        capabilities: ['478_landmarks', 'iris_tracking', 'distilled_quantized'],
        evaluationScores: const [
          ModelEvaluationScore(metricName: 'NME_percent', value: 2.1, targetThreshold: 3.5, passesGate: true),
          ModelEvaluationScore(metricName: 'latency_ms', value: 3.1, targetThreshold: 5.0, passesGate: true),
        ],
      );

      service.stageCandidate(candidate);
      expect(service.getStagedCandidate(OneovaModelType.faceMesh), isNotNull);
      expect(service.evaluateCandidate(OneovaModelType.faceMesh), isTrue);

      ModelSwapEvent? capturedEvent;
      final sub = service.onSwapEvents.listen((event) {
        capturedEvent = event;
      });

      // Atomic swap-in
      final success = service.swapInStagedModel(OneovaModelType.faceMesh);
      expect(success, isTrue);
      await pumpEventQueue();

      final active = service.getActiveModel(OneovaModelType.faceMesh);
      expect(active, isNotNull);
      expect(active!.id, equals('oneova_face_mesh_v3_distilled'));
      expect(active.version, equals('3.0.0'));

      // Rollback snapshot preserved
      final snapshot = service.getRollbackSnapshot(OneovaModelType.faceMesh);
      expect(snapshot, isNotNull);
      expect(snapshot!.id, equals('oneova_face_mesh_v2'));

      // Event emitted
      expect(capturedEvent, isNotNull);
      expect(capturedEvent!.activeModel.id, equals('oneova_face_mesh_v3_distilled'));
      expect(capturedEvent!.isRollback, isFalse);

      // Execute rollback
      final rollbackSuccess = service.rollback(OneovaModelType.faceMesh);
      expect(rollbackSuccess, isTrue);
      await pumpEventQueue();

      final restored = service.getActiveModel(OneovaModelType.faceMesh);
      expect(restored, isNotNull);
      expect(restored!.id, equals('oneova_face_mesh_v2'));
      expect(capturedEvent!.isRollback, isTrue);

      await sub.cancel();
      service.dispose();
    });

    test('Candidate failing eval gate is rejected from swap-in', () {
      final service = OneovaModelSwapService();

      final failingCandidate = OneovaModelDescriptor(
        id: 'oneova_face_mesh_unstable',
        type: OneovaModelType.faceMesh,
        version: '3.0.0-unstable',
        format: OneovaModelFormat.liteRt,
        downloadUrl: 'https://cdn.oneova.app/models/unstable.tflite',
        localFilename: 'unstable.tflite',
        sha256Checksum: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        sizeBytes: 5000000,
        minComputeTier: 1,
        targetLatencyMs: 12.0,
        capabilities: ['landmarks'],
        evaluationScores: const [
          ModelEvaluationScore(metricName: 'NME_percent', value: 8.5, targetThreshold: 3.5, passesGate: false),
        ],
      );

      service.stageCandidate(failingCandidate);
      expect(service.evaluateCandidate(OneovaModelType.faceMesh), isFalse);

      // Attempt swap-in should fail
      final success = service.swapInStagedModel(OneovaModelType.faceMesh);
      expect(success, isFalse);

      // Current active model remains untouched
      final active = service.getActiveModel(OneovaModelType.faceMesh);
      expect(active!.id, equals('oneova_face_mesh_v2'));

      service.dispose();
    });
  });
}
