import 'package:cloud_firestore/cloud_firestore.dart';

enum ExecutionStatus {
  pending('pending'),
  running('running'),
  success('success'),
  failed('failed'),
  aborted('aborted');

  final String value;
  const ExecutionStatus(this.value);

  factory ExecutionStatus.fromString(String str) {
    return ExecutionStatus.values.firstWhere(
      (e) => e.value == str,
      orElse: () => ExecutionStatus.pending,
    );
  }
}

class WorkflowExecution {
  final String id;
  final String workflowId;
  final Map<String, dynamic> triggerPayload;
  final ExecutionStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String? error;
  final List<String> executedActions;

  WorkflowExecution({
    required this.id,
    required this.workflowId,
    required this.triggerPayload,
    required this.status,
    required this.startedAt,
    this.completedAt,
    this.error,
    this.executedActions = const [],
  });

  factory WorkflowExecution.fromMap(String id, Map<String, dynamic> map) {
    return WorkflowExecution(
      id: id,
      workflowId: map['workflowId'] as String? ?? '',
      triggerPayload: Map<String, dynamic>.from(map['triggerPayload'] ?? {}),
      status: ExecutionStatus.fromString(map['status'] as String? ?? ''),
      startedAt: (map['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedAt: (map['completedAt'] as Timestamp?)?.toDate(),
      error: map['error'] as String?,
      executedActions: List<String>.from(map['executedActions'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'workflowId': workflowId,
      'triggerPayload': triggerPayload,
      'status': status.value,
      'startedAt': Timestamp.fromDate(startedAt),
      if (completedAt != null) 'completedAt': Timestamp.fromDate(completedAt!),
      if (error != null) 'error': error,
      'executedActions': executedActions,
    };
  }

  WorkflowExecution copyWith({
    String? id,
    String? workflowId,
    Map<String, dynamic>? triggerPayload,
    ExecutionStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    String? error,
    List<String>? executedActions,
  }) {
    return WorkflowExecution(
      id: id ?? this.id,
      workflowId: workflowId ?? this.workflowId,
      triggerPayload: triggerPayload ?? this.triggerPayload,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      error: error ?? this.error,
      executedActions: executedActions ?? this.executedActions,
    );
  }
}
