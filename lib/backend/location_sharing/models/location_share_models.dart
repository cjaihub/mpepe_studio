import 'package:oneova/backend/maps/models/map_models.dart';
import 'package:oneova/backend/ai_agents/location_ai_models.dart'; // For LocationPrecision

enum LocationShareMode {
  currentLocation,
  temporaryLiveLocation,
  journeyProgress,
  eta,
}

enum LocationShareStatus {
  active,
  paused,
  stopped,
  expired,
}

enum LocationShareAuditEvent {
  started,
  updated,
  paused,
  stopped,
  expired,
}

class LocationShareAuditLog {
  final LocationShareAuditEvent event;
  final DateTime timestamp;
  final String note;

  const LocationShareAuditLog({
    required this.event,
    required this.timestamp,
    this.note = '',
  });
}

class LocationShareSession {
  final String id;
  final String senderId;
  final String recipientId;
  final LocationShareMode mode;
  final LocationPrecision precision;
  final DateTime startTime;
  final DateTime expiresAt;
  
  LocationShareStatus status;
  GeoLocation? lastKnownLocation;
  DateTime? lastUpdatedAt;
  String? journeyDestinationPlaceId; // Only applicable for journeyProgress / eta
  List<LocationShareAuditLog> auditLogs;

  LocationShareSession({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.mode,
    required this.precision,
    required this.startTime,
    required this.expiresAt,
    this.status = LocationShareStatus.active,
    this.lastKnownLocation,
    this.lastUpdatedAt,
    this.journeyDestinationPlaceId,
    List<LocationShareAuditLog>? auditLogs,
  }) : auditLogs = auditLogs ?? [];

  /// Helper to enforce strict expiration checking locally
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
