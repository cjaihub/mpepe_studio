import 'package:oneova/backend/instrumentation/models/instrumentation_models.dart';

class PrivacyViolationException implements Exception {
  final String message;
  PrivacyViolationException(this.message);

  @override
  String toString() => 'PrivacyViolationException: $message';
}

class InstrumentationEngine {
  final List<TelemetryEvent> _events = [];

  // Keys that strictly trigger a Privacy Violation if passed into the telemetry metadata
  static const List<String> _forbiddenKeys = [
    'password',
    'passwords',
    'token',
    'tokens',
    'private_key',
    'private_keys',
    'private_message',
    'message_content',
    'private_ai_context',
    'ai_context',
    'latitude',
    'longitude',
    'exact_location',
  ];

  void logEvent({
    required InstrumentTarget target,
    required MetricType type,
    required double value,
    Map<String, dynamic> metadata = const {},
  }) {
    _enforcePrivacyScrubber(metadata);

    _events.add(TelemetryEvent(
      id: 'event_${DateTime.now().microsecondsSinceEpoch}',
      target: target,
      type: type,
      value: value,
      metadata: metadata,
      timestamp: DateTime.now(),
    ));
  }

  void _enforcePrivacyScrubber(Map<String, dynamic> metadata) {
    for (var key in metadata.keys) {
      final lowercaseKey = key.toLowerCase();
      for (var forbidden in _forbiddenKeys) {
        if (lowercaseKey.contains(forbidden)) {
          throw PrivacyViolationException('Never log $forbidden. Detected in metadata key: $key');
        }
      }
    }
  }

  List<TelemetryEvent> get events => List.unmodifiable(_events);
}
