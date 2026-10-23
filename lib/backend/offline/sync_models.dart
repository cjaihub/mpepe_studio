import 'package:uuid/uuid.dart';

enum SyncActionType {
  likeContent,
  commentCreate,
  messageSend,
  contentDraft,
  mediaUploadResume
}

class SyncAction {
  final String id;
  final SyncActionType type;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;
  int retryCount;
  bool isProcessing;

  SyncAction({
    String? id,
    required this.type,
    required this.payload,
    DateTime? queuedAt,
    this.retryCount = 0,
    this.isProcessing = false,
  })  : id = id ?? const Uuid().v4(),
        queuedAt = queuedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'payload': payload,
        'queuedAt': queuedAt.toIso8601String(),
        'retryCount': retryCount,
      };

  factory SyncAction.fromJson(Map<String, dynamic> json) {
    return SyncAction(
      id: json['id'],
      type: SyncActionType.values.firstWhere((e) => e.name == json['type']),
      payload: Map<String, dynamic>.from(json['payload']),
      queuedAt: DateTime.parse(json['queuedAt']),
      retryCount: json['retryCount'] ?? 0,
    );
  }
}
