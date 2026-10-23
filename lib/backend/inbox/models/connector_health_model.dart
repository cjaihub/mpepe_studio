import 'package:cloud_firestore/cloud_firestore.dart';

enum ConnectorStatus {
  connected,
  connecting,
  syncing,
  degraded,
  rateLimited,
  reauthRequired,
  disconnected,
  error,
  unknown
}

class ConnectorHealth {
  final String id; // Matches connectorId
  final String platformId;
  final String externalAccountId;
  final ConnectorStatus status;
  final DateTime? lastSuccessfulSync;
  final DateTime? lastWebhookAt;
  final DateTime? lastApiSuccessAt;
  final DateTime? lastErrorAt;
  final String? errorCode;
  final bool reauthenticationRequired;
  final List<String> capabilities;
  final DateTime updatedAt;

  ConnectorHealth({
    required this.id,
    required this.platformId,
    required this.externalAccountId,
    this.status = ConnectorStatus.unknown,
    this.lastSuccessfulSync,
    this.lastWebhookAt,
    this.lastApiSuccessAt,
    this.lastErrorAt,
    this.errorCode,
    this.reauthenticationRequired = false,
    this.capabilities = const [],
    required this.updatedAt,
  });

  factory ConnectorHealth.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    ConnectorStatus parsedStatus = ConnectorStatus.unknown;
    final String sStr = data['status'] ?? '';
    for (var s in ConnectorStatus.values) {
      if (s.name.toLowerCase() == sStr.toLowerCase()) {
        parsedStatus = s;
        break;
      }
    }

    return ConnectorHealth(
      id: doc.id,
      platformId: data['platformId'] ?? '',
      externalAccountId: data['externalAccountId'] ?? '',
      status: parsedStatus,
      lastSuccessfulSync: (data['lastSuccessfulSync'] as Timestamp?)?.toDate(),
      lastWebhookAt: (data['lastWebhookAt'] as Timestamp?)?.toDate(),
      lastApiSuccessAt: (data['lastApiSuccessAt'] as Timestamp?)?.toDate(),
      lastErrorAt: (data['lastErrorAt'] as Timestamp?)?.toDate(),
      errorCode: data['errorCode'],
      reauthenticationRequired: data['reauthenticationRequired'] ?? false,
      capabilities: List<String>.from(data['capabilities'] ?? []),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'platformId': platformId,
      'externalAccountId': externalAccountId,
      'status': status.name,
      if (lastSuccessfulSync != null) 'lastSuccessfulSync': Timestamp.fromDate(lastSuccessfulSync!),
      if (lastWebhookAt != null) 'lastWebhookAt': Timestamp.fromDate(lastWebhookAt!),
      if (lastApiSuccessAt != null) 'lastApiSuccessAt': Timestamp.fromDate(lastApiSuccessAt!),
      if (lastErrorAt != null) 'lastErrorAt': Timestamp.fromDate(lastErrorAt!),
      if (errorCode != null) 'errorCode': errorCode,
      'reauthenticationRequired': reauthenticationRequired,
      'capabilities': capabilities,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }
}
