import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/background_agent_models.dart';

class BackgroundAgentService {
  static final BackgroundAgentService _instance = BackgroundAgentService._internal();
  factory BackgroundAgentService() => _instance;
  BackgroundAgentService._internal();

  BackgroundAgentConfig _config = const BackgroundAgentConfig();
  final List<AiAuditEvent> _activityLog = [];

  BackgroundAgentConfig get config => _config;
  List<AiAuditEvent> get activityLog => List.unmodifiable(_activityLog);

  // Stream for UI updates (e.g. Dashboard)
  final _configController = StreamController<BackgroundAgentConfig>.broadcast();
  Stream<BackgroundAgentConfig> get configStream => _configController.stream;

  final _logController = StreamController<List<AiAuditEvent>>.broadcast();
  Stream<List<AiAuditEvent>> get logStream => _logController.stream;

  /// GLOBAL KILL SWITCH
  /// Immediately halts all background AI processing and transitions mode to offline.
  void emergencyStopAllAi() {
    _config = _config.copyWith(
      isGlobalEmergencyStopActive: true,
      mode: BackgroundAgentMode.offline,
      status: AgentStatus.emergencyStop,
    );
    _configController.add(_config);
    _logSystemEvent("EMERGENCY STOP TRIGGERED. All autonomous functions halted.");
  }

  void pauseAgent() {
    if (_config.isGlobalEmergencyStopActive) return;
    _config = _config.copyWith(status: AgentStatus.paused);
    _configController.add(_config);
    _logSystemEvent("Agent paused by user.");
  }

  void resumeAgent() {
    if (_config.isGlobalEmergencyStopActive) return; // Cannot resume until emergency stop is cleared
    _config = _config.copyWith(status: AgentStatus.idle);
    _configController.add(_config);
    _logSystemEvent("Agent resumed.");
  }

  void clearEmergencyStop() {
    _config = _config.copyWith(
      isGlobalEmergencyStopActive: false,
      status: AgentStatus.idle,
    );
    _configController.add(_config);
    _logSystemEvent("Emergency stop cleared.");
  }

  /// Evaluates if the agent has permission to execute an action in the background.
  /// Never allows unrestricted autonomous behavior.
  bool canExecuteAction({
    required String action,
    required String channel,
    required String conversationId,
    required double estimatedCost,
  }) {
    if (_config.isGlobalEmergencyStopActive || _config.status == AgentStatus.paused) {
      return false;
    }

    if (_config.mode == BackgroundAgentMode.offline) {
      return false;
    }

    // 1. Budget and Limits Checks
    if (_config.currentDailyActions >= _config.dailyActionLimit) {
      return false;
    }
    if ((_config.currentDailyBudgetUsed + estimatedCost) > _config.dailyBudgetLimit) {
      return false;
    }

    // 2. Allowed/Blocked Action Check
    if (_config.blockedActions.contains(action)) {
      return false;
    }
    if (_config.allowedActions.isNotEmpty && !_config.allowedActions.contains(action)) {
      return false;
    }

    // 3. Allowed Channel/Conversation Check
    if (_config.allowedChannels.isNotEmpty && !_config.allowedChannels.contains(channel)) {
      return false;
    }
    if (_config.allowedConversations.isNotEmpty && !_config.allowedConversations.contains(conversationId)) {
      return false;
    }

    // 4. Schedule Check
    if (!_isWithinSchedule()) {
      return false;
    }

    return true;
  }

  /// Every autonomous action MUST generate an audit event.
  void recordAuditEvent({
    required String actionTaken,
    required String reasoning,
    required String conversationId,
    required String toolUsed,
    required Map<String, dynamic> dataAccessed,
    required String generatedResponse,
    required double cost,
  }) {
    final event = AiAuditEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      actionTaken: actionTaken,
      reasoning: reasoning,
      conversationId: conversationId,
      toolUsed: toolUsed,
      dataAccessed: dataAccessed,
      generatedResponse: generatedResponse,
    );

    _activityLog.insert(0, event);
    _logController.add(_activityLog);

    // Update limits
    _config = _config.copyWith(
      currentDailyActions: _config.currentDailyActions + 1,
      currentDailyBudgetUsed: _config.currentDailyBudgetUsed + cost,
    );
    _configController.add(_config);
  }

  void _logSystemEvent(String message) {
    recordAuditEvent(
      actionTaken: 'SYSTEM_STATE_CHANGE',
      reasoning: 'User triggered or system safety constraint.',
      conversationId: 'system',
      toolUsed: 'system',
      dataAccessed: {},
      generatedResponse: message,
      cost: 0.0,
    );
  }

  bool _isWithinSchedule() {
    if (_config.schedule.isEmpty) return true; // Unrestricted time
    // Implementation to check current time against start/end strings like "09:00" and "17:00"
    return true; 
  }
}

final backgroundAgentServiceProvider = Provider((ref) => BackgroundAgentService());

final backgroundAgentConfigProvider = StreamProvider<BackgroundAgentConfig>((ref) {
  final service = ref.watch(backgroundAgentServiceProvider);
  return service.configStream;
});

final backgroundAgentLogProvider = StreamProvider<List<AiAuditEvent>>((ref) {
  final service = ref.watch(backgroundAgentServiceProvider);
  return service.logStream;
});
