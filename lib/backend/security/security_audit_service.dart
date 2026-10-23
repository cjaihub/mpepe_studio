import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final securityAuditServiceProvider = Provider<SecurityAuditService>((ref) {
  return SecurityAuditService(FirebaseFirestore.instance);
});

enum SecurityEventType {
  login,
  passkeyRegistered,
  e2eKeyGenerated,
  privacySettingsChanged,
  aiAccessRevoked,
  dataExportRequested,
  accountDeletionRequested,
}

class SecurityEvent {
  final String id;
  final SecurityEventType type;
  final String description;
  final DateTime timestamp;
  final String ipAddress;
  final String userAgent;

  SecurityEvent({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.ipAddress,
    required this.userAgent,
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'description': description,
      'timestamp': Timestamp.fromDate(timestamp),
      'ipAddress': ipAddress,
      'userAgent': userAgent,
    };
  }

  factory SecurityEvent.fromMap(Map<String, dynamic> map, String id) {
    return SecurityEvent(
      id: id,
      type: SecurityEventType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => SecurityEventType.login,
      ),
      description: map['description'] ?? '',
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ipAddress: map['ipAddress'] ?? 'Unknown',
      userAgent: map['userAgent'] ?? 'Unknown',
    );
  }
}

class SecurityAuditService {
  final FirebaseFirestore _firestore;

  SecurityAuditService(this._firestore);

  /// Logs a critical security event to the immutable audit log.
  Future<void> logEvent({
    required String userId,
    required SecurityEventType type,
    required String description,
    required String ipAddress,
    required String userAgent,
  }) async {
    final event = SecurityEvent(
      id: '',
      type: type,
      description: description,
      timestamp: DateTime.now(),
      ipAddress: ipAddress,
      userAgent: userAgent,
    );

    // security_events is written only by Ova Guard (Cloud Functions) now;
    // client-side audit entries stay local to the debug log.
    debugPrint('[SecurityAudit] ${event.type.name} for $userId: ${event.description}');
  }

  /// Streams the audit log for user visibility
  Stream<List<SecurityEvent>> streamEvents(String userId) {
    return _firestore
        .collection('security_events')
        .doc(userId)
        .collection('events')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SecurityEvent.fromMap(doc.data(), doc.id))
            .toList());
  }
}
