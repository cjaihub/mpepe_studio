import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sync_models.dart';
import '../observability/telemetry_service.dart';

final offlineSyncProvider = Provider<OfflineSyncManager>((ref) {
  return OfflineSyncManager(ref.read(telemetryServiceProvider));
});

/// Manages offline-first operations and resilient background sync.
/// Ensures that the Server Remains Authoritative upon conflict resolution.
class OfflineSyncManager {
  final TelemetryService _telemetry;
  final List<SyncAction> _queue = [];
  bool _isOnline = true; // Typically updated via connectivity_plus listener
  bool _isSyncing = false;

  OfflineSyncManager(this._telemetry) {
    _loadPersistedQueue();
  }

  /// Called by the Connectivity listener when network state changes
  void updateNetworkStatus(bool isOnline) {
    _isOnline = isOnline;
    if (_isOnline) {
      _processQueue();
    }
  }

  /// Queue an action to happen immediately if online, or deferred if offline.
  void enqueueAction(SyncActionType type, Map<String, dynamic> payload) {
    final action = SyncAction(type: type, payload: payload);
    
    // Deduplication check for idempotent actions (e.g., liking the same video)
    if (_isDuplicate(action)) {
      return;
    }

    _queue.add(action);
    _persistQueue();

    if (_isOnline) {
      _processQueue();
    }
  }

  bool _isDuplicate(SyncAction newAction) {
    if (newAction.type == SyncActionType.likeContent) {
      return _queue.any((a) => a.type == newAction.type && a.payload['contentId'] == newAction.payload['contentId']);
    }
    return false;
  }

  Future<void> _processQueue() async {
    if (_isSyncing || _queue.isEmpty || !_isOnline) return;
    _isSyncing = true;

    // Sort by oldest first for causality where necessary.
    _queue.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));

    final toRemove = <String>[];

    for (final action in _queue) {
      if (action.isProcessing) continue;
      action.isProcessing = true;

      try {
        await _executeActionAgainstServer(action);
        toRemove.add(action.id);
      } catch (e) {
        action.retryCount++;
        _telemetry.recordException(e as Exception, StackTrace.current);
        if (action.retryCount >= 5) {
          // Dead letter queue or drop depending on business logic
          toRemove.add(action.id); 
        }
      } finally {
        action.isProcessing = false;
      }
    }

    _queue.removeWhere((a) => toRemove.contains(a.id));
    _persistQueue();
    _isSyncing = false;
  }

  Future<void> _executeActionAgainstServer(SyncAction action) async {
    // In a real implementation, this routes to the respective Repository/API.
    // E.g., if (action.type == SyncActionType.likeContent) { api.like(...) }
    
    // Simulating server authoritative resolution:
    // If the server rejects it (e.g., post was deleted while offline), 
    // the API throws, we catch it, and if it's a 404, we drop the action (authoritative).
    await Future.delayed(const Duration(milliseconds: 200));
  }

  // ---- Mock Persistence Layer ----
  void _persistQueue() {
    // Write _queue.map((e)=>e.toJson()) to SharedPreferences or Hive.
  }

  void _loadPersistedQueue() {
    // Read from SharedPreferences or Hive and populate _queue.
  }
}
