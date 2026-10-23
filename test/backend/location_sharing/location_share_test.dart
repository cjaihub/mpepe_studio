import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/maps/models/map_models.dart';
import 'package:oneova/backend/ai_agents/location_ai_models.dart';
import 'package:oneova/backend/location_sharing/models/location_share_models.dart';
import 'package:oneova/backend/location_sharing/services/location_share_service.dart';

void main() {
  late LocationShareService service;

  setUp(() {
    service = LocationShareService();
  });

  test('Server strictly enforces auto-expiration and revokes access', () async {
    final session = service.startSharing(
      senderId: 'user_1',
      recipientId: 'user_2',
      mode: LocationShareMode.temporaryLiveLocation,
      precision: LocationPrecision.precise,
      duration: const Duration(milliseconds: 100), // Expiration time is minimal
      initialLocation: const GeoLocation(latitude: 40.0, longitude: -74.0),
    );

    // Initial check - recipient has access
    var loc = service.getSharedLocation(session.id, 'user_2');
    expect(loc, isNotNull);

    // Wait for expiration
    await Future.delayed(const Duration(milliseconds: 150));

    // Secondary check - server must explicitly drop access and purge data
    loc = service.getSharedLocation(session.id, 'user_2');
    expect(loc, isNull);
    
    // Verify internal state mutation is correct
    expect(session.status, LocationShareStatus.expired);
    expect(session.lastKnownLocation, isNull);

    // Verify audit logs tracked the sequence exactly
    final auditEvents = session.auditLogs.map((l) => l.event).toList();
    expect(auditEvents.contains(LocationShareAuditEvent.started), true);
    expect(auditEvents.contains(LocationShareAuditEvent.expired), true);
  });

  test('Sender can manually pause and stop', () {
    final session = service.startSharing(
      senderId: 'user_1',
      recipientId: 'user_2',
      mode: LocationShareMode.journeyProgress,
      precision: LocationPrecision.precise,
      duration: const Duration(hours: 1),
      initialLocation: const GeoLocation(latitude: 40.0, longitude: -74.0),
    );

    // Pause
    bool paused = service.pauseSession(session.id, 'user_1');
    expect(paused, true);
    // Recipient loses access while paused
    expect(service.getSharedLocation(session.id, 'user_2'), isNull);

    // Stop
    bool stopped = service.stopSession(session.id, 'user_1');
    expect(stopped, true);
    expect(session.lastKnownLocation, isNull); // Data purged

    final auditEvents = session.auditLogs.map((l) => l.event).toList();
    expect(auditEvents, containsAllInOrder([
      LocationShareAuditEvent.started,
      LocationShareAuditEvent.paused,
      LocationShareAuditEvent.stopped,
    ]));
  });

  test('Update location fails after stop or expiration', () async {
    final session = service.startSharing(
      senderId: 'user_1',
      recipientId: 'user_2',
      mode: LocationShareMode.currentLocation,
      precision: LocationPrecision.approximate,
      duration: const Duration(milliseconds: 100),
    );

    service.stopSession(session.id, 'user_1');
    
    // Try to update after stop
    final updated = service.updateLocation(session.id, 'user_1', const GeoLocation(latitude: 1, longitude: 1));
    expect(updated, false);
  });
}
