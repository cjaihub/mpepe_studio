import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'system_status_models.dart';
import '../remote_connect_service.dart';
import '../agents/background_agent_service.dart';
import '../agents/models/background_agent_models.dart';
import '../telemetry/telemetry_stream_provider.dart';
import '../session_service.dart';

final systemStatusProvider = Provider<SystemStatusSnapshot>((ref) {
  final now = DateTime.now();

  // 1. Realtime (remoteConnectProvider)
  final remoteConnect = ref.watch(remoteConnectProvider);
  String realtimeStatus = remoteConnect.status.name.toUpperCase();
  int realtimeColor = remoteConnect.status == ConnectionStatus.connected ? 0xFF69F0AE : 0xFFFFAB40;
  if (remoteConnect.status == ConnectionStatus.error) realtimeColor = 0xFF990000;
  
  // 2. AI (backgroundAgentConfigProvider)
  final aiConfig = ref.watch(backgroundAgentServiceProvider).config;
  String aiStatus = aiConfig.status.name.toUpperCase();
  int aiColor = (aiConfig.status == AgentStatus.idle || aiConfig.status == AgentStatus.running) ? 0xFF69F0AE : 0xFFFFAB40;
  if (aiConfig.isGlobalEmergencyStopActive) {
    aiStatus = 'EMERGENCY STOP';
    aiColor = 0xFF990000;
  }

  // 3. Storage (telemetryStreamProvider)
  final telemetry = ref.watch(telemetryStreamProvider).value;
  String storageStatus = 'UNKNOWN';
  int storageColor = 0xFF9CA3AF;
  if (telemetry != null) {
    storageStatus = '${telemetry.storageUsedGb.toStringAsFixed(1)} GB / ${telemetry.storageTotalGb.toStringAsFixed(1)} GB';
    storageColor = 0xFF69F0AE; 
  }

  // 4. Database (sessionProvider)
  final session = ref.watch(sessionProvider).activeSession;
  String dbStatus = session?.status.toUpperCase() ?? 'DISCONNECTED';
  int dbColor = session?.isLive == true ? 0xFF69F0AE : 0xFF990000;

  // 5. System Health (Global)
  bool isHealthy = remoteConnect.status == ConnectionStatus.connected && (session?.isLive == true);
  String globalStatus = isHealthy ? 'ONLINE' : 'DEGRADED';
  int globalColor = isHealthy ? 0xFF69F0AE : 0xFFFFAB40;
  String globalDesc = isHealthy ? 'All core services operational' : 'Experiencing connectivity issues';

  return SystemStatusSnapshot(
    components: {
      SystemComponent.realtime: ComponentHealth(
        component: SystemComponent.realtime,
        statusDisplay: realtimeStatus,
        colorHex: realtimeColor,
        lastHeartbeat: now,
      ),
      SystemComponent.ai: ComponentHealth(
        component: SystemComponent.ai,
        statusDisplay: aiStatus,
        colorHex: aiColor,
        lastHeartbeat: now,
      ),
      SystemComponent.storage: ComponentHealth(
        component: SystemComponent.storage,
        statusDisplay: storageStatus,
        colorHex: storageColor,
        lastHeartbeat: now,
      ),
      SystemComponent.database: ComponentHealth(
        component: SystemComponent.database,
        statusDisplay: dbStatus,
        colorHex: dbColor,
        lastHeartbeat: now,
      ),
      SystemComponent.messaging: ComponentHealth(
        component: SystemComponent.messaging,
        statusDisplay: 'ACTIVE',
        colorHex: 0xFF69F0AE,
        lastHeartbeat: now,
      ),
      SystemComponent.notifications: ComponentHealth(
        component: SystemComponent.notifications,
        statusDisplay: 'ACTIVE',
        colorHex: 0xFF69F0AE,
        lastHeartbeat: now,
      ),
    },
    globalStateDisplay: globalStatus,
    globalColorHex: globalColor,
    globalDescription: globalDesc,
  );
});
