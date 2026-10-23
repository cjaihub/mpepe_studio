import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-user state in `calls/{callId}/participants/{uid}`.
///
/// Creating a doc with status `ringing` is what makes the Cloud Function
/// `onCallParticipantRinging` push the incoming call to that user's devices.
enum ParticipantStatus { ringing, joined, declined, left, dropped, busy, missed }

class CallParticipant {
  final String userId;
  final ParticipantStatus status;
  final String name;
  final String? avatar;
  final bool isAudioMuted;
  final bool isVideoMuted;
  final bool isScreenSharing;
  final DateTime? joinedAt;

  const CallParticipant({
    required this.userId,
    this.status = ParticipantStatus.ringing,
    this.name = '',
    this.avatar,
    this.isAudioMuted = false,
    this.isVideoMuted = false,
    this.isScreenSharing = false,
    this.joinedAt,
  });

  bool get isActive => status == ParticipantStatus.joined;

  factory CallParticipant.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return CallParticipant(
      userId: doc.id,
      status: ParticipantStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => ParticipantStatus.ringing,
      ),
      name: (data['name'] ?? '') as String,
      avatar: data['avatar'] as String?,
      isAudioMuted: data['isAudioMuted'] ?? false,
      isVideoMuted: data['isVideoMuted'] ?? false,
      isScreenSharing: data['isScreenSharing'] ?? false,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status.name,
      'name': name,
      if (avatar != null) 'avatar': avatar,
      'isAudioMuted': isAudioMuted,
      'isVideoMuted': isVideoMuted,
      'isScreenSharing': isScreenSharing,
      'joinedAt': status == ParticipantStatus.joined ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
