import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/audit_models.dart';
import 'audit_ledger_repository.dart';

class AuditLedgerService {
  final AuditLedgerRepository _repository;

  AuditLedgerService(this._repository);

  Future<void> logStarted({
    required String actorId,
    required String sessionId,
    required String correlationId,
    required String surface,
    required String toolId,
    required OperationType operationType,
    required String action,
    required String targetType,
    required String targetId,
    required AuthorizationState authorizationState,
    required ConfirmationState confirmationState,
    String? parentEventId,
  }) async {
    final event = AuditEvent(
      actorId: actorId,
      sessionId: sessionId,
      correlationId: correlationId,
      surface: surface,
      toolId: toolId,
      operationType: operationType,
      action: action,
      targetType: targetType,
      targetId: targetId,
      authorizationState: authorizationState,
      confirmationState: confirmationState,
      executionState: ExecutionState.started,
      success: false,
      parentEventId: parentEventId,
    );
    await _repository.saveEvent(event);
  }

  Future<void> logCompleted({
    required String correlationId,
    required String targetId,
    required String toolId,
    required bool undoAvailable,
    Map<String, dynamic> metadata = const {},
  }) async {
    final events = await _repository.getByCorrelationId(correlationId);
    final startedEvents = events.where(
      (e) => e.targetId == targetId && e.toolId == toolId && e.executionState == ExecutionState.started
    ).toList();
    
    // Fallback if not found properly, though it should exist if we control the flow
    if (startedEvents.isEmpty) {
      throw Exception('Started event not found for completion ($toolId on $targetId)');
    }
    
    // Just pick the latest started event
    startedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final startedEvent = startedEvents.first;

    final completedEvent = AuditEvent(
      actorId: startedEvent.actorId,
      sessionId: startedEvent.sessionId,
      correlationId: startedEvent.correlationId,
      surface: startedEvent.surface,
      toolId: startedEvent.toolId,
      operationType: startedEvent.operationType,
      action: startedEvent.action,
      targetType: startedEvent.targetType,
      targetId: startedEvent.targetId,
      authorizationState: startedEvent.authorizationState,
      confirmationState: startedEvent.confirmationState,
      executionState: ExecutionState.completed,
      success: true,
      undoAvailable: undoAvailable,
      metadata: _redactMetadata(metadata),
      parentEventId: startedEvent.id, // Reference previous
    );

    await _repository.saveEvent(completedEvent);
  }

  Future<void> logFailed({
    required String correlationId,
    required String targetId,
    required String toolId,
    required String failureCode,
    Map<String, dynamic> metadata = const {},
  }) async {
    final events = await _repository.getByCorrelationId(correlationId);
    final startedEvents = events.where(
      (e) => e.targetId == targetId && e.toolId == toolId && e.executionState == ExecutionState.started
    ).toList();
    
    if (startedEvents.isEmpty) {
      throw Exception('Started event not found for failure ($toolId on $targetId)');
    }
    
    startedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final startedEvent = startedEvents.first;

    final failedEvent = AuditEvent(
      actorId: startedEvent.actorId,
      sessionId: startedEvent.sessionId,
      correlationId: startedEvent.correlationId,
      surface: startedEvent.surface,
      toolId: startedEvent.toolId,
      operationType: startedEvent.operationType,
      action: startedEvent.action,
      targetType: startedEvent.targetType,
      targetId: startedEvent.targetId,
      authorizationState: startedEvent.authorizationState,
      confirmationState: startedEvent.confirmationState,
      executionState: ExecutionState.failed,
      success: false,
      failureCode: failureCode,
      metadata: _redactMetadata(metadata),
      parentEventId: startedEvent.id,
    );

    await _repository.saveEvent(failedEvent);
  }

  Future<void> logCancelled({
    required String correlationId,
    required String targetId,
    required String toolId,
    required String failureCode,
  }) async {
    final events = await _repository.getByCorrelationId(correlationId);
    final startedEvents = events.where(
      (e) => e.targetId == targetId && e.toolId == toolId && e.executionState == ExecutionState.started
    ).toList();
    
    if (startedEvents.isEmpty) {
      // It might have been cancelled before even starting, e.g. awaiting confirmation.
      // But typically we log cancelled after started. Or we might want to log a completely new event.
      // Let's assume it has started.
      return;
    }
    
    startedEvents.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final startedEvent = startedEvents.first;

    final cancelledEvent = AuditEvent(
      actorId: startedEvent.actorId,
      sessionId: startedEvent.sessionId,
      correlationId: startedEvent.correlationId,
      surface: startedEvent.surface,
      toolId: startedEvent.toolId,
      operationType: startedEvent.operationType,
      action: startedEvent.action,
      targetType: startedEvent.targetType,
      targetId: startedEvent.targetId,
      authorizationState: startedEvent.authorizationState,
      confirmationState: startedEvent.confirmationState,
      executionState: ExecutionState.cancelled,
      success: false,
      failureCode: failureCode,
      parentEventId: startedEvent.id,
    );

    await _repository.saveEvent(cancelledEvent);
  }

  Map<String, dynamic> _redactMetadata(Map<String, dynamic> original) {
    // Redact sensitive data
    final result = Map<String, dynamic>.from(original);
    for (final key in result.keys) {
      final lower = key.toLowerCase();
      if (lower.contains('password') || 
          lower.contains('token') || 
          lower.contains('key') || 
          lower.contains('secret') ||
          lower.contains('credential') ||
          lower.contains('pixels')) {
        result[key] = '[REDACTED]';
      }
    }
    return result;
  }
}

final auditLedgerServiceProvider = Provider<AuditLedgerService>((ref) {
  return AuditLedgerService(ref.watch(auditLedgerRepositoryProvider));
});
