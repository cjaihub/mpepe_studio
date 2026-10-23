enum ActionType {
  createDraft,
  editDraft,
  sendMessage,
  likeContent,
  uploadChunk,
}

enum SyncConflictStrategy {
  serverWins,    // Protects server state from stale offline overwrites
  clientWins,    // Dangerous, rarely used
  manualMerge,   // Escalate to user UI
}

class OfflineAction {
  final String id;
  final ActionType type;
  final String targetEntityId; // e.g., the post ID or message ID
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
  final int localBaseVersion; // Crucial for conflict resolution: what version did the user edit offline?

  OfflineAction({
    required this.id,
    required this.type,
    required this.targetEntityId,
    required this.payload,
    required this.queuedAt,
    required this.localBaseVersion,
  });
}

class UploadTask {
  final String id;
  final String filePath;
  final int totalBytes;
  int uploadedBytes;
  bool isPaused;

  UploadTask({
    required this.id,
    required this.filePath,
    required this.totalBytes,
    this.uploadedBytes = 0,
    this.isPaused = false,
  });
}
