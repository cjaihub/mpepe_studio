import 'package:oneova/backend/maps/models/map_models.dart';
import 'package:oneova/backend/ai_agents/location_ai_models.dart';
import 'package:oneova/backend/location_sharing/models/location_share_models.dart';

class LocationShareService {
  // In-memory stub representing the strict backend server database
  final Map<String, LocationShareSession> _sessions = {};

  /// Initiates a new secure location sharing session.
  LocationShareSession startSharing({
    required String senderId,
    required String recipientId,
    required LocationShareMode mode,
    required LocationPrecision precision,
    required Duration duration,
    String? journeyDestinationPlaceId,
    GeoLocation? initialLocation,
  }) {
    final now = DateTime.now();
    final session = LocationShareSession(
      id: 'ls_\${now.millisecondsSinceEpoch}',
      senderId: senderId,
      recipientId: recipientId,
      mode: mode,
      precision: precision,
      startTime: now,
      expiresAt: now.add(duration),
      lastKnownLocation: initialLocation,
      lastUpdatedAt: initialLocation != null ? now : null,
      journeyDestinationPlaceId: journeyDestinationPlaceId,
    );

    _addAudit(session, LocationShareAuditEvent.started, 'Session initiated by \$senderId');
    _sessions[session.id] = session;
    return session;
  }

  /// Updates the location. Must validate session status and expiration first.
  bool updateLocation(String sessionId, String senderId, GeoLocation newLocation) {
    final session = _sessions[sessionId];
    if (session == null || session.senderId != senderId) return false;
    
    if (_enforceExpiration(session)) return false; // Rejected if expired
    if (session.status != LocationShareStatus.active) return false;

    session.lastKnownLocation = newLocation;
    session.lastUpdatedAt = DateTime.now();
    _addAudit(session, LocationShareAuditEvent.updated, 'Location updated');
    return true;
  }

  /// Pauses the active session. Sender action only.
  bool pauseSession(String sessionId, String senderId) {
    final session = _sessions[sessionId];
    if (session == null || session.senderId != senderId) return false;

    if (_enforceExpiration(session)) return false;

    session.status = LocationShareStatus.paused;
    _addAudit(session, LocationShareAuditEvent.paused, 'Paused by sender');
    return true;
  }

  /// Stops the session permanently before expiration. Sender action only.
  bool stopSession(String sessionId, String senderId) {
    final session = _sessions[sessionId];
    if (session == null || session.senderId != senderId) return false;

    session.status = LocationShareStatus.stopped;
    // We clear location data strictly upon stopping
    session.lastKnownLocation = null; 
    _addAudit(session, LocationShareAuditEvent.stopped, 'Manually stopped by sender');
    return true;
  }

  /// Secure retrieval for the recipient. Server MUST enforce expiration here.
  GeoLocation? getSharedLocation(String sessionId, String requestorId) {
    final session = _sessions[sessionId];
    
    // Auth Check
    if (session == null || session.recipientId != requestorId) {
      return null;
    }

    // Strict Expiration Enforcement before releasing data
    if (_enforceExpiration(session)) {
      return null;
    }

    // Status Enforcement
    if (session.status != LocationShareStatus.active) {
      return null;
    }

    return session.lastKnownLocation;
  }

  /// Server-side helper to securely evaluate and transition expiration state
  bool _enforceExpiration(LocationShareSession session) {
    if (session.status == LocationShareStatus.expired) return true;
    if (session.status == LocationShareStatus.stopped) return true;

    if (session.isExpired) {
      session.status = LocationShareStatus.expired;
      session.lastKnownLocation = null; // Purge location data locally immediately
      _addAudit(session, LocationShareAuditEvent.expired, 'Session auto-expired');
      return true;
    }
    return false;
  }

  void _addAudit(LocationShareSession session, LocationShareAuditEvent event, String note) {
    session.auditLogs.add(LocationShareAuditLog(
      event: event,
      timestamp: DateTime.now(),
      note: note,
    ));
  }

  // Helper for tests
  LocationShareSession? getSessionInternal(String sessionId) => _sessions[sessionId];
}
