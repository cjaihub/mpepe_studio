import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_config.dart';
import '../models/agent_audit_event.dart';
import '../../auth/auth_repository.dart';
import '../../backend/settings_service.dart';

final backgroundAgentServiceProvider = Provider<BackgroundAgentService>((ref) {
  return BackgroundAgentService(ref: ref);
});

final agentConfigProvider = StreamProvider<AgentConfig>((ref) {
  final service = ref.watch(backgroundAgentServiceProvider);
  return service.streamConfig();
});

final agentAuditsProvider = StreamProvider<List<AgentAuditEvent>>((ref) {
  final service = ref.watch(backgroundAgentServiceProvider);
  return service.streamAudits();
});

class BackgroundAgentService {
  final Ref ref;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  BackgroundAgentService({required this.ref});

  // The agent config is the `aiAgent` category of the one settings store,
  // user_settings/{uid}. SettingsService mirrors it to
  // users/{uid}/ai_settings/agent_config, which aiGateway reads.
  SettingsService get _settings => SettingsService(firestore: _firestore);

  Stream<AgentConfig> streamConfig() {
    final user = ref.read(authStateProvider).value;
    if (user == null) return Stream.value(AgentConfig());
    return _settings.watchCategory(user.uid, 'aiAgent').map(AgentConfig.fromMap);
  }

  Future<void> updateConfig(AgentConfig config) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    await _settings.updateSettingsCategory(user.uid, 'aiAgent', config.toMap());
  }

  Future<void> pauseAllAi() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    await _settings.updateSettingsCategory(user.uid, 'aiAgent', {'isGloballyPaused': true});
  }

  Future<void> resumeAllAi() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    await _settings.updateSettingsCategory(user.uid, 'aiAgent', {'isGloballyPaused': false});
  }

  Stream<List<AgentAuditEvent>> streamAudits() {
    final user = ref.read(authStateProvider).value;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('agent_audits')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AgentAuditEvent.fromFirestore(doc))
            .toList());
  }
}
