import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/counters/models/counter_models.dart';
import 'package:oneova/backend/counters/services/counter_service.dart';

// Mock server for counter resolution
class MockCounterServer implements CounterServerStub {
  bool shouldFail = false;
  int internalCounter = 10; // Server thinks there are 10 likes initially

  @override
  Future<int> executeIncrement(CounterTransaction tx) async {
    if (shouldFail) {
      throw Exception('Server 500 Error');
    }
    internalCounter += tx.increment;
    return internalCounter; // Returns the new authoritative value
  }
}

void main() {
  late CounterService service;
  late MockCounterServer mockServer;

  setUp(() {
    mockServer = MockCounterServer();
    service = CounterService(mockServer);
    
    // Simulate initial load from server
    service.reconcileServerState('post_1', CounterType.likes, 10);
  });

  test('Optimistic UI applies immediately and reconciles on success', () async {
    final entity = service.getEntity('post_1', CounterType.likes);
    expect(entity.displayValue, 10);

    final tx = CounterTransaction(
      transactionId: 'tx_1',
      entityId: 'post_1',
      type: CounterType.likes,
      increment: 1,
      timestamp: DateTime.now(),
    );

    // Call without awaiting to check immediate optimistic state
    final future = service.submitTransaction(tx);
    
    // Optimistic state should be 11 (10 server + 1 delta)
    expect(entity.displayValue, 11);
    expect(entity.localDelta, 1);

    await future;

    // After resolution, authoritative state should be 11, delta 0
    expect(entity.displayValue, 11);
    expect(entity.serverValue, 11);
    expect(entity.localDelta, 0);
  });

  test('Duplicate idempotent requests are strictly ignored', () async {
    final entity = service.getEntity('post_1', CounterType.likes);
    
    final tx = CounterTransaction(
      transactionId: 'tx_dup',
      entityId: 'post_1',
      type: CounterType.likes,
      increment: 1,
      timestamp: DateTime.now(),
    );

    await service.submitTransaction(tx);
    expect(entity.displayValue, 11);

    // Submit identical transaction ID
    await service.submitTransaction(tx);
    
    // Should still be 11, strictly ignored
    expect(entity.displayValue, 11);
  });

  test('Transaction failure triggers strict rollback', () async {
    mockServer.shouldFail = true;
    final entity = service.getEntity('post_1', CounterType.likes);

    final tx = CounterTransaction(
      transactionId: 'tx_fail',
      entityId: 'post_1',
      type: CounterType.likes,
      increment: 1,
      timestamp: DateTime.now(),
    );

    try {
      await service.submitTransaction(tx);
    } catch (e) {
      expect(e, isA<TransactionFailureException>());
    }

    // Rollback applied: Delta should be erased, back to authoritative 10
    expect(entity.localDelta, 0);
    expect(entity.displayValue, 10);
  });

  test('Offline queues local deltas and reconciles on reconnect', () async {
    service.setNetworkStatus(false);
    final entity = service.getEntity('post_1', CounterType.likes);

    final tx = CounterTransaction(
      transactionId: 'tx_offline',
      entityId: 'post_1',
      type: CounterType.likes,
      increment: 1,
      timestamp: DateTime.now(),
    );

    // Enqueued while offline
    await service.submitTransaction(tx);

    // UI shows optimistic 11
    expect(entity.displayValue, 11);
    expect(entity.localDelta, 1);
    expect(entity.serverValue, 10);

    // Network Restored
    service.setNetworkStatus(true); // Triggers reconcile

    // Let the event loop cycle for the async reconcile
    await Future.delayed(const Duration(milliseconds: 50));

    // Reconciled: UI remains 11, but server adopted it and delta cleared
    expect(entity.displayValue, 11);
    expect(entity.localDelta, 0);
    expect(entity.serverValue, 11);
  });
}
