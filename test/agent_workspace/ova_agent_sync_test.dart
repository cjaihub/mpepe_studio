import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/agent_workspace/ova_agent_models.dart';

void main() {
  group('OvaAgentSession creation and title derivation tests', () {
    test('OvaAgentSession default new chat initialization', () {
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final session = OvaAgentSession(
        id: 'sess_$nowMs',
        title: 'New Chat',
        agentMode: OvaAgentMode.orchestrator,
        effort: OvaAgentEffort.deepThink,
        fullComputerAccess: true,
        status: 'idle',
        lastPreview: 'Ready for new instruction',
        originDevice: 'mac',
        turnCount: 0,
        updatedAtMs: nowMs,
        createdAt: now,
        updatedAt: now,
      );

      expect(session.title, equals('New Chat'));
      expect(session.turnCount, equals(0));
      expect(session.status, equals('idle'));
      expect(session.fullComputerAccess, isTrue);

      final map = session.toFirestoreMap();
      expect(map['title'], equals('New Chat'));
      expect(map['agentMode'], equals('orchestrator'));
      expect(map['status'], equals('idle'));
      expect(map['turnCount'], equals(0));

      final restored = OvaAgentSession.fromMap(session.id, map);
      expect(restored.id, equals(session.id));
      expect(restored.title, equals('New Chat'));
      expect(restored.agentMode, equals(OvaAgentMode.orchestrator));
    });

    test('Canonical path structure guarantees account-level sync across mobile & mac', () {
      const uid = 'gVIljkFHwLMKXTpHCuYJwYC7Dxh2';
      final canonicalBasePath = 'users/$uid/agent_sessions';
      const sessionId = 'sess_1793832271120';
      final turnsPath = '$canonicalBasePath/$sessionId/turns';

      expect(canonicalBasePath, equals('users/gVIljkFHwLMKXTpHCuYJwYC7Dxh2/agent_sessions'));
      expect(turnsPath, equals('users/gVIljkFHwLMKXTpHCuYJwYC7Dxh2/agent_sessions/sess_1793832271120/turns'));
    });
  });
}
