
// ServiceState enum removed to prevent frontend-invented statuses.

enum SystemComponent {
  realtime,
  ai,
  notifications,
  messaging,
  storage,
  database,
}

class ComponentHealth {
  final SystemComponent component;
  final String statusDisplay;
  final int colorHex;
  final DateTime lastHeartbeat;
  final int retryCount;
  final String? lastError; // Only exposed to admins

  const ComponentHealth({
    required this.component,
    required this.statusDisplay,
    required this.colorHex,
    required this.lastHeartbeat,
    this.retryCount = 0,
    this.lastError,
  });

  ComponentHealth copyWith({
    String? statusDisplay,
    int? colorHex,
    DateTime? lastHeartbeat,
    int? retryCount,
    String? lastError,
  }) {
    return ComponentHealth(
      component: component,
      statusDisplay: statusDisplay ?? this.statusDisplay,
      colorHex: colorHex ?? this.colorHex,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }
}

class SystemStatusSnapshot {
  final Map<SystemComponent, ComponentHealth> components;
  final String globalStateDisplay;
  final int globalColorHex;
  final String globalDescription;
  
  const SystemStatusSnapshot({
    required this.components,
    required this.globalStateDisplay,
    required this.globalColorHex,
    required this.globalDescription,
  });
}
