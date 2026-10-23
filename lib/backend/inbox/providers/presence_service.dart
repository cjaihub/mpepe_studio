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

final userPresenceProvider = StreamProvider.family<bool, String>((ref, userId) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((snapshot) {
        if (!snapshot.exists) return false;
        final data = snapshot.data();
        if (data == null) return false;
        
        final isOnline = data['isOnline'] as bool? ?? false;
        if (!isOnline) return false;
        
        final lastSeen = (data['lastSeen'] as Timestamp?)?.toDate();
        if (lastSeen == null) return false;
        
        // Consider offline if lastSeen is older than 2 minutes
        if (DateTime.now().difference(lastSeen).inMinutes > 2) {
          return false;
        }
        
        return true;
      });
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

  void dispose() {
    _stopHeartbeat();
  }
}
