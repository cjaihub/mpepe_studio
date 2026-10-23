import 'package:cloud_firestore/cloud_firestore.dart';

enum WorkflowTriggerType {
  newMessage('new_message'),
  keyword('keyword'),
  reaction('reaction'),
  newFollower('new_follower'),
  newContact('new_contact'),
  formSubmission('form_submission'),
  scheduledTime('scheduled_time'),
  webhook('webhook'),
  channelEvent('channel_event'),
  aiClassification('ai_classification');

  final String value;
  const WorkflowTriggerType(this.value);

  factory WorkflowTriggerType.fromString(String str) {
    return WorkflowTriggerType.values.firstWhere(
      (e) => e.value == str,
      orElse: () => WorkflowTriggerType.newMessage,
    );
  }
}

enum WorkflowActionType {
  sendMessage('send_message'),
  createDraft('create_draft'),
  assignConversation('assign_conversation'),
  addLabel('add_label'),
  createTask('create_task'),
  scheduleMessage('schedule_message'),
  notifyTeam('notify_team'),
  callAi('call_ai'),
  escalate('escalate'),
  updateContact('update_contact'),
  createCalendarEvent('create_calendar_event');

  final String value;
  const WorkflowActionType(this.value);

  factory WorkflowActionType.fromString(String str) {
    return WorkflowActionType.values.firstWhere(
      (e) => e.value == str,
      orElse: () => WorkflowActionType.sendMessage,
    );
  }
}

enum WorkflowOperator {
  equals('equals'),
  notEquals('not_equals'),
  contains('contains'),
  greaterThan('greater_than'),
  lessThan('less_than'),
  exists('exists');

  final String value;
  const WorkflowOperator(this.value);

  factory WorkflowOperator.fromString(String str) {
    return WorkflowOperator.values.firstWhere(
      (e) => e.value == str,
      orElse: () => WorkflowOperator.equals,
    );
  }
}

class WorkflowCondition {
  final String field;
  final WorkflowOperator operator;
  final dynamic value;

  WorkflowCondition({
    required this.field,
    required this.operator,
    required this.value,
  });

  factory WorkflowCondition.fromMap(Map<String, dynamic> map) {
    return WorkflowCondition(
      field: map['field'] as String? ?? '',
      operator: WorkflowOperator.fromString(map['operator'] as String? ?? ''),
      value: map['value'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'field': field,
      'operator': operator.value,
      'value': value,
    };
  }
}

class WorkflowAction {
  final String id;
  final WorkflowActionType type;
  final Map<String, dynamic> payload;
  final int? delaySeconds;

  WorkflowAction({
    required this.id,
    required this.type,
    required this.payload,
    this.delaySeconds,
  });

  factory WorkflowAction.fromMap(Map<String, dynamic> map) {
    return WorkflowAction(
      id: map['id'] as String? ?? '',
      type: WorkflowActionType.fromString(map['type'] as String? ?? ''),
      payload: Map<String, dynamic>.from(map['payload'] ?? {}),
      delaySeconds: map['delaySeconds'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.value,
      'payload': payload,
      if (delaySeconds != null) 'delaySeconds': delaySeconds,
    };
  }
}

class WorkflowTrigger {
  final WorkflowTriggerType type;
  final Map<String, dynamic> config;

  WorkflowTrigger({
    required this.type,
    required this.config,
  });

  factory WorkflowTrigger.fromMap(Map<String, dynamic> map) {
    return WorkflowTrigger(
      type: WorkflowTriggerType.fromString(map['type'] as String? ?? ''),
      config: Map<String, dynamic>.from(map['config'] ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type.value,
      'config': config,
    };
  }
}

class RetryPolicy {
  final int maxRetries;
  final String backoffType;

  RetryPolicy({
    this.maxRetries = 0,
    this.backoffType = 'linear',
  });

  factory RetryPolicy.fromMap(Map<String, dynamic> map) {
    return RetryPolicy(
      maxRetries: map['maxRetries'] as int? ?? 0,
      backoffType: map['backoffType'] as String? ?? 'linear',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'maxRetries': maxRetries,
      'backoffType': backoffType,
    };
  }
}

class WorkflowConfig {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final int version;
  final String ownerId;
  final WorkflowTrigger trigger;
  final List<WorkflowCondition> conditions;
  final List<WorkflowAction> actions;
  final RetryPolicy retryPolicy;
  final int rateLimitPerMinute;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  WorkflowConfig({
    required this.id,
    required this.name,
    this.description = '',
    this.enabled = true,
    this.version = 1,
    required this.ownerId,
    required this.trigger,
    this.conditions = const [],
    this.actions = const [],
    RetryPolicy? retryPolicy,
    this.rateLimitPerMinute = 10,
    this.createdAt,
    this.updatedAt,
  }) : retryPolicy = retryPolicy ?? RetryPolicy();

  factory WorkflowConfig.fromMap(String id, Map<String, dynamic> map) {
    return WorkflowConfig(
      id: id,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      enabled: map['enabled'] as bool? ?? false,
      version: map['version'] as int? ?? 1,
      ownerId: map['ownerId'] as String? ?? '',
      trigger: WorkflowTrigger.fromMap(Map<String, dynamic>.from(map['trigger'] ?? {})),
      conditions: (map['conditions'] as List<dynamic>?)
              ?.map((e) => WorkflowCondition.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      actions: (map['actions'] as List<dynamic>?)
              ?.map((e) => WorkflowAction.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      retryPolicy: RetryPolicy.fromMap(Map<String, dynamic>.from(map['retryPolicy'] ?? {})),
      rateLimitPerMinute: map['rateLimitPerMinute'] as int? ?? 10,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'enabled': enabled,
      'version': version,
      'ownerId': ownerId,
      'trigger': trigger.toMap(),
      'conditions': conditions.map((e) => e.toMap()).toList(),
      'actions': actions.map((e) => e.toMap()).toList(),
      'retryPolicy': retryPolicy.toMap(),
      'rateLimitPerMinute': rateLimitPerMinute,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  WorkflowConfig copyWith({
    String? id,
    String? name,
    String? description,
    bool? enabled,
    int? version,
    String? ownerId,
    WorkflowTrigger? trigger,
    List<WorkflowCondition>? conditions,
    List<WorkflowAction>? actions,
    RetryPolicy? retryPolicy,
    int? rateLimitPerMinute,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WorkflowConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      version: version ?? this.version,
      ownerId: ownerId ?? this.ownerId,
      trigger: trigger ?? this.trigger,
      conditions: conditions ?? this.conditions,
      actions: actions ?? this.actions,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      rateLimitPerMinute: rateLimitPerMinute ?? this.rateLimitPerMinute,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
