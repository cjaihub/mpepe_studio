import 'package:cloud_firestore/cloud_firestore.dart';

class DeviceSession {
  final String sessionId;
  final String deviceName; // e.g., 'MacBook Pro'
  final String os; // e.g., 'macOS 14.5'
  final String ipAddress;
  final String location;
  final String userAgent;
  final bool isTrusted;
  final DateTime lastActiveAt;
  final DateTime createdAt;
  final bool isRevoked;

  DeviceSession({
    required this.sessionId,
    required this.deviceName,
    required this.os,
    required this.ipAddress,
    this.location = 'Unknown Location',
    required this.userAgent,
    this.isTrusted = false,
    required this.lastActiveAt,
    required this.createdAt,
    this.isRevoked = false,
  });

  factory DeviceSession.fromMap(Map<String, dynamic> map, String id) {
    return DeviceSession(
      sessionId: id,
      deviceName: map['deviceName'] ?? 'Unknown Device',
      os: map['os'] ?? 'Unknown OS',
      ipAddress: map['ipAddress'] ?? 'Unknown IP',
      location: map['location'] ?? 'Unknown Location',
      userAgent: map['userAgent'] ?? '',
      isTrusted: map['isTrusted'] ?? false,
      lastActiveAt: (map['lastActiveAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isRevoked: map['isRevoked'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'deviceName': deviceName,
      'os': os,
      'ipAddress': ipAddress,
      'location': location,
      'userAgent': userAgent,
      'isTrusted': isTrusted,
      'lastActiveAt': Timestamp.fromDate(lastActiveAt),
      'createdAt': Timestamp.fromDate(createdAt),
      'isRevoked': isRevoked,
    };
  }
}
