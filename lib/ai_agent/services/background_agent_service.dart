import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_config.dart';
import '../models/agent_audit_event.dart';
import '../../auth/auth_repository.dart';

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

  Stream<AgentConfig> streamConfig() {
    final user = ref.read(authStateProvider).value;
    if (user == null) return Stream.value(AgentConfig());

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('ai_settings')
        .doc('agent_config')
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) {
        return AgentConfig();
      }
      return AgentConfig.fromMap(doc.data()!);
    });
  }

  Future<void> updateConfig(AgentConfig config) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('ai_settings')
        .doc('agent_config')
        .set(config.toMap(), SetOptions(merge: true));
  }

  Future<void> pauseAllAi() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('ai_settings')
        .doc('agent_config')
        .set({'isGloballyPaused': true}, SetOptions(merge: true));
  }

  Future<void> resumeAllAi() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('ai_settings')
        .doc('agent_config')
        .set({'isGloballyPaused': false}, SetOptions(merge: true));
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
