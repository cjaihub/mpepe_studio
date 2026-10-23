import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/event_models.dart';

final eventBusProvider = Provider<EventBusService>((ref) {
  return EventBusService();
});

class EventBusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Fire an event into the global canonical event bus.
  /// 
  /// Enforces: Authentication, Idempotency, Deduplication, Auditing.
  Future<void> publishEvent({
    required String eventId, // Client-generated UUID for idempotency
    required AppEventType type,
    required String targetId,
    required Map<String, dynamic> payload,
    int sequenceNumber = 0, // Enforces ordering where necessary
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('Unauthenticated: Cannot publish canonical event.');
    }

    final eventRef = _firestore.collection('system_events').doc(eventId);
    
    // Write within a transaction to enforce Deduplication and Idempotency
    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(eventRef);
      if (doc.exists) {
        // Idempotent return: If the eventId already exists, we do not double-process.
        return; 
      }

      final canonicalEvent = CanonicalEvent(
        eventId: eventId,
        type: type,
        actorId: uid,
        targetId: targetId,
        payload: payload,
        sequenceNumber: sequenceNumber,
        timestamp: DateTime.now(),
        isProcessed: false, // Picked up by Cloud Functions retry queues
        retryCount: 0,
      );

      // 1. Publish to the unified event stream
      transaction.set(eventRef, canonicalEvent.toMap());

      // 2. Strongly audit the action in the immutable audit log
      transaction.set(
        _firestore.collection('audit_logs').doc(eventId),
        {
          'eventId': eventId,
          'action': type.eventName,
          'actorId': uid,
          'targetId': targetId,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'published',
        }
      );
    });
  }

  /// Specialized method for retryable failed events (simulated backend queue pull)
  /// If a cloud function fails to process (e.g. video processing fail), it increments retryCount.
  Future<void> retryFailedEvent(String eventId) async {
    final eventRef = _firestore.collection('system_events').doc(eventId);
    
    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(eventRef);
      if (!doc.exists) return;

      final data = doc.data()!;
      final currentRetries = data['retryCount'] ?? 0;
      
      if (currentRetries >= 5) {
        // Dead letter queue
        transaction.update(eventRef, {'status': 'dead_letter'});
        return;
      }

      transaction.update(eventRef, {
        'retryCount': currentRetries + 1,
        'isProcessed': false, // Re-queues it for listeners
      });
    });
  }
}
