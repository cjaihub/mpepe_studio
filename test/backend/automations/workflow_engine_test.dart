import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/automations/models/workflow_models.dart';
import 'package:oneova/backend/automations/workflow_engine.dart';

void main() {
  group('WorkflowEngine Security and Logic Tests', () {
    late WorkflowEngine engine;

    setUp(() {
      engine = WorkflowEngine();
    });

    test('Engine strictly prevents execution of disabled workflows', () async {
      final workflow = WorkflowDefinition(
        id: 'wf_1',
        name: 'Test Workflow',
        isEnabled: false,
        ownerId: 'user123',
        triggerType: WorkflowTriggerType.newMessage,
      );

      engine.registerWorkflow(workflow);
      await engine.processEvent(
        type: WorkflowTriggerType.newMessage,
        payload: {'text': 'hello'},
        idempotencyKey: 'test_key_1',
      );

      expect(engine.executionHistory.isEmpty, isTrue, reason: 'Disabled workflow should not execute');
    });

    test('Engine prevents infinite loops via preventSelfTrigger', () async {
      final workflow = WorkflowDefinition(
        id: 'wf_loop',
        name: 'Looping Workflow',
        isEnabled: true,
        ownerId: 'user123',
        triggerType: WorkflowTriggerType.newMessage,
        preventSelfTrigger: true,
        actions: [
          WorkflowAction(id: 'action1', type: WorkflowActionType.sendMessage),
        ]
      );

      engine.registerWorkflow(workflow);
      
      // Simulating an event triggered by an automated reply
      await engine.processEvent(
        type: WorkflowTriggerType.newMessage,
        payload: {'isAutomated': true},
        idempotencyKey: 'test_key_loop_1',
      );

      expect(engine.executionHistory.length, equals(1));
      expect(engine.executionHistory.first.status, equals(ExecutionStatus.loopDetected));
    });

    test('Engine enforces rate limits over sliding window', () async {
      final workflow = WorkflowDefinition(
        id: 'wf_rate_limit',
        name: 'Rate Limited Workflow',
        isEnabled: true,
        ownerId: 'user123',
        triggerType: WorkflowTriggerType.newMessage,
        rateLimit: WorkflowRateLimit(maxExecutions: 2, window: Duration(seconds: 1)),
      );

      engine.registerWorkflow(workflow);

      // Attempt 1 (Should Pass)
      await engine.processEvent(type: WorkflowTriggerType.newMessage, payload: {}, idempotencyKey: 'rate_1');
      // Attempt 2 (Should Pass)
      await engine.processEvent(type: WorkflowTriggerType.newMessage, payload: {}, idempotencyKey: 'rate_2');
      // Attempt 3 (Should Fail due to Rate Limit)
      await engine.processEvent(type: WorkflowTriggerType.newMessage, payload: {}, idempotencyKey: 'rate_3');

      final passedExecutions = engine.executionHistory.where((l) => l.status == ExecutionStatus.completed).toList();
      final blockedExecutions = engine.executionHistory.where((l) => l.status == ExecutionStatus.rateLimited).toList();

      expect(passedExecutions.length, equals(2));
      expect(blockedExecutions.length, equals(1));
    });

    test('Engine enforces idempotency locks for duplicate concurrent triggers', () async {
      final workflow = WorkflowDefinition(
        id: 'wf_idempotent',
        name: 'Idempotent Workflow',
        isEnabled: true,
        ownerId: 'user123',
        triggerType: WorkflowTriggerType.webhook,
      );

      engine.registerWorkflow(workflow);

      // Fire twice with the exact same idempotency key
      await engine.processEvent(type: WorkflowTriggerType.webhook, payload: {}, idempotencyKey: 'webhook_xyz');
      await engine.processEvent(type: WorkflowTriggerType.webhook, payload: {}, idempotencyKey: 'webhook_xyz');

      // The engine should only log one execution attempt because the second was dropped at the gateway
      expect(engine.executionHistory.length, equals(1));
    });
  });
}
