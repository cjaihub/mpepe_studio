import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/device_session.dart';

final sessionManagerServiceProvider = Provider<SessionManagerService>((ref) {
  return SessionManagerService(FirebaseFirestore.instance);
});

class SessionManagerService {
  final FirebaseFirestore _firestore;

  SessionManagerService(this._firestore);

  /// Registers a new device session in Firestore and notifies user devices of the login.
  /// Typically called upon a successful login.
  Future<void> registerSession(String userId, DeviceSession session) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('sessions')
        .doc(session.sessionId)
        .set(session.toMap());

    // Security alert notification in real time
    try {
      await _firestore.collection('notifications').add({
        'userId': userId,
        'category': 'security',
        'priority': 'high',
        'title': 'New Login Alert',
        'body': 'Your account was accessed from ${session.deviceName} (${session.os}) at ${session.location} [${session.ipAddress}].',
        'deepLink': '/settings/security',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Revokes an active session, flagging it so security rules can reject it.
  Future<void> revokeSession(String userId, String sessionId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('sessions')
        .doc(sessionId)
        .update({'isRevoked': true});
  }

  /// Streams the active sessions for a user to display in the UI.
  Stream<List<DeviceSession>> streamSessions(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('sessions')
        .where('isRevoked', isEqualTo: false)
        .orderBy('lastActiveAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DeviceSession.fromMap(doc.data(), doc.id))
            .toList());
  }
}
