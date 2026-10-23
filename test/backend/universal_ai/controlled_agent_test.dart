import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/universal_ai/universal_ai_models.dart';
import 'package:oneova/backend/universal_ai/universal_ai_services.dart';
import 'package:oneova/backend/universal_ai/agent_control_models.dart';
import 'package:oneova/backend/universal_ai/controlled_agent_service.dart';

void main() {
  late ToolRegistry registry;
  late ToolExecutor executor;
  late ControlledAgentService service;

  setUp(() {
    registry = ToolRegistry();
    executor = ToolExecutor(registry);
    service = ControlledAgentService(registry, executor);

    registry.registerTool(
      const AIToolDefinition(
        name: 'sendMessage',
        description: 'Send a message',
        category: AIToolCategory.messages,
        privilege: ToolPrivilegeLevel.userAction,
        parameterSchema: {},
      ),
      (params) async => 'Message Sent',
    );
  });

  test('Draft mode prevents execution but logs intent', () async {
    const profile = ControlledAgentProfile(
      id: 'agent_1',
      ownerUserId: 'user_1',
      mode: AgentMode.draft, // DRAFT MODE
      allowedPermissions: [AIToolCategory.messages],
      limits: AgentLimits(),
    );

    final result = await service.evaluateAndExecute(profile, 'sendMessage', {'text': 'Hello'});
    
    expect(result['status'], 'drafted');
    expect(result['intendedTool'], 'sendMessage');

    final logs = service.getAuditLogsForTesting();
    expect(logs.length, 1);
    expect(logs[0].authorized, true);
    expect(logs[0].authorizationReason, 'Drafted according to agent mode');
    expect(logs[0].result['status'], 'drafted'); // Result is recorded
  });

  test('Auto mode executes when within limits', () async {
    const profile = ControlledAgentProfile(
      id: 'agent_2',
      ownerUserId: 'user_1',
      mode: AgentMode.auto,
      allowedPermissions: [AIToolCategory.messages],
      limits: AgentLimits(maxDailyMessages: 1), // Strict limit
    );

    // First execution succeeds
    final result1 = await service.evaluateAndExecute(profile, 'sendMessage', {'text': 'Hello'});
    expect(result1, 'Message Sent');

    // Second execution blocks due to limit
    final result2 = await service.evaluateAndExecute(profile, 'sendMessage', {'text': 'Spam'});
    expect(result2['error'], 'Daily message limit reached');

    final logs = service.getAuditLogsForTesting();
    expect(logs.length, 2);
    expect(logs[1].authorized, false);
    expect(logs[1].authorizationReason, 'Daily message limit reached');
  });

  test('Blocks execution to blocked contacts', () async {
    const profile = ControlledAgentProfile(
      id: 'agent_3',
      ownerUserId: 'user_1',
      mode: AgentMode.auto,
      allowedPermissions: [AIToolCategory.messages],
      limits: AgentLimits(blockedContacts: ['jerk_user_99']),
    );

    final result = await service.evaluateAndExecute(profile, 'sendMessage', {'contactId': 'jerk_user_99'});
    expect(result['error'], 'Attempted to interact with a blocked contact');

    final logs = service.getAuditLogsForTesting();
    expect(logs[0].authorized, false);
  });
}
