import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final presenceServiceProvider = Provider<PresenceService>((ref) {
  final service = PresenceService(FirebaseFirestore.instance);
  ref.onDispose(() => service.dispose());
  return service;
});

enum PresenceStatus { online, inCall, inLive, recentlyActive, offline }

class UserPresence {
  final PresenceStatus status;
  final DateTime? lastSeen;
  final String? callId;
  final String? liveStreamId;

  const UserPresence({
    this.status = PresenceStatus.offline,
    this.lastSeen,
    this.callId,
    this.liveStreamId,
  });

  bool get isOnline =>
      status == PresenceStatus.online ||
      status == PresenceStatus.inCall ||
      status == PresenceStatus.inLive;
  bool get isInCall => status == PresenceStatus.inCall;
  bool get isInLive => status == PresenceStatus.inLive;

  String get label {
    switch (status) {
      case PresenceStatus.online:
        return 'Active now';
      case PresenceStatus.inCall:
        return 'In a call';
      case PresenceStatus.inLive:
        return 'Live now';
      case PresenceStatus.recentlyActive:
        if (lastSeen != null) {
          final diff = DateTime.now().difference(lastSeen!);
          if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
          if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
        }
        return 'Recently active';
      case PresenceStatus.offline:
        if (lastSeen != null) {
          final diff = DateTime.now().difference(lastSeen!);
          if (diff.inMinutes < 60) return 'Active ${diff.inMinutes}m ago';
          if (diff.inHours < 24) return 'Active ${diff.inHours}h ago';
          if (diff.inDays < 7) return 'Active ${diff.inDays}d ago';
        }
        return 'Offline';
    }
  }
}

final userPresenceDetailsProvider =
    StreamProvider.family<UserPresence, String>((ref, userId) {
  if (userId.isEmpty) return Stream.value(const UserPresence());
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists) return const UserPresence();
    final data = snapshot.data();
    if (data == null) return const UserPresence();

    final isOnline = data['isOnline'] as bool? ?? false;
    final inCall = data['inCall'] as bool? ?? false;
    final inLive = data['inLive'] as bool? ?? false;
    final callId = data['activeCallId'] as String?;
    final liveStreamId = data['activeStreamId'] as String?;
    final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate();

    if (inCall) {
      return UserPresence(
        status: PresenceStatus.inCall,
        lastSeen: lastSeen,
        callId: callId,
      );
    }
    if (inLive) {
      return UserPresence(
        status: PresenceStatus.inLive,
        lastSeen: lastSeen,
        liveStreamId: liveStreamId,
      );
    }
    if (isOnline && lastSeen != null) {
      final diff = DateTime.now().difference(lastSeen);
      if (diff.inMinutes <= 2) {
        return UserPresence(
          status: PresenceStatus.online,
          lastSeen: lastSeen,
        );
      } else if (diff.inMinutes <= 15) {
        return UserPresence(
          status: PresenceStatus.recentlyActive,
          lastSeen: lastSeen,
        );
      }
    }
    return UserPresence(
      status: PresenceStatus.offline,
      lastSeen: lastSeen,
    );
  });
});

final userPresenceProvider = StreamProvider.family<bool, String>((ref, userId) {
  return ref.watch(userPresenceDetailsProvider(userId)).when(
        data: (presence) => Stream.value(presence.isOnline),
        loading: () => Stream.value(false),
        error: (_, __) => Stream.value(false),
      );
});

class PresenceService {
  final FirebaseFirestore _firestore;
  Timer? _heartbeatTimer;
  String? _userId;

  PresenceService(this._firestore) {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _userId = user.uid;
        _startHeartbeat();
      } else {
        _stopHeartbeat();
        _userId = null;
      }
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _updatePresence();
    // Update presence every 60 seconds
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _updatePresence();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _updatePresence() async {
    if (_userId == null) return;
    try {
      await _firestore.collection('users').doc(_userId).set({
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  /// Sets online status explicitly.
  Future<void> setOnline() async {
    await _updatePresence();
  }

  /// Sets offline status explicitly. 
  /// In a real app with RTDB, this would be an onDisconnect hook.
  Future<void> setOffline() async {
    if (_userId == null) return;
    try {
      await _firestore.collection('users').doc(_userId).set({
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': false,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error setting offline: $e');
    }
  }

  /// Updates in-call status for live presence indicators
  Future<void> setInCall(String? callId) async {
    if (_userId == null) return;
    try {
      await _firestore.collection('users').doc(_userId).set({
        'inCall': callId != null,
        'activeCallId': callId,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Updates in-live status for live presence indicators
  Future<void> setInLive(String? streamId) async {
    if (_userId == null) return;
    try {
      await _firestore.collection('users').doc(_userId).set({
        'inLive': streamId != null,
        'activeStreamId': streamId,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void dispose() {
    _stopHeartbeat();
  }
}
