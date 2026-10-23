import 'package:oneova/backend/counters/models/counter_models.dart';

// Interface simulating actual server infrastructure for executing counter increments
abstract class CounterServerStub {
  Future<int> executeIncrement(CounterTransaction tx);
}

class TransactionFailureException implements Exception {
  final String message;
  TransactionFailureException(this.message);
}

class CounterService {
  final CounterServerStub _server;
  final Map<String, CounterEntity> _store = {};
  final Set<String> _processedTransactions = {}; // Deduplication ledger
  final Map<String, List<CounterTransaction>> _pendingTransactions = {};

  bool _isOnline = true;

  CounterService(this._server);

  void setNetworkStatus(bool isOnline) {
    _isOnline = isOnline;
    if (_isOnline) {
      _reconcilePending();
    }
  }

  CounterEntity getEntity(String entityId, CounterType type) {
    final key = '${type.name}_$entityId';
    return _store.putIfAbsent(key, () => CounterEntity(entityId: entityId, type: type));
  }

  // Authoritative updates from server sync events (e.g. realtime socket pushing truth)
  void reconcileServerState(String entityId, CounterType type, int authoritativeValue) {
    final entity = getEntity(entityId, type);
    entity.serverValue = authoritativeValue;
    // Local deltas remain applied until their specific transactions are resolved
  }

  Future<void> submitTransaction(CounterTransaction tx) async {
    // 1. Deduplication Check
    if (_processedTransactions.contains(tx.transactionId)) {
      return; // Ignore duplicate requests
    }
    _processedTransactions.add(tx.transactionId);

    final entity = getEntity(tx.entityId, tx.type);

    // 2. Optimistic UI update
    entity.localDelta += tx.increment;
    
    // Store in pending queue
    final key = '${tx.type.name}_${tx.entityId}';
    _pendingTransactions.putIfAbsent(key, () => []).add(tx);

    // 3. Execution (or enqueue if offline)
    if (_isOnline) {
      await _execute(tx, entity, key);
    }
  }

  Future<void> _execute(CounterTransaction tx, CounterEntity entity, String queueKey) async {
    try {
      final authoritativeServerValue = await _server.executeIncrement(tx);
      
      // SUCCESS: Clear delta, adopt authoritative truth
      entity.localDelta -= tx.increment;
      entity.serverValue = authoritativeServerValue;
      
      _pendingTransactions[queueKey]?.remove(tx);

    } catch (e) {
      // ROLLBACK: Transaction failed
      entity.localDelta -= tx.increment;
      _processedTransactions.remove(tx.transactionId); // Allow retry later
      _pendingTransactions[queueKey]?.remove(tx);
      
      throw TransactionFailureException('Transaction ${tx.transactionId} failed, rollback applied.');
    }
  }

  Future<void> _reconcilePending() async {
    final allPending = _pendingTransactions.values.expand((element) => element).toList();
    for (var tx in allPending) {
      final entity = getEntity(tx.entityId, tx.type);
      final key = '${tx.type.name}_${tx.entityId}';
      try {
        await _execute(tx, entity, key);
      } catch (e) {
        // Rollback already handled internally
      }
    }
  }
}
