import 'package:oneova/backend/sync/models/sync_models.dart';

// Interface simulating the actual server database to test versioning blocks
abstract class RemoteServerStub {
  int getServerEntityVersion(String entityId);
  void executeWrite(String entityId, Map<String, dynamic> data, int newVersion);
}

class SyncEngine {
  final RemoteServerStub _remoteServer;
  
  final List<OfflineAction> _actionQueue = [];
  final Map<String, UploadTask> _uploadQueue = {};
  
  bool _isOnline = false;

  SyncEngine(this._remoteServer);

  void setNetworkStatus(bool isOnline) {
    _isOnline = isOnline;
    if (_isOnline) {
      _flushQueue();
      _resumeUploads();
    }
  }

  void queueAction(OfflineAction action) {
    if (_isOnline) {
      _executeActionDirectly(action);
    } else {
      _actionQueue.add(action);
    }
  }

  void _flushQueue() {
    if (_actionQueue.isEmpty) return;

    // Deduplicate: If multiple offline edits exist for the same entity, collapse them
    // For simplicity, we just execute sequentially, but a real engine collapses.
    
    final failedDueToConflict = <OfflineAction>[];

    for (var action in _actionQueue) {
      try {
        _executeActionDirectly(action);
      } catch (e) {
        if (e.toString().contains('Stale state conflict')) {
          failedDueToConflict.add(action);
        } else {
          rethrow; // Other network error, leave in queue
        }
      }
    }

    _actionQueue.clear();
    
    // Unresolved conflicts are escalated or discarded based on strategy (we drop to protect server)
    if (failedDueToConflict.isNotEmpty) {
      // Typically fires a UI event "Some offline changes could not be synced because the post was edited elsewhere"
    }
  }

  void _executeActionDirectly(OfflineAction action) {
    // CRITICAL CONSTRAINT: Never allow offline stale state to silently overwrite newer server state.
    final serverVersion = _remoteServer.getServerEntityVersion(action.targetEntityId);

    if (serverVersion > action.localBaseVersion) {
      // The server has moved ahead since the user went offline!
      // Silently overwriting would destroy data.
      throw Exception('Stale state conflict: Server version $serverVersion is newer than local base ${action.localBaseVersion}');
    }

    // Safe to execute
    _remoteServer.executeWrite(action.targetEntityId, action.payload, action.localBaseVersion + 1);
  }

  // --- Upload Resilience ---
  void queueUpload(UploadTask task) {
    _uploadQueue[task.id] = task;
    if (_isOnline) _resumeUploads();
  }

  void _resumeUploads() {
    for (var task in _uploadQueue.values) {
      if (!task.isPaused && task.uploadedBytes < task.totalBytes) {
        // Mocking resume logic
        task.uploadedBytes = task.totalBytes; // simulate instant finish
      }
    }
  }
  
  List<OfflineAction> get queuedActions => List.unmodifiable(_actionQueue);
}
