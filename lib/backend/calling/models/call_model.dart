import 'package:cloud_firestore/cloud_firestore.dart';

/// Media kind of a call. `group` is kept for older docs; new docs use
/// [CallModel.isGroup] together with audio/video.
enum CallType { audio, video, group }

/// Lifecycle of the whole call document (`calls/{callId}`).
///
/// ringing → active → ended, or ringing → missed / declined / busy when
/// nobody picked up. The Cloud Function `onCallStatusChanged` fans the final
/// state out to call history and missed-call notifications.
enum CallStatus { ringing, active, ended, missed, declined, busy }

/// Why a call finished; stored as `endReason` for history and UI copy.
enum CallEndReason { hangup, declined, busy, noAnswer, failed, cancelled }

/// One call (1:1 or group) in `calls/{callId}`.
///
/// Field names keep the legacy aliases (`callerId`, `participants`, `isVideo`)
/// so the existing Calls tab in messaging keeps reading history.
class CallModel {
  final String id;
  final String hostId;
  final CallType type;
  final CallStatus status;
  final List<String> participantIds;
  final bool isGroup;
  final String? title;
  final String callerName;
  final String? callerAvatar;
  final String? chatId;

  /// UUID used by CallKit / ConnectionService. Firestore ids are not UUIDs,
  /// and iOS rejects anything else.
  final String callkitId;
  final CallEndReason? endReason;
  final DateTime startedAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;

  const CallModel({
    required this.id,
    required this.hostId,
    required this.type,
    this.status = CallStatus.ringing,
    required this.participantIds,
    this.isGroup = false,
    this.title,
    this.callerName = '',
    this.callerAvatar,
    this.chatId,
    required this.callkitId,
    this.endReason,
    required this.startedAt,
    this.answeredAt,
    this.endedAt,
  });

  bool get isVideo => type == CallType.video || type == CallType.group;

  bool get isFinished =>
      status == CallStatus.ended ||
      status == CallStatus.missed ||
      status == CallStatus.declined ||
      status == CallStatus.busy;

  static DateTime? _date(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory CallModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final ids = List<String>.from(
      (data['participantIds'] ?? data['participants'] ?? const []) as List,
    );
    final rawType = data['type'] as String?;
    var type = CallType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => data['isVideo'] == true ? CallType.video : CallType.audio,
    );
    if (type == CallType.group) type = CallType.video;
    final reason = data['endReason'] as String?;
    return CallModel(
      id: doc.id,
      hostId: (data['hostId'] ?? data['callerId'] ?? '') as String,
      type: type,
      status: CallStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => CallStatus.ringing,
      ),
      participantIds: ids,
      isGroup: data['isGroup'] == true || ids.length > 2,
      title: data['title'] as String?,
      callerName: (data['callerName'] ?? '') as String,
      callerAvatar: data['callerAvatar'] as String?,
      chatId: data['chatId'] as String?,
      callkitId: (data['callkitId'] ?? '') as String,
      endReason: reason == null
          ? null
          : CallEndReason.values.firstWhere(
              (e) => e.name == reason,
              orElse: () => CallEndReason.hangup,
            ),
      startedAt: _date(data['startedAt']) ?? DateTime.now(),
      answeredAt: _date(data['answeredAt']),
      endedAt: _date(data['endedAt']),
    );
  }

  /// Initial document written when a call is placed.
  Map<String, dynamic> toCreateMap() {
    return {
      'hostId': hostId,
      'callerId': hostId,
      'type': type.name,
      'isVideo': isVideo,
      'isGroup': isGroup,
      'status': status.name,
      'participantIds': participantIds,
      'participants': participantIds,
      if (title != null) 'title': title,
      'callerName': callerName,
      if (callerAvatar != null) 'callerAvatar': callerAvatar,
      if (chatId != null) 'chatId': chatId,
      'callkitId': callkitId,
      'startedAt': FieldValue.serverTimestamp(),
    };
  }
}
