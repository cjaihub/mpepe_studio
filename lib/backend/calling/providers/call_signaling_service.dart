import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/call_model.dart';
import '../models/call_participant.dart';

final callSignalingServiceProvider = Provider<CallSignalingService>((ref) {
  return CallSignalingService();
});

/// Someone to ring.
class CallTarget {
  final String userId;
  final String name;
  final String? avatar;

  const CallTarget({required this.userId, this.name = '', this.avatar});
}

/// Firestore side of the call lifecycle (`calls/{callId}` and its
/// `participants` subcollection). WebRTC offers/answers/candidates live in
/// `signaling` and are handled by `WebRTCConnectionManager`.
class CallSignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get currentUserId => _auth.currentUser?.uid ?? '';

  DocumentReference<Map<String, dynamic>> callRef(String callId) =>
      _firestore.collection('calls').doc(callId);

  DocumentReference<Map<String, dynamic>> _participantRef(String callId, String uid) =>
      callRef(callId).collection('participants').doc(uid);

  /// Resolves a display name and avatar from `users/{uid}`.
  Future<CallTarget> resolveUser(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final d = doc.data() ?? const <String, dynamic>{};
      String pick(List<String> keys) {
        for (final k in keys) {
          final v = d[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return '';
      }

      final name = pick(['fullName', 'displayName', 'username']);
      final avatar = pick(['profilePhotoUrl', 'photoUrl', 'avatarUrl']);
      return CallTarget(
        userId: uid,
        name: name.isEmpty ? 'Oneova user' : name,
        avatar: avatar.isEmpty ? null : avatar,
      );
    } catch (e) {
      debugPrint('[CallSignaling] resolveUser($uid) failed: $e');
      return CallTarget(userId: uid, name: 'Oneova user');
    }
  }

  /// Places a call. Writing the ringing participant docs is what triggers the
  /// server push (see functions/src/calls.ts).
  Future<CallModel> createCall({
    required List<String> targetUserIds,
    required bool isVideo,
    String? chatId,
    String? title,
  }) async {
    final me = currentUserId;
    if (me.isEmpty) throw StateError('Not signed in');
    final targets = targetUserIds.where((id) => id.isNotEmpty && id != me).toSet().toList();
    if (targets.isEmpty) throw ArgumentError('No one to call');

    final self = await resolveUser(me);
    final resolved = await Future.wait(targets.map(resolveUser));
    final ref = _firestore.collection('calls').doc();
    final call = CallModel(
      id: ref.id,
      hostId: me,
      type: isVideo ? CallType.video : CallType.audio,
      participantIds: [me, ...targets],
      isGroup: targets.length > 1,
      title: title,
      callerName: self.name,
      callerAvatar: self.avatar,
      chatId: chatId,
      callkitId: const Uuid().v4(),
      startedAt: DateTime.now(),
    );

    final batch = _firestore.batch();
    batch.set(ref, call.toCreateMap());
    batch.set(
      _participantRef(ref.id, me),
      {
        ...CallParticipant(
          userId: me,
          status: ParticipantStatus.joined,
          name: self.name,
          avatar: self.avatar,
          isVideoMuted: !isVideo,
        ).toMap(),
        'userId': me,
      },
    );
    for (final t in resolved) {
      batch.set(
        _participantRef(ref.id, t.userId),
        {
          ...CallParticipant(userId: t.userId, name: t.name, avatar: t.avatar).toMap(),
          'userId': t.userId,
        },
      );
    }
    await batch.commit();
    return call;
  }

  /// Rings more people into an existing call (turns it into a group call).
  Future<void> addParticipants(String callId, List<String> userIds) async {
    final snap = await callRef(callId).get();
    final existing = List<String>.from((snap.data()?['participantIds'] ?? const []) as List);
    final fresh = userIds.where((u) => u.isNotEmpty && !existing.contains(u)).toSet().toList();
    if (fresh.isEmpty) return;
    final resolved = await Future.wait(fresh.map(resolveUser));
    final batch = _firestore.batch();
    batch.update(callRef(callId), {
      'participantIds': FieldValue.arrayUnion(fresh),
      'participants': FieldValue.arrayUnion(fresh),
      'isGroup': true,
    });
    for (final t in resolved) {
      batch.set(_participantRef(callId, t.userId), {
        ...CallParticipant(userId: t.userId, name: t.name, avatar: t.avatar).toMap(),
        'userId': t.userId,
      });
    }
    await batch.commit();
  }

  Future<CallModel?> getCall(String callId) async {
    final doc = await callRef(callId).get();
    if (!doc.exists) return null;
    return CallModel.fromFirestore(doc);
  }

  Future<ParticipantStatus?> myStatus(String callId) async {
    final doc = await _participantRef(callId, currentUserId).get();
    if (!doc.exists) return null;
    return CallParticipant.fromFirestore(doc).status;
  }

  /// Accepts on this device. Other devices of the same user stop ringing
  /// because the server sends a `call_cancel` push when the status leaves
  /// `ringing`.
  Future<void> acceptCall(String callId, {required bool videoOn}) async {
    final me = currentUserId;
    await _participantRef(callId, me).set({
      'status': ParticipantStatus.joined.name,
      'joinedAt': FieldValue.serverTimestamp(),
      'isVideoMuted': !videoOn,
      'isAudioMuted': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(callRef(callId));
      final data = snap.data();
      if (data == null) return;
      if (data['status'] == CallStatus.ringing.name) {
        tx.update(callRef(callId), {
          'status': CallStatus.active.name,
          'answeredAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> declineCall(String callId) =>
      _setMyStatusAndSettle(callId, ParticipantStatus.declined);

  /// Auto-reply when this user is already in another call.
  Future<void> markBusy(String callId) =>
      _setMyStatusAndSettle(callId, ParticipantStatus.busy);

  Future<void> leaveCall(String callId) =>
      _setMyStatusAndSettle(callId, ParticipantStatus.left);

  /// Connection could not be recovered (network gone, peer unreachable).
  Future<void> markDropped(String callId) =>
      _setMyStatusAndSettle(callId, ParticipantStatus.dropped);

  Future<void> _setMyStatusAndSettle(String callId, ParticipantStatus status) async {
    final me = currentUserId;
    if (me.isEmpty) return;
    try {
      await _participantRef(callId, me).set({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await settleCall(callId);
    } catch (e) {
      debugPrint('[CallSignaling] set ${status.name} failed: $e');
    }
  }

  /// Caller gave up (hang up while ringing) or the ring timed out.
  Future<void> cancelRinging(String callId, {required bool timedOut}) async {
    final participants = await callRef(callId).collection('participants').get();
    final batch = _firestore.batch();
    for (final doc in participants.docs) {
      final p = CallParticipant.fromFirestore(doc);
      if (p.status == ParticipantStatus.ringing) {
        batch.update(doc.reference, {
          'status': ParticipantStatus.missed.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else if (p.userId == currentUserId && p.status == ParticipantStatus.joined) {
        batch.update(doc.reference, {
          'status': ParticipantStatus.left.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
    await settleCall(
      callId,
      forcedReason: timedOut ? CallEndReason.noAnswer : CallEndReason.cancelled,
    );
  }

  /// Ends the call document once fewer than two people can still talk.
  Future<void> settleCall(String callId, {CallEndReason? forcedReason}) async {
    final ref = callRef(callId);
    final participants = await ref.collection('participants').get();
    var joined = 0;
    var ringing = 0;
    var declined = 0;
    var busy = 0;
    for (final doc in participants.docs) {
      switch (CallParticipant.fromFirestore(doc).status) {
        case ParticipantStatus.joined:
          joined++;
          break;
        case ParticipantStatus.ringing:
          ringing++;
          break;
        case ParticipantStatus.declined:
          declined++;
          break;
        case ParticipantStatus.busy:
          busy++;
          break;
        default:
          break;
      }
    }
    final stillAlive = joined >= 2 || (joined == 1 && ringing > 0);
    if (stillAlive && forcedReason == null) return;

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if (data == null) return;
      final current = data['status'] as String?;
      if (current != CallStatus.ringing.name && current != CallStatus.active.name) return;

      final answered = data['answeredAt'] != null;
      CallStatus status;
      CallEndReason reason;
      if (answered) {
        status = CallStatus.ended;
        reason = CallEndReason.hangup;
      } else if (forcedReason == CallEndReason.cancelled) {
        status = CallStatus.missed;
        reason = CallEndReason.cancelled;
      } else if (busy > 0 && declined == 0) {
        status = CallStatus.busy;
        reason = CallEndReason.busy;
      } else if (declined > 0 && ringing == 0) {
        status = CallStatus.declined;
        reason = CallEndReason.declined;
      } else {
        status = CallStatus.missed;
        reason = forcedReason ?? CallEndReason.noAnswer;
      }
      tx.update(ref, {
        'status': status.name,
        'endReason': reason.name,
        'endedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateMediaState(
    String callId, {
    bool? audioMuted,
    bool? videoMuted,
  }) async {
    final me = currentUserId;
    if (me.isEmpty) return;
    try {
      await _participantRef(callId, me).set({
        'isAudioMuted': ?audioMuted,
        'isVideoMuted': ?videoMuted,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[CallSignaling] updateMediaState failed: $e');
    }
  }

  Future<List<CallParticipant>> fetchParticipants(String callId) async {
    final snap = await callRef(callId).collection('participants').get();
    return snap.docs.map(CallParticipant.fromFirestore).toList();
  }

  Stream<CallModel?> watchCall(String callId) => callRef(callId)
      .snapshots()
      .map((d) => d.exists ? CallModel.fromFirestore(d) : null);

  Stream<List<CallParticipant>> watchParticipants(String callId) => callRef(callId)
      .collection('participants')
      .snapshots()
      .map((s) => s.docs.map(CallParticipant.fromFirestore).toList());

  /// Calls that are ringing this user right now (foreground path; background
  /// and killed-app ringing comes from the push + CallKit).
  Stream<List<CallModel>> streamIncomingCalls() {
    final uid = currentUserId;
    if (uid.isEmpty) return const Stream.empty();

    return _firestore
        .collection('calls')
        .where('participantIds', arrayContains: uid)
        .where('status', whereIn: [CallStatus.ringing.name, CallStatus.active.name])
        .snapshots()
        .asyncMap((snapshot) async {
      final calls = <CallModel>[];
      for (final doc in snapshot.docs) {
        final call = CallModel.fromFirestore(doc);
        if (call.hostId == uid) continue;
        // Ignore stale rings older than two minutes.
        if (DateTime.now().difference(call.startedAt).inMinutes >= 2 &&
            call.status == CallStatus.ringing) {
          continue;
        }
        final pDoc = await doc.reference.collection('participants').doc(uid).get();
        if (pDoc.exists && CallParticipant.fromFirestore(pDoc).status == ParticipantStatus.ringing) {
          calls.add(call);
        }
      }
      return calls;
    });
  }
}
