enum InstrumentTarget {
  api,
  database,
  realtime,
  video,
  ai,
  notifications,
  connectors,
  maps,
  search,
  automation,
  payments,
  mobileCrashes,
}

enum MetricType {
  latency,
  error,
  success,
  queueDepth,
  retries,
  providerError,
}

class TelemetryEvent {
  final String id;
  final InstrumentTarget target;
  final MetricType type;
  final double value; // For latency, queue depth, or boolean success (1/0)
  final Map<String, dynamic> metadata;
  final DateTime timestamp;

  TelemetryEvent({
    required this.id,
    required this.target,
    required this.type,
    required this.value,
    required this.metadata,
    required this.timestamp,
  });
}
