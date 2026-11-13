import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';

enum OvaWorkspaceViewMode {
  agentChat,
  wisprStudio,
  inputDeck;

  String get label => switch (this) {
        OvaWorkspaceViewMode.agentChat => 'Agentic',
        OvaWorkspaceViewMode.wisprStudio => 'Wispr Flow',
        OvaWorkspaceViewMode.inputDeck => 'Input Deck',
      };

  IconData get icon => switch (this) {
        OvaWorkspaceViewMode.agentChat => Icons.auto_awesome_rounded,
        OvaWorkspaceViewMode.wisprStudio => Icons.graphic_eq_rounded,
        OvaWorkspaceViewMode.inputDeck => Icons.mouse_rounded,
      };
}

enum OvaWisprTarget {
  composer,
  autoSendAgent,
  macCursor;

  String get label => switch (this) {
        OvaWisprTarget.composer => 'To Composer',
        OvaWisprTarget.autoSendAgent => 'Voice → Agent',
        OvaWisprTarget.macCursor => 'Wispr → Mac Cursor',
      };

  String get shortLabel => switch (this) {
        OvaWisprTarget.composer => 'Composer',
        OvaWisprTarget.autoSendAgent => 'Auto-Send',
        OvaWisprTarget.macCursor => 'Mac Cursor',
      };

  IconData get icon => switch (this) {
        OvaWisprTarget.composer => Icons.edit_note_rounded,
        OvaWisprTarget.autoSendAgent => Icons.bolt_rounded,
        OvaWisprTarget.macCursor => Icons.desktop_mac_rounded,
      };
}

class OvaLiveActionEvent {
  final String id;
  final String category; // 'mouse' | 'keyboard' | 'wispr' | 'agent' | 'system'
  final String summary;
  final String origin; // 'mobile' | 'mac'
  final DateTime timestamp;

  const OvaLiveActionEvent({
    required this.id,
    required this.category,
    required this.summary,
    required this.origin,
    required this.timestamp,
  });

  IconData get icon => switch (category) {
        'mouse' => Icons.mouse_rounded,
        'keyboard' => Icons.keyboard_rounded,
        'wispr' => Icons.graphic_eq_rounded,
        'agent' => Icons.auto_awesome_rounded,
        _ => Icons.bolt_rounded,
      };
}

enum OvaAgentMode {
  orchestrator,
  computerUse,
  codeTerminal,
  studioNle,
  creatorOps,
  research;

  String get wireValue => switch (this) {
        OvaAgentMode.orchestrator => 'orchestrator',
        OvaAgentMode.computerUse => 'computer_use',
        OvaAgentMode.codeTerminal => 'code_terminal',
        OvaAgentMode.studioNle => 'studio_nle',
        OvaAgentMode.creatorOps => 'creator_ops',
        OvaAgentMode.research => 'research',
      };

  String get label => switch (this) {
        OvaAgentMode.orchestrator => 'Auto Agent',
        OvaAgentMode.computerUse => 'Computer Use',
        OvaAgentMode.codeTerminal => 'Code & Shell',
        OvaAgentMode.studioNle => 'Studio NLE',
        OvaAgentMode.creatorOps => 'Creator Ops',
        OvaAgentMode.research => 'Deep Research',
      };

  String get subtitle => switch (this) {
        OvaAgentMode.orchestrator => 'Autonomous multi-agent & live workstation sync',
        OvaAgentMode.computerUse => 'Full mouse, keyboard, AppleScript, apps & windows',
        OvaAgentMode.codeTerminal => 'Workspace files, zsh commands & code artifacts',
        OvaAgentMode.studioNle => 'Timeline macros, NLE WebSocket & export workflows',
        OvaAgentMode.creatorOps => 'Reels retention hooks, scripts & creator growth',
        OvaAgentMode.research => 'Structured plans, specs & deep synthesis',
      };

  IconData get icon => switch (this) {
        OvaAgentMode.orchestrator => Icons.hub_rounded,
        OvaAgentMode.computerUse => Icons.desktop_mac_rounded,
        OvaAgentMode.codeTerminal => Icons.terminal_rounded,
        OvaAgentMode.studioNle => Icons.movie_creation_outlined,
        OvaAgentMode.creatorOps => Icons.bolt_rounded,
        OvaAgentMode.research => Icons.science_outlined,
      };

  static OvaAgentMode fromWire(String? raw) => switch (raw) {
        'computer_use' => OvaAgentMode.computerUse,
        'code_terminal' => OvaAgentMode.codeTerminal,
        'studio_nle' => OvaAgentMode.studioNle,
        'creator_ops' => OvaAgentMode.creatorOps,
        'research' => OvaAgentMode.research,
        _ => OvaAgentMode.orchestrator,
      };
}

enum OvaAgentEffort {
  fast,
  balanced,
  deepThink;

  String get wireValue => switch (this) {
        OvaAgentEffort.fast => 'fast',
        OvaAgentEffort.balanced => 'balanced',
        OvaAgentEffort.deepThink => 'deep_think',
      };

  String get label => switch (this) {
        OvaAgentEffort.fast => 'Fast',
        OvaAgentEffort.balanced => 'Balanced',
        OvaAgentEffort.deepThink => 'Extended Thinking',
      };

  IconData get icon => switch (this) {
        OvaAgentEffort.fast => Icons.flash_on_rounded,
        OvaAgentEffort.balanced => Icons.tune_rounded,
        OvaAgentEffort.deepThink => Icons.psychology_rounded,
      };

  static OvaAgentEffort fromWire(String? raw) => switch (raw) {
        'fast' => OvaAgentEffort.fast,
        'deep_think' => OvaAgentEffort.deepThink,
        _ => OvaAgentEffort.balanced,
      };
}

enum OvaPlanStepStatus {
  pending,
  inProgress,
  completed;

  String get wireValue => switch (this) {
        OvaPlanStepStatus.pending => 'pending',
        OvaPlanStepStatus.inProgress => 'in_progress',
        OvaPlanStepStatus.completed => 'completed',
      };

  static OvaPlanStepStatus fromWire(String? raw) => switch (raw) {
        'completed' => OvaPlanStepStatus.completed,
        'in_progress' => OvaPlanStepStatus.inProgress,
        _ => OvaPlanStepStatus.pending,
      };
}

class OvaAgentPlanStep {
  final String id;
  final String title;
  final OvaPlanStepStatus status;

  const OvaAgentPlanStep({
    required this.id,
    required this.title,
    this.status = OvaPlanStepStatus.pending,
  });

  OvaAgentPlanStep copyWith({
    String? title,
    OvaPlanStepStatus? status,
  }) {
    return OvaAgentPlanStep(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'status': status.wireValue,
      };

  factory OvaAgentPlanStep.fromMap(Map<String, dynamic> map) {
    return OvaAgentPlanStep(
      id: (map['id'] ?? 'step').toString(),
      title: (map['title'] ?? 'Task step').toString(),
      status: OvaPlanStepStatus.fromWire(map['status']?.toString()),
    );
  }
}

enum OvaToolCallStatus {
  pendingMac,
  awaitingApproval,
  approved,
  denied,
  running,
  completed,
  error;

  String get wireValue => switch (this) {
        OvaToolCallStatus.pendingMac => 'pending_mac',
        OvaToolCallStatus.awaitingApproval => 'awaiting_approval',
        OvaToolCallStatus.approved => 'approved',
        OvaToolCallStatus.denied => 'denied',
        OvaToolCallStatus.running => 'running',
        OvaToolCallStatus.completed => 'completed',
        OvaToolCallStatus.error => 'error',
      };

  bool get isTerminal =>
      this == OvaToolCallStatus.completed ||
      this == OvaToolCallStatus.denied ||
      this == OvaToolCallStatus.error;

  static OvaToolCallStatus fromWire(String? raw) => switch (raw) {
        'pending_mac' => OvaToolCallStatus.pendingMac,
        'awaiting_approval' => OvaToolCallStatus.awaitingApproval,
        'approved' => OvaToolCallStatus.approved,
        'denied' => OvaToolCallStatus.denied,
        'running' => OvaToolCallStatus.running,
        'completed' => OvaToolCallStatus.completed,
        'error' => OvaToolCallStatus.error,
        _ => OvaToolCallStatus.completed,
      };
}

class OvaAgentToolCall {
  final String id;
  final String name;
  final String title;
  final Map<String, dynamic> args;
  final bool requiresApproval;
  final OvaToolCallStatus status;
  final String? approvedBy;
  final String? output;
  final int? exitCode;
  final int? durationMs;

  const OvaAgentToolCall({
    required this.id,
    required this.name,
    required this.title,
    this.args = const {},
    this.requiresApproval = false,
    this.status = OvaToolCallStatus.pendingMac,
    this.approvedBy,
    this.output,
    this.exitCode,
    this.durationMs,
  });

  IconData get icon => switch (name) {
        'inspect_workstation' => Icons.monitor_heart_outlined,
        'capture_screen_context' => Icons.screenshot_monitor_rounded,
        'list_open_windows' => Icons.web_asset_rounded,
        'manage_app' || 'open_mac_app' => Icons.launch_rounded,
        'navigate_app_menu' => Icons.menu_open_rounded,
        'click_ui_element' => Icons.touch_app_rounded,
        'mouse_action' => Icons.mouse_rounded,
        'keyboard_action' || 'type_on_workstation' => Icons.keyboard_rounded,
        'clipboard_action' => Icons.content_paste_rounded,
        'run_applescript' => Icons.integration_instructions_outlined,
        'manage_computer_system' ||
        'system_control' ||
        'power_workstation' =>
          Icons.tune_rounded,
        'save_memory' ||
        'recall_memories' ||
        'delete_memory' =>
          Icons.psychology_rounded,
        'list_workspace_files' => Icons.folder_open_rounded,
        'read_file_snippet' => Icons.description_outlined,
        'nle_bridge_action' => Icons.movie_edit,
        'press_hotkey' || 'send_mac_hotkey' => Icons.keyboard_command_key_rounded,
        'run_terminal_command' => Icons.terminal_rounded,
        'write_workspace_file' => Icons.edit_document,
        'search_web' => Icons.public_rounded,
        'search_workspace' => Icons.search_rounded,
        _ => Icons.build_circle_outlined,
      };

  OvaAgentToolCall copyWith({
    OvaToolCallStatus? status,
    String? approvedBy,
    String? output,
    int? exitCode,
    int? durationMs,
  }) {
    return OvaAgentToolCall(
      id: id,
      name: name,
      title: title,
      args: args,
      requiresApproval: requiresApproval,
      status: status ?? this.status,
      approvedBy: approvedBy ?? this.approvedBy,
      output: output ?? this.output,
      exitCode: exitCode ?? this.exitCode,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'title': title,
        'args': args,
        'requiresApproval': requiresApproval,
        'status': status.wireValue,
        if (approvedBy != null) 'approvedBy': approvedBy,
        if (output != null) 'output': output,
        if (exitCode != null) 'exitCode': exitCode,
        if (durationMs != null) 'durationMs': durationMs,
      };

  factory OvaAgentToolCall.fromMap(Map<String, dynamic> map) {
    final rawArgs = map['args'];
    final requiresApproval = map['requiresApproval'] == true ||
        map['risk']?.toString() == 'approval_required';
    return OvaAgentToolCall(
      id: (map['id'] ?? 'tc').toString(),
      name: (map['name'] ?? 'tool').toString(),
      title: (map['title'] ?? map['name'] ?? 'Tool execution').toString(),
      args: rawArgs is Map ? Map<String, dynamic>.from(rawArgs) : const {},
      requiresApproval: requiresApproval,
      status: OvaToolCallStatus.fromWire(map['status']?.toString()),
      approvedBy: map['approvedBy']?.toString(),
      output: map['output']?.toString(),
      exitCode: map['exitCode'] is num ? (map['exitCode'] as num).toInt() : null,
      durationMs:
          map['durationMs'] is num ? (map['durationMs'] as num).toInt() : null,
    );
  }
}

class OvaAgentArtifact {
  final String id;
  final String title;
  final String kind;
  final String language;
  final String content;

  const OvaAgentArtifact({
    required this.id,
    required this.title,
    this.kind = 'markdown',
    this.language = 'markdown',
    required this.content,
  });

  IconData get icon => switch (kind) {
        'code' => Icons.code_rounded,
        'script' || 'command' => Icons.terminal_rounded,
        'plan' => Icons.checklist_rounded,
        _ => Icons.article_outlined,
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'kind': kind,
        'language': language,
        'content': content,
      };

  factory OvaAgentArtifact.fromMap(Map<String, dynamic> map) {
    return OvaAgentArtifact(
      id: (map['id'] ?? 'art').toString(),
      title: (map['title'] ?? 'Artifact').toString(),
      kind: (map['kind'] ?? 'markdown').toString(),
      language: (map['language'] ?? 'markdown').toString(),
      content: (map['content'] ?? '').toString(),
    );
  }
}

class OvaSubagentBadge {
  final String id;
  final String label;
  final String role;

  const OvaSubagentBadge({
    required this.id,
    required this.label,
    required this.role,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'role': role,
      };

  factory OvaSubagentBadge.fromMap(Map<String, dynamic> map) {
    return OvaSubagentBadge(
      id: (map['id'] ?? 'orchestrator').toString(),
      label: (map['label'] ?? 'Ova Orchestrator').toString(),
      role: (map['role'] ?? 'Multi-agent coordination').toString(),
    );
  }
}

class OvaAgentTurn {
  final String id;
  final int createdAtMs;
  final String role; // 'user' | 'assistant'
  final String originDevice; // 'mac' | 'mobile'
  final String authorLabel;
  final String text;
  final String status; // 'thinking' | 'awaiting_approval' | 'running_tools' | 'synthesizing' | 'completed' | 'error'
  final List<String> thinkingSteps;
  final int thinkingDurationMs;
  final OvaSubagentBadge? subagent;
  final List<OvaAgentToolCall> toolCalls;
  final List<OvaAgentArtifact> artifacts;
  final List<String> followUps;
  final List<String> contextChips;
  final DateTime createdAt;

  const OvaAgentTurn({
    required this.id,
    required this.createdAtMs,
    required this.role,
    required this.originDevice,
    required this.authorLabel,
    required this.text,
    this.status = 'completed',
    this.thinkingSteps = const [],
    this.thinkingDurationMs = 0,
    this.subagent,
    this.toolCalls = const [],
    this.artifacts = const [],
    this.followUps = const [],
    this.contextChips = const [],
    required this.createdAt,
  });

  bool get isUser => role == 'user';
  bool get isBusy =>
      status == 'thinking' ||
      status == 'running_tools' ||
      status == 'synthesizing';

  bool get hasPendingApprovals => toolCalls
      .any((tc) => tc.status == OvaToolCallStatus.awaitingApproval);

  Map<String, dynamic> toFirestoreMap() => {
        'createdAtMs': createdAtMs,
        'role': role,
        'originDevice': originDevice,
        'authorLabel': authorLabel,
        'text': text,
        'status': status,
        'thinkingSteps': thinkingSteps,
        'thinkingDurationMs': thinkingDurationMs,
        if (subagent != null) 'subagent': subagent!.toMap(),
        'toolCalls': toolCalls.map((t) => t.toMap()).toList(),
        'artifacts': artifacts.map((a) => a.toMap()).toList(),
        'followUps': followUps,
        'contextChips': contextChips,
        'createdAt': createdAt.toUtc(),
        'updatedAt': DateTime.now().toUtc(),
      };

  factory OvaAgentTurn.fromMap(String id, Map<String, dynamic> d) {
    final created = _parseDateTime(d['createdAt'], d['createdAtMs']);
    final ms = d['createdAtMs'] is num
        ? (d['createdAtMs'] as num).toInt()
        : created.millisecondsSinceEpoch;
    final rawSub = d['subagent'];
    final rawTools = d['toolCalls'] as List<dynamic>? ?? const [];
    final rawArtifacts = d['artifacts'] as List<dynamic>? ?? const [];
    final rawThinking = d['thinkingSteps'] as List<dynamic>? ?? const [];
    final rawFollowUps = d['followUps'] as List<dynamic>? ?? const [];
    final rawContext = d['contextChips'] as List<dynamic>? ?? const [];

    return OvaAgentTurn(
      id: id,
      createdAtMs: ms,
      role: (d['role'] ?? 'assistant').toString(),
      originDevice: (d['originDevice'] ?? 'mobile').toString(),
      authorLabel: (d['authorLabel'] ?? 'Creator').toString(),
      text: (d['text'] ?? '').toString(),
      status: (d['status'] ?? 'completed').toString(),
      thinkingSteps: rawThinking.map((e) => e.toString()).toList(),
      thinkingDurationMs: d['thinkingDurationMs'] is num
          ? (d['thinkingDurationMs'] as num).toInt()
          : 0,
      subagent: rawSub is Map
          ? OvaSubagentBadge.fromMap(Map<String, dynamic>.from(rawSub))
          : null,
      toolCalls: rawTools
          .whereType<Map>()
          .map((m) => OvaAgentToolCall.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      artifacts: rawArtifacts
          .whereType<Map>()
          .map((m) => OvaAgentArtifact.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      followUps: rawFollowUps.map((e) => e.toString()).toList(),
      contextChips: rawContext.map((e) => e.toString()).toList(),
      createdAt: created,
    );
  }
}

class OvaAgentSession {
  final String id;
  final String title;
  final OvaAgentMode agentMode;
  final OvaAgentEffort effort;
  final bool fullComputerAccess;
  final String status;
  final String? activeSubagent;
  final List<OvaAgentPlanStep> plan;
  final String lastPreview;
  final String originDevice;
  final String? deviceId;
  final String? computerName;
  final int turnCount;
  final bool pinned;
  final int updatedAtMs;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OvaAgentSession({
    required this.id,
    required this.title,
    this.agentMode = OvaAgentMode.orchestrator,
    this.effort = OvaAgentEffort.balanced,
    this.fullComputerAccess = true,
    this.status = 'idle',
    this.activeSubagent,
    this.plan = const [],
    this.lastPreview = '',
    this.originDevice = 'mobile',
    this.deviceId,
    this.computerName,
    this.turnCount = 0,
    this.pinned = false,
    required this.updatedAtMs,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toFirestoreMap() => {
        'title': title,
        'agentMode': agentMode.wireValue,
        'effort': effort.wireValue,
        'fullComputerAccess': fullComputerAccess,
        'status': status,
        if (activeSubagent != null) 'activeSubagent': activeSubagent,
        'plan': plan.map((p) => p.toMap()).toList(),
        'lastPreview': lastPreview,
        'originDevice': originDevice,
        if (deviceId != null) 'deviceId': deviceId,
        if (computerName != null) 'computerName': computerName,
        'turnCount': turnCount,
        'pinned': pinned,
        'updatedAtMs': updatedAtMs,
        'createdAt': createdAt.toUtc(),
        'updatedAt': updatedAt.toUtc(),
      };

  factory OvaAgentSession.fromMap(String id, Map<String, dynamic> d) {
    final created = _parseDateTime(d['createdAt'], d['updatedAtMs']);
    final updated = _parseDateTime(d['updatedAt'], d['updatedAtMs']);
    final updMs = d['updatedAtMs'] is num
        ? (d['updatedAtMs'] as num).toInt()
        : updated.millisecondsSinceEpoch;
    final rawPlan = d['plan'] as List<dynamic>? ?? const [];

    return OvaAgentSession(
      id: id,
      title: (d['title'] ?? 'New Agent Session').toString(),
      agentMode: OvaAgentMode.fromWire(d['agentMode']?.toString()),
      effort: OvaAgentEffort.fromWire(d['effort']?.toString()),
      fullComputerAccess: d['fullComputerAccess'] != false,
      status: (d['status'] ?? 'idle').toString(),
      activeSubagent: d['activeSubagent']?.toString(),
      plan: rawPlan
          .whereType<Map>()
          .map((m) => OvaAgentPlanStep.fromMap(Map<String, dynamic>.from(m)))
          .toList(),
      lastPreview: (d['lastPreview'] ?? '').toString(),
      originDevice: (d['originDevice'] ?? 'mobile').toString(),
      deviceId: d['deviceId']?.toString(),
      computerName: d['computerName']?.toString(),
      turnCount: d['turnCount'] is num ? (d['turnCount'] as num).toInt() : 0,
      pinned: d['pinned'] == true,
      updatedAtMs: updMs,
      createdAt: created,
      updatedAt: updated,
    );
  }

  OvaAgentSession copyWith({
    String? id,
    String? title,
    OvaAgentMode? agentMode,
    OvaAgentEffort? effort,
    bool? fullComputerAccess,
    String? status,
    String? activeSubagent,
    List<OvaAgentPlanStep>? plan,
    String? lastPreview,
    String? originDevice,
    String? deviceId,
    String? computerName,
    int? turnCount,
    bool? pinned,
    int? updatedAtMs,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OvaAgentSession(
      id: id ?? this.id,
      title: title ?? this.title,
      agentMode: agentMode ?? this.agentMode,
      effort: effort ?? this.effort,
      fullComputerAccess: fullComputerAccess ?? this.fullComputerAccess,
      status: status ?? this.status,
      activeSubagent: activeSubagent ?? this.activeSubagent,
      plan: plan ?? this.plan,
      lastPreview: lastPreview ?? this.lastPreview,
      originDevice: originDevice ?? this.originDevice,
      deviceId: deviceId ?? this.deviceId,
      computerName: computerName ?? this.computerName,
      turnCount: turnCount ?? this.turnCount,
      pinned: pinned ?? this.pinned,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime _parseDateTime(dynamic raw, dynamic fallbackMs) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
  }
  if (fallbackMs is num) {
    return DateTime.fromMillisecondsSinceEpoch(fallbackMs.toInt());
  }
  return DateTime.now();
}

class OvaAgentMemory {
  final String id;
  final String key;
  final String content;
  final String originDevice;
  final DateTime updatedAt;

  const OvaAgentMemory({
    required this.id,
    required this.key,
    required this.content,
    this.originDevice = 'computer',
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'key': key,
        'content': content,
        'originDevice': originDevice,
        'updatedAtMs': updatedAt.millisecondsSinceEpoch,
      };

  factory OvaAgentMemory.fromMap(String id, Map<String, dynamic> d) {
    final updMs =
        d['updatedAtMs'] is num ? (d['updatedAtMs'] as num).toInt() : null;
    return OvaAgentMemory(
      id: id,
      key: (d['key'] ?? '').toString(),
      content: (d['content'] ?? '').toString(),
      originDevice: (d['originDevice'] ?? 'unknown').toString(),
      updatedAt: _parseDateTime(d['updatedAt'], updMs),
    );
  }
}

