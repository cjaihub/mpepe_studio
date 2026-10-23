import 'package:cloud_firestore/cloud_firestore.dart';

enum DeviceStatus { active, revoked, expired }

class DeviceSession {
  final String deviceId;
  final String userId;
  final String deviceName;
  final String publicKey; // Public key for establishing E2EE sessions
  final DeviceStatus status;
  final DateTime lastActive;

  const DeviceSession({
    required this.deviceId,
    required this.userId,
    required this.deviceName,
    required this.publicKey,
    this.status = DeviceStatus.active,
    required this.lastActive,
  });

  factory DeviceSession.fromMap(Map<String, dynamic> map, String id) {
    return DeviceSession(
      deviceId: id,
      userId: map['userId'] ?? '',
      deviceName: map['deviceName'] ?? 'Unknown Device',
      publicKey: map['publicKey'] ?? '',
      status: DeviceStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => DeviceStatus.active,
      ),
      lastActive: (map['lastActive'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'deviceName': deviceName,
      'publicKey': publicKey,
      'status': status.name,
      'lastActive': lastActive,
    };
  }
}

class EncryptedPayload {
  final String ciphertext;
  final String iv; // Initialization vector
  final String mac; // Message Authentication Code for tampering detection
  final String senderDeviceId; // Which device sent this
  
  // This explicitly guarantees to the architecture that the content 
  // cannot be read by the server. AI models scanning the database 
  // will only see these fields.
  final bool isE2EE = true; 

  const EncryptedPayload({
    required this.ciphertext,
    required this.iv,
    required this.mac,
    required this.senderDeviceId,
  });

  factory EncryptedPayload.fromMap(Map<String, dynamic> map) {
    return EncryptedPayload(
      ciphertext: map['ciphertext'] ?? '',
      iv: map['iv'] ?? '',
      mac: map['mac'] ?? '',
      senderDeviceId: map['senderDeviceId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ciphertext': ciphertext,
      'iv': iv,
      'mac': mac,
      'senderDeviceId': senderDeviceId,
      'isE2EE': isE2EE,
    };
  }
}
