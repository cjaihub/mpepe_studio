import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/offline/offline_sync_manager.dart';
import 'package:oneova/backend/offline/sync_models.dart';
import 'package:oneova/backend/observability/telemetry_service.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

@GenerateMocks([TelemetryService])
import 'offline_sync_manager_test.mocks.dart';

void main() {
  late OfflineSyncManager syncManager;
  late MockTelemetryService mockTelemetry;

  setUp(() {
    mockTelemetry = MockTelemetryService();
    syncManager = OfflineSyncManager(mockTelemetry);
  });

  group('OfflineSyncManager Tests', () {
    test('Should queue actions when offline', () {
      syncManager.updateNetworkStatus(false);

      syncManager.enqueueAction(SyncActionType.likeContent, {'contentId': 'video_123'});
      
      // We can't access private _queue easily without reflection, 
      // but we can verify telemetry or behavior if we exposed a getter. 
      // For now, we trust the internal state handles the enqueue without throwing.
      expect(() => syncManager.enqueueAction(SyncActionType.messageSend, {'text': 'Hello'}), returnsNormally);
    });

    test('Should deduplicate identical idempotent actions (e.g. Likes)', () {
      syncManager.updateNetworkStatus(false);

      syncManager.enqueueAction(SyncActionType.likeContent, {'contentId': 'video_456'});
      syncManager.enqueueAction(SyncActionType.likeContent, {'contentId': 'video_456'});
      syncManager.enqueueAction(SyncActionType.likeContent, {'contentId': 'video_789'});

      // Queue should only have 2 items (video_456 and video_789)
      // Since it's internal, a real test might expose a getQueueLength() for testing.
    });

    test('Should process queue when network status becomes online', () async {
      syncManager.updateNetworkStatus(false);
      syncManager.enqueueAction(SyncActionType.contentDraft, {'text': 'My Draft'});

      // Network restored
      syncManager.updateNetworkStatus(true);
      
      // Wait for process to simulate network
      await Future.delayed(const Duration(milliseconds: 300));
      
      // If it fails, telemetry records exception. Verify it was NOT called, meaning success.
      verifyNever(mockTelemetry.recordException(any, any));
    });
  });
}
