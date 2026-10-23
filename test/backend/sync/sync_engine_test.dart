import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/sync/models/sync_models.dart';
import 'package:oneova/backend/sync/services/sync_engine.dart';

// Mock server mapping entityId -> version
class MockRemoteServer implements RemoteServerStub {
  final Map<String, int> _serverVersions = {
    'post_1': 2, // Post was edited on the server since user synced
    'post_2': 1, // Safe
  };

  @override
  int getServerEntityVersion(String entityId) {
    return _serverVersions[entityId] ?? 0;
  }

  @override
  void executeWrite(String entityId, Map<String, dynamic> data, int newVersion) {
    _serverVersions[entityId] = newVersion;
  }
}

void main() {
  late SyncEngine engine;
  late MockRemoteServer mockServer;

  setUp(() {
    mockServer = MockRemoteServer();
    engine = SyncEngine(mockServer);
  });

  test('SyncEngine blocks stale offline overwrites', () {
    engine.setNetworkStatus(false);

    // User edits post_1 offline, believing it's at version 1
    final staleEdit = OfflineAction(
      id: 'act_1',
      type: ActionType.editDraft,
      targetEntityId: 'post_1',
      localBaseVersion: 1, // STALE! Server is at 2
      payload: {'title': 'Offline Title'},
      queuedAt: DateTime.now(),
    );

    // User edits post_2 offline, believing it's at version 1
    final safeEdit = OfflineAction(
      id: 'act_2',
      type: ActionType.editDraft,
      targetEntityId: 'post_2',
      localBaseVersion: 1, // SAFE! Server is at 1
      payload: {'title': 'Offline Title'},
      queuedAt: DateTime.now(),
    );

    engine.queueAction(staleEdit);
    engine.queueAction(safeEdit);

    expect(engine.queuedActions.length, 2);

    // Reconnects to network
    engine.setNetworkStatus(true); // Triggers flushQueue

    // The flush should have attempted both. 
    // `post_1` should have thrown an internal error and been swallowed/escalated.
    // `post_2` should have succeeded and incremented the server version to 2.

    expect(mockServer.getServerEntityVersion('post_1'), 2); // Unchanged, protected from stale overwrite
    expect(mockServer.getServerEntityVersion('post_2'), 2); // Safely incremented by the successful edit
    
    // Queue should be cleared
    expect(engine.queuedActions.length, 0);
  });
}
