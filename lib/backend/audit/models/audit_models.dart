import 'package:uuid/uuid.dart';

enum OperationType { read, write, destructive, externalAction }

enum AuthorizationState { authorized, denied, notRequired, unknown }

enum ConfirmationState { notRequired, pending, confirmed, rejected, expired }

enum ExecutionState { queued, started, completed, failed, cancelled, partiallyCompleted }

class AuditEvent {
  final String id;
  final DateTime timestamp;
  final String actorId;
  final String sessionId;
  final String correlationId;
  final String surface;
  final String toolId;
  final OperationType operationType;
  final String action;
  final String targetType;
  final String targetId;
  final AuthorizationState authorizationState;
  final ConfirmationState confirmationState;
  final ExecutionState executionState;
  final bool success;
  final String? failureCode;
  final bool undoAvailable;
  final String? parentEventId;
  final Map<String, dynamic> metadata;

  AuditEvent({
    String? id,
    DateTime? timestamp,
    required this.actorId,
    required this.sessionId,
    required this.correlationId,
    required this.surface,
    required this.toolId,
    required this.operationType,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.authorizationState,
    required this.confirmationState,
    required this.executionState,
    required this.success,
    this.failureCode,
    this.undoAvailable = false,
    this.parentEventId,
    this.metadata = const {},
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now().toUtc();

  AuditEvent copyWith({
    String? id,
    DateTime? timestamp,
    String? actorId,
    String? sessionId,
    String? correlationId,
    String? surface,
    String? toolId,
    OperationType? operationType,
    String? action,
    String? targetType,
    String? targetId,
    AuthorizationState? authorizationState,
    ConfirmationState? confirmationState,
    ExecutionState? executionState,
    bool? success,
    String? failureCode,
    bool? undoAvailable,
    String? parentEventId,
    Map<String, dynamic>? metadata,
  }) {
    return AuditEvent(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      actorId: actorId ?? this.actorId,
      sessionId: sessionId ?? this.sessionId,
      correlationId: correlationId ?? this.correlationId,
      surface: surface ?? this.surface,
      toolId: toolId ?? this.toolId,
      operationType: operationType ?? this.operationType,
      action: action ?? this.action,
      targetType: targetType ?? this.targetType,
      targetId: targetId ?? this.targetId,
      authorizationState: authorizationState ?? this.authorizationState,
      confirmationState: confirmationState ?? this.confirmationState,
      executionState: executionState ?? this.executionState,
      success: success ?? this.success,
      failureCode: failureCode ?? this.failureCode,
      undoAvailable: undoAvailable ?? this.undoAvailable,
      parentEventId: parentEventId ?? this.parentEventId,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'actorId': actorId,
        'sessionId': sessionId,
        'correlationId': correlationId,
        'surface': surface,
        'toolId': toolId,
        'operationType': operationType.name,
        'action': action,
        'targetType': targetType,
        'targetId': targetId,
        'authorizationState': authorizationState.name,
        'confirmationState': confirmationState.name,
        'executionState': executionState.name,
        'success': success,
        'failureCode': failureCode,
        'undoAvailable': undoAvailable,
        'parentEventId': parentEventId,
        'metadata': metadata,
      };

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
        id: json['id'],
        timestamp: DateTime.parse(json['timestamp']),
        actorId: json['actorId'],
        sessionId: json['sessionId'],
        correlationId: json['correlationId'],
        surface: json['surface'],
        toolId: json['toolId'],
        operationType: OperationType.values.firstWhere((e) => e.name == json['operationType'], orElse: () => OperationType.read),
        action: json['action'],
        targetType: json['targetType'],
        targetId: json['targetId'],
        authorizationState: AuthorizationState.values.firstWhere((e) => e.name == json['authorizationState'], orElse: () => AuthorizationState.unknown),
        confirmationState: ConfirmationState.values.firstWhere((e) => e.name == json['confirmationState'], orElse: () => ConfirmationState.notRequired),
        executionState: ExecutionState.values.firstWhere((e) => e.name == json['executionState'], orElse: () => ExecutionState.completed),
        success: json['success'],
        failureCode: json['failureCode'],
        undoAvailable: json['undoAvailable'],
        parentEventId: json['parentEventId'],
        metadata: json['metadata'] ?? {},
      );
}
