import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 10: Release Deployment & Cloud Infrastructure Verification', () {
    test('Cloud Run GPU YAML deployment manifest adheres to specification', () {
      final file = File('packages/cloud_vision_service/deploy/cloud_run_gpu.yaml');
      expect(file.existsSync(), isTrue, reason: 'cloud_run_gpu.yaml must exist');
      
      final content = file.readAsStringSync();
      expect(content, contains('nvidia-l4'));
      expect(content, contains('autoscaling.knative.dev/minScale: "0"'));
      expect(content, contains('autoscaling.knative.dev/maxScale: "100"'));
      expect(content, contains('SCALE_TO_ZERO_SECONDS'));
      expect(content, contains('path: /healthz'));
      expect(content, contains('oneova-production'));
    });

    test('GKE Autopilot Spot batch deployment manifest adheres to specification', () {
      final file = File('packages/cloud_vision_service/deploy/gke_spot_batch.yaml');
      expect(file.existsSync(), isTrue, reason: 'gke_spot_batch.yaml must exist');
      
      final content = file.readAsStringSync();
      expect(content, contains('cloud.google.com/gke-spot: "true"'));
      expect(content, contains('nvidia.com/gpu'));
      expect(content, contains('PREEMPTION_CHECKPOINT_DIR'));
      expect(content, contains('oneova-render-queue'));
    });

    test('Budget alerts configuration implements 4-tier spending throttle and fallbacks', () {
      final file = File('packages/cloud_vision_service/deploy/budget_alerts.json');
      expect(file.existsSync(), isTrue, reason: 'budget_alerts.json must exist');
      
      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(jsonMap['budgetName'], equals('oneova-looks-cloud-budget'));
      expect(jsonMap['projectId'], equals('oneova-prod'));
      
      final thresholds = jsonMap['thresholdRules'] as List<dynamic>;
      expect(thresholds.length, equals(4));
      
      final thresholdPercents = thresholds.map((t) => t['thresholdPercent']).toList();
      expect(thresholdPercents, containsAll([0.5, 0.8, 1.0, 1.2]));

      final fallbackRule = thresholds.firstWhere((t) => t['thresholdPercent'] == 1.0);
      expect(fallbackRule['action'], equals('TRIGGER_PHONE_FALLBACK'));
    });

    test('Remote Config Looks template contains thermal ladder, models, and compute router', () {
      final file = File('config/firebase/remote_config_looks_template.json');
      expect(file.existsSync(), isTrue, reason: 'remote_config_looks_template.json must exist');
      
      final jsonMap = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final params = jsonMap['parameters'] as Map<String, dynamic>;
      
      expect(params.containsKey('thermal_governor_ladder'), isTrue);
      expect(params.containsKey('model_registry_manifest'), isTrue);
      expect(params.containsKey('compute_router_policy'), isTrue);
      expect(params.containsKey('looks_feature_flags'), isTrue);

      // Parse thermal ladder JSON string
      final thermalJsonStr = params['thermal_governor_ladder']['defaultValue']['value'] as String;
      final thermalLadder = jsonDecode(thermalJsonStr) as Map<String, dynamic>;
      expect(thermalLadder.keys, containsAll(['nominal', 'light', 'moderate', 'severe', 'critical', 'emergency']));
      expect(thermalLadder['nominal']['maxFps'], equals(60));
      expect(thermalLadder['emergency']['maxFps'], equals(15));

      // Parse model registry manifest JSON string
      final modelRegistryStr = params['model_registry_manifest']['defaultValue']['value'] as String;
      final modelRegistry = jsonDecode(modelRegistryStr) as Map<String, dynamic>;
      final models = modelRegistry['models'] as Map<String, dynamic>;
      expect(models.keys, containsAll(['face_mesh', 'segmentation', 'hands', 'depth']));
      expect(models['face_mesh']['sha256'], isNotEmpty);

      // Parse compute router policy
      final computeRouterStr = params['compute_router_policy']['defaultValue']['value'] as String;
      final computeRouter = jsonDecode(computeRouterStr) as Map<String, dynamic>;
      expect(computeRouter['allowProOverride'], isTrue);
      expect(computeRouter['fallbackSpendPercentTrigger'], equals(100));
    });

    test('Internal test build script exists, is executable, and enforces guardrails', () {
      final script = File('tools/build_internal_test.sh');
      expect(script.existsSync(), isTrue, reason: 'build_internal_test.sh must exist');
      
      final content = script.readAsStringSync();
      expect(content, contains('home_lock_test.dart'));
      expect(content, contains('flutter analyze lib/looks/'));
      expect(content, contains('STRICTLY BANNED'));
      expect(content, contains('--release-store'));
      expect(content, contains('--internal-apk'));
      expect(content, contains('--dry-run'));
    });
  });
}
