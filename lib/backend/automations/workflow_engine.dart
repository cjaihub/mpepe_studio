import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/workflow_models.dart';

final workflowEngineProvider = Provider((ref) => WorkflowEngine());

class WorkflowEngine {
  // Simulates in-memory database of registered workflows
  final List<WorkflowDefinition> _activeWorkflows = [];
  
  // Execution history tracking (in production, this goes to Firestore/DB)
  final List<WorkflowExecutionLog> _executionHistory = [];
  
  // Idempotency Locks (Key: idempotency_key, Value: timestamp)
  // Ensures exactly-once execution for identical triggers in a tight window
  final Map<String, DateTime> _idempotencyLocks = {};

  // Rate Limiting (Key: workflowId, Value: list of execution timestamps)
  final Map<String, List<DateTime>> _rateLimits = {};

  List<WorkflowExecutionLog> get executionHistory => List.unmodifiable(_executionHistory);
  List<WorkflowExecutionLog> get failureHistory => _executionHistory.where((l) => l.status == ExecutionStatus.failed).toList();
  List<WorkflowExecutionLog> get activeTasks => _executionHistory.where((l) => l.status == ExecutionStatus.running).toList();

  void registerWorkflow(WorkflowDefinition workflow) {
    _activeWorkflows.add(workflow);
  }

  /// Entry point for all system events to trigger automations.
  /// [idempotencyKey] prevents identical events from firing multiple times.
  /// [executionDepth] tracks automation chaining to prevent infinite loops.
  Future<void> processEvent({
    required WorkflowTriggerType type,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
    int executionDepth = 0,
  }) async {
    // 1. Idempotency Check
    if (_idempotencyLocks.containsKey(idempotencyKey)) {
      final lockTime = _idempotencyLocks[idempotencyKey]!;
      // Simple TTL of 1 hour for idempotency locks
      if (DateTime.now().difference(lockTime).inHours < 1) {
        debugPrint("Workflow Engine: Idempotency lock active for $idempotencyKey. Ignoring.");
        return;
      }
    }
    _idempotencyLocks[idempotencyKey] = DateTime.now();

    // 2. Find matching workflows
    final matchingWorkflows = _activeWorkflows.where((w) {
      if (!w.isEnabled) return false;
      if (w.triggerType != type) return false;
      if (executionDepth >= w.maxExecutionDepth) return false;
      return _evaluateConditions(payload, w.conditions);
    }).toList();

    for (final workflow in matchingWorkflows) {
      await _executeWorkflow(
        workflow: workflow, 
        payload: payload, 
        executionDepth: executionDepth,
      );
    }
  }

  Future<void> _executeWorkflow({
    required WorkflowDefinition workflow,
    required Map<String, dynamic> payload,
    required int executionDepth,
  }) async {
    final executionId = '${workflow.id}_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Loop Detection
    if (workflow.preventSelfTrigger && payload['isAutomated'] == true) {
      _logExecution(executionId, workflow.id, ExecutionStatus.loopDetected, payload);
      return;
    }

    // 2. Rate Limiting Check
    if (!_checkRateLimit(workflow.id, workflow.rateLimit)) {
      _logExecution(executionId, workflow.id, ExecutionStatus.rateLimited, payload);
      return;
    }

    _logExecution(executionId, workflow.id, ExecutionStatus.running, payload);

    // 3. Execution Pipeline (with Retry Policy)
    try {
      await _executeActionsWithRetry(
        actions: workflow.actions,
        payload: payload,
        retryPolicy: workflow.retryPolicy,
        executionDepth: executionDepth,
      );
      _updateExecutionStatus(executionId, ExecutionStatus.completed, null);
    } catch (e) {
      _updateExecutionStatus(executionId, ExecutionStatus.failed, e.toString());
    }
  }

  Future<void> _executeActionsWithRetry({
    required List<WorkflowAction> actions,
    required Map<String, dynamic> payload,
    required WorkflowRetryPolicy retryPolicy,
    required int executionDepth,
  }) async {
    for (final action in actions) {
      int attempts = 0;
      bool success = false;
      Duration backoff = retryPolicy.initialBackoff;

      while (attempts < retryPolicy.maxRetries && !success) {
        try {
          attempts++;
          
          if (action.delayBeforeExecution != null) {
            await Future.delayed(action.delayBeforeExecution!);
          }
          
          await _performAction(action, payload, executionDepth);
          success = true;
          
        } catch (e) {
          if (attempts >= retryPolicy.maxRetries) {
            rethrow;
          }
          debugPrint("Action failed. Retrying in $backoff...");
          await Future.delayed(backoff);
          backoff = Duration(milliseconds: (backoff.inMilliseconds * retryPolicy.backoffMultiplier).toInt());
        }
      }
    }
  }

  Future<void> _performAction(WorkflowAction action, Map<String, dynamic> triggerPayload, int currentDepth) async {
    // In production, map WorkflowActionType to actual business logic / services.
    debugPrint("Executing Action [${action.type.name}] with payload: ${action.payload}");
    
    // Simulate API/Network call
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Example: If the action is sending a message, it might trigger another event.
    // We append `isAutomated: true` to prevent self-triggering loops.
    if (action.type == WorkflowActionType.sendMessage) {
      // processEvent(
      //   type: WorkflowTriggerType.newMessage,
      //   payload: {'isAutomated': true, ...action.payload},
      //   idempotencyKey: 'nested_${DateTime.now().millisecondsSinceEpoch}',
      //   executionDepth: currentDepth + 1,
      // );
    }
  }

  bool _evaluateConditions(Map<String, dynamic> payload, List<WorkflowCondition> conditions) {
    for (final condition in conditions) {
      final actualValue = payload[condition.field];
      if (actualValue == null) return false;

      switch (condition.operator) {
        case '==':
          if (actualValue != condition.value) return false;
          break;
        case '!=':
          if (actualValue == condition.value) return false;
          break;
        case 'contains':
          if (actualValue is String && !(actualValue).contains(condition.value)) return false;
          if (actualValue is List && !(actualValue).contains(condition.value)) return false;
          break;
        case '>':
          if (actualValue is num && condition.value is num && !(actualValue > condition.value)) return false;
          break;
        // ... additional operators
      }
    }
    return true;
  }

  bool _checkRateLimit(String workflowId, WorkflowRateLimit rateLimit) {
    final now = DateTime.now();
    _rateLimits.putIfAbsent(workflowId, () => []);
    
    // Clean up old timestamps outside the window
    _rateLimits[workflowId]!.removeWhere((timestamp) => now.difference(timestamp) > rateLimit.window);
    
    if (_rateLimits[workflowId]!.length >= rateLimit.maxExecutions) {
      return false; // Rate limit exceeded
    }
    
    _rateLimits[workflowId]!.add(now);
    return true;
  }

  void _logExecution(String execId, String workflowId, ExecutionStatus status, Map<String, dynamic> payload) {
    _executionHistory.add(WorkflowExecutionLog(
      executionId: execId,
      workflowId: workflowId,
      startedAt: DateTime.now(),
      status: status,
      triggerPayload: payload,
    ));
  }

  void _updateExecutionStatus(String execId, ExecutionStatus status, String? error) {
    final index = _executionHistory.indexWhere((l) => l.executionId == execId);
    if (index != -1) {
      final old = _executionHistory[index];
      _executionHistory[index] = WorkflowExecutionLog(
        executionId: old.executionId,
        workflowId: old.workflowId,
        startedAt: old.startedAt,
        completedAt: DateTime.now(),
        status: status,
        errorMessage: error,
        triggerPayload: old.triggerPayload,
      );
    }
  }
}
