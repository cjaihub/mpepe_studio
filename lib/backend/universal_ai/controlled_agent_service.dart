import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:oneova/backend/universal_ai/universal_ai_models.dart';
import 'package:oneova/backend/universal_ai/universal_ai_services.dart';
import 'package:oneova/backend/universal_ai/agent_control_models.dart';

class ControlledAgentService {
  final ToolRegistry _registry;
  final ToolExecutor _executor;
  final List<AutonomousActionAudit> _auditLogs = [];

  int _dailyActionsUsed = 0;
  int _dailyMessagesUsed = 0;
  String _usageDateKey = _todayKey();

  ControlledAgentService(this._registry, this._executor);

  static String _todayKey() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> syncQuotaFromFirestore(String uid) async {
    if (Firebase.apps.isEmpty || uid.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ai_settings')
          .doc('quotas')
          .get();
      final data = doc.data();
      if (data == null) return;
      final dateKey = (data['dateKey'] ?? '').toString();
      if (dateKey == _todayKey()) {
        _usageDateKey = dateKey;
        _dailyActionsUsed = (data['dailyActionsUsed'] as num?)?.toInt() ?? 0;
        _dailyMessagesUsed = (data['dailyMessagesUsed'] as num?)?.toInt() ?? 0;
      } else {
        _usageDateKey = _todayKey();
        _dailyActionsUsed = 0;
        _dailyMessagesUsed = 0;
      }
    } catch (_) {}
  }

  void _persistAuditAndQuota(ControlledAgentProfile profile, AutonomousActionAudit log) {
    if (Firebase.apps.isEmpty || profile.id.isEmpty) return;
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(profile.id);
      unawaited(userRef.collection('agent_audits').doc(log.id).set({
        'agentId': log.agentId,
        'toolName': log.toolName,
        'authorized': log.authorized,
        'reason': log.authorizationReason,
        'timestamp': FieldValue.serverTimestamp(),
      }));
      unawaited(userRef.collection('ai_settings').doc('quotas').set({
        'dateKey': _usageDateKey,
        'dailyActionsUsed': _dailyActionsUsed,
        'dailyMessagesUsed': _dailyMessagesUsed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } catch (_) {}
  }

  Future<dynamic> evaluateAndExecute(ControlledAgentProfile profile, String toolName, Map<String, dynamic> params) async {
    final def = _registry.getDefinition(toolName);
    if (def == null) {
      return _logAndReject(profile, toolName, params, 'Tool not found');
    }

    // 1. Check Category Permissions
    if (!profile.allowedPermissions.contains(def.category)) {
      return _logAndReject(profile, toolName, params, 'Category \${def.category.name} not permitted for this agent');
    }

    // 2. Check Allowed Hours
    final currentHour = DateTime.now().hour;
    if (currentHour < profile.limits.allowedHourStart || currentHour >= profile.limits.allowedHourEnd) {
      return _logAndReject(profile, toolName, params, 'Agent operating outside allowed hours');
    }

    // 3. Check Limits
    if (_dailyActionsUsed >= profile.limits.maxDailyActions) {
      return _logAndReject(profile, toolName, params, 'Daily action limit reached');
    }
    if (def.category == AIToolCategory.messages && _dailyMessagesUsed >= profile.limits.maxDailyMessages) {
      return _logAndReject(profile, toolName, params, 'Daily message limit reached');
    }

    // 4. Check Blocked Contacts (assuming params contains 'contactId')
    if (params.containsKey('contactId') && profile.limits.blockedContacts.contains(params['contactId'])) {
      return _logAndReject(profile, toolName, params, 'Attempted to interact with a blocked contact');
    }

    // 5. Evaluate Mode
    dynamic result;
    if (profile.mode == AgentMode.suggestions || profile.mode == AgentMode.draft) {
      // Do not execute. Return the intent to the UI as a draft/suggestion.
      result = {'status': 'drafted', 'intendedTool': toolName, 'intendedParams': params};
      _logSuccess(profile, toolName, params, result, 'Drafted according to agent mode');
    } else if (profile.mode == AgentMode.scheduled) {
      result = {'status': 'scheduled', 'intendedTool': toolName, 'intendedParams': params};
      _logSuccess(profile, toolName, params, result, 'Scheduled according to agent mode');
    } else if (profile.mode == AgentMode.auto) {
      // Execute the action for real
      _dailyActionsUsed++;
      if (def.category == AIToolCategory.messages) _dailyMessagesUsed++;
      
      try {
        result = await _executor.execute(toolName, params);
        _logSuccess(profile, toolName, params, result, 'Executed autonomously');
      } catch (e) {
        return _logAndReject(profile, toolName, params, 'Execution failed: \$e');
      }
    }

    return result;
  }

  Map<String, dynamic> _logAndReject(ControlledAgentProfile profile, String toolName, Map<String, dynamic> params, String reason) {
    final log = AutonomousActionAudit(
      id: 'aa_\${DateTime.now().millisecondsSinceEpoch}',
      agentId: profile.id,
      timestamp: DateTime.now(),
      toolName: toolName,
      toolInvocationParams: params,
      authorized: false,
      authorizationReason: reason,
    );
    _auditLogs.add(log);
    _persistAuditAndQuota(profile, log);
    return {'error': reason};
  }

  void _logSuccess(ControlledAgentProfile profile, String toolName, Map<String, dynamic> params, dynamic result, String reason) {
    final log = AutonomousActionAudit(
      id: 'aa_\${DateTime.now().millisecondsSinceEpoch}',
      agentId: profile.id,
      timestamp: DateTime.now(),
      toolName: toolName,
      toolInvocationParams: params,
      result: result,
      authorized: true,
      authorizationReason: reason,
    );
    _auditLogs.add(log);
    _persistAuditAndQuota(profile, log);
  }

  List<AutonomousActionAudit> getAuditLogsForTesting() => _auditLogs;
  void resetLimitsForTesting() {
    _dailyActionsUsed = 0;
    _dailyMessagesUsed = 0;
  }
}
