// ignore_for_file: avoid_print
import 'package:flutter_riverpod/flutter_riverpod.dart';

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService();
});

/// Core Telemetry Service implementing an OpenTelemetry-style API.
/// This acts as the vendor-neutral layer for Traces, Metrics, and Logs.
class TelemetryService {
  
  /// Starts a tracing span for measuring latency.
  Span startSpan(String name, {Map<String, String>? attributes}) {
    // In production, this would call OpenTelemetry's Tracer.startSpan()
    return Span(name: name, attributes: attributes ?? {});
  }

  /// Records a specific metric (e.g., counters, gauges, histograms).
  void recordMetric(String name, double value, {Map<String, String>? attributes}) {
    // In production, this would call OpenTelemetry's Meter API
    print('[METRIC] $name: $value | Attributes: $attributes');
  }

  /// Logs a system event.
  /// EXPLICIT REQUIREMENT: Never log passwords, private keys, tokens, 
  /// raw private messages, or private AI context.
  void logEvent(String name, Map<String, dynamic> data) {
    // Pre-flight PII/Secrets sanitizer
    final sanitizedData = _sanitizePayload(data);
    
    // In production, this routes to OTel Logger or Firebase Crashlytics/Analytics
    print('[LOG] $name: $sanitizedData');
  }

  /// Records a crash or fatal error.
  void recordException(dynamic exception, StackTrace? stack, {bool fatal = false}) {
    // In production, routes to Firebase Crashlytics / OTel Error Tracking
    print('[ERROR] Fatal: $fatal | Exception: $exception');
  }

  /// Strips sensitive keys from outgoing telemetry payloads.
  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> payload) {
    final Map<String, dynamic> sanitized = {};
    final sensitiveKeys = [
      'password', 'key', 'token', 'secret', 'auth', 
      'message_body', 'private_context', 'e2ee_payload'
    ];

    payload.forEach((key, value) {
      if (sensitiveKeys.any((sensitive) => key.toLowerCase().contains(sensitive))) {
        sanitized[key] = '[REDACTED]';
      } else if (value is Map<String, dynamic>) {
        sanitized[key] = _sanitizePayload(value);
      } else {
        sanitized[key] = value;
      }
    });

    return sanitized;
  }
}

/// Represents an OpenTelemetry-style tracing Span.
class Span {
  final String name;
  final Map<String, String> attributes;
  final DateTime startTime;
  
  Span({required this.name, required this.attributes}) 
    : startTime = DateTime.now() {
    print('[SPAN START] $name');
  }

  /// Adds metadata to the ongoing span.
  void addEvent(String eventName) {
    print('[SPAN EVENT] $name -> $eventName');
  }

  /// Records an error against this specific span.
  void recordException(dynamic exception) {
    print('[SPAN ERROR] $name -> $exception');
  }

  /// Ends the span and computes latency.
  void end() {
    final duration = DateTime.now().difference(startTime);
    print('[SPAN END] $name completed in ${duration.inMilliseconds}ms');
    // In production, exports to the OTel Collector.
  }
}
