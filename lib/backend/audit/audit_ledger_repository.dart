import 'models/audit_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class AuditLedgerRepository {
  Future<void> saveEvent(AuditEvent event);
  Future<AuditEvent?> getEvent(String id);
  Future<List<AuditEvent>> queryEvents({String? actorId, String? correlationId});
  Future<List<AuditEvent>> getByCorrelationId(String correlationId);
  Future<List<AuditEvent>> getRelatedEvents(String parentEventId);
}

class InMemoryAuditLedgerRepository implements AuditLedgerRepository {
  final Map<String, AuditEvent> _events = {};

  @override
  Future<void> saveEvent(AuditEvent event) async {
    _events[event.id] = event;
  }

  @override
  Future<AuditEvent?> getEvent(String id) async {
    return _events[id];
  }

  @override
  Future<List<AuditEvent>> queryEvents({String? actorId, String? correlationId}) async {
    return _events.values.where((e) {
      if (actorId != null && e.actorId != actorId) return false;
      if (correlationId != null && e.correlationId != correlationId) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<AuditEvent>> getByCorrelationId(String correlationId) async {
    return _events.values.where((e) => e.correlationId == correlationId).toList();
  }

  @override
  Future<List<AuditEvent>> getRelatedEvents(String parentEventId) async {
    return _events.values.where((e) => e.parentEventId == parentEventId).toList();
  }
}

final auditLedgerRepositoryProvider = Provider<AuditLedgerRepository>((ref) {
  return InMemoryAuditLedgerRepository(); // Swap with real implementation when needed
});
