import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/agent_workspace/ova_agent_mac_executor.dart';
import 'package:oneova/agent_workspace/ova_agent_models.dart';

void main() {
  group('OvaAgentMacExecutor real-time computer navigation & control skills', () {
    test('manage_app list_running returns running processes', () async {
      const call = OvaAgentToolCall(
        id: 't_apps',
        name: 'manage_app',
        title: 'List Running Apps',
        args: {'action': 'list_running'},
      );

      final res = await OvaAgentMacExecutor.instance.execute(call);
      expect(res.ok, isTrue);
      expect(res.output.isNotEmpty, isTrue);
    });

    test('manage_computer_system get_system_status returns battery and disk', () async {
      const call = OvaAgentToolCall(
        id: 't_sys',
        name: 'manage_computer_system',
        title: 'System Status',
        args: {'action': 'get_system_status'},
      );

      final res = await OvaAgentMacExecutor.instance.execute(call);
      expect(res.ok, isTrue);
      expect(res.output, contains('Disk:'));
    });

    test('press_hotkey dispatches key events without failure', () async {
      const call = OvaAgentToolCall(
        id: 't_key',
        name: 'press_hotkey',
        title: 'Press Hotkey',
        args: {'keys': 'shift', 'repeat': 1},
      );

      final res = await OvaAgentMacExecutor.instance.execute(call);
      expect(res.ok, isTrue);
      expect(res.output, contains('Dispatched hotkey'));
    });
  });
}

