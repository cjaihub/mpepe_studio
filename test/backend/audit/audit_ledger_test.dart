import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:oneova/backend/audit/models/audit_models.dart';
import 'package:oneova/backend/audit/audit_ledger_repository.dart';
import 'package:oneova/backend/audit/audit_ledger_service.dart';

void main() {
  group('Audit Ledger System Tests', () {
    late AuditLedgerRepository repository;
    late AuditLedgerService service;

    setUp(() {
      repository = InMemoryAuditLedgerRepository();
      service = AuditLedgerService(repository);
    });

    test('READ operation logs started and completed', () async {
      final correlationId = const Uuid().v4();
      
      await service.logStarted(
        actorId: 'user1',
        sessionId: 'session1',
        correlationId: correlationId,
        surface: 'inbox',
        toolId: 'search_inbox',
        operationType: OperationType.read,
        action: 'search',
        targetType: 'message',
        targetId: 'msg_1',
        authorizationState: AuthorizationState.authorized,
        confirmationState: ConfirmationState.notRequired,
      );

      var events = await repository.getByCorrelationId(correlationId);
      expect(events.length, 1);
      expect(events.first.executionState, ExecutionState.started);

      await service.logCompleted(
        correlationId: correlationId,
        targetId: 'msg_1',
        toolId: 'search_inbox',
        undoAvailable: false,
      );

      events = await repository.getByCorrelationId(correlationId);
      expect(events.length, 2);
      
      final completedEvent = events.firstWhere((e) => e.executionState == ExecutionState.completed);
      expect(completedEvent.success, isTrue);
      expect(completedEvent.parentEventId, events.firstWhere((e) => e.executionState == ExecutionState.started).id);
    });

    test('WRITE operation with cancellation', () async {
      final correlationId = const Uuid().v4();
      
      await service.logStarted(
        actorId: 'user1',
        sessionId: 'session1',
        correlationId: correlationId,
        surface: 'pro_editor',
        toolId: 'color.set_exposure',
        operationType: OperationType.write,
        action: 'set_exposure',
        targetType: 'clip',
        targetId: 'clip_1',
        authorizationState: AuthorizationState.authorized,
        confirmationState: ConfirmationState.pending,
      );

      await service.logCancelled(
        correlationId: correlationId,
        targetId: 'clip_1',
        toolId: 'color.set_exposure',
        failureCode: 'USER_CANCELLED',
      );

      final events = await repository.getByCorrelationId(correlationId);
      expect(events.length, 2);
      final cancelled = events.firstWhere((e) => e.executionState == ExecutionState.cancelled);
      expect(cancelled.success, isFalse);
      expect(cancelled.failureCode, 'USER_CANCELLED');
    });

    test('DESTRUCTIVE operation logs failure correctly', () async {
      final correlationId = const Uuid().v4();
      
      await service.logStarted(
        actorId: 'user1',
        sessionId: 'session1',
        correlationId: correlationId,
        surface: 'creator_studio',
        toolId: 'delete_effect',
        operationType: OperationType.destructive,
        action: 'delete',
        targetType: 'effect',
        targetId: 'eff_1',
        authorizationState: AuthorizationState.authorized,
        confirmationState: ConfirmationState.confirmed,
      );

      await service.logFailed(
        correlationId: correlationId,
        targetId: 'eff_1',
        toolId: 'delete_effect',
        failureCode: 'DATABASE_ERROR',
      );

      final events = await repository.getByCorrelationId(correlationId);
      expect(events.length, 2);
      final failed = events.firstWhere((e) => e.executionState == ExecutionState.failed);
      expect(failed.success, isFalse);
      expect(failed.failureCode, 'DATABASE_ERROR');
    });

    test('EXTERNAL_ACTION correctly redacts sensitive metadata', () async {
      final correlationId = const Uuid().v4();
      
      await service.logStarted(
        actorId: 'user1',
        sessionId: 'session1',
        correlationId: correlationId,
        surface: 'settings',
        toolId: 'connect_youtube',
        operationType: OperationType.externalAction,
        action: 'connect',
        targetType: 'integration',
        targetId: 'yt',
        authorizationState: AuthorizationState.authorized,
        confirmationState: ConfirmationState.notRequired,
      );

      await service.logCompleted(
        correlationId: correlationId,
        targetId: 'yt',
        toolId: 'connect_youtube',
        undoAvailable: false,
        metadata: {
          'oauthToken': 'super_secret_token_123',
          'channelName': 'My Channel',
          'apiKey': 'abc-123',
        },
      );

      final events = await repository.getByCorrelationId(correlationId);
      final completed = events.firstWhere((e) => e.executionState == ExecutionState.completed);
      
      expect(completed.metadata['oauthToken'], '[REDACTED]');
      expect(completed.metadata['apiKey'], '[REDACTED]');
      expect(completed.metadata['channelName'], 'My Channel');
    });
  });
}
