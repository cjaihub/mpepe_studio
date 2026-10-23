import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/instrumentation/models/instrumentation_models.dart';
import 'package:oneova/backend/instrumentation/services/instrumentation_engine.dart';

void main() {
  late InstrumentationEngine engine;

  setUp(() {
    engine = InstrumentationEngine();
  });

  test('InstrumentationEngine records valid telemetry successfully', () {
    engine.logEvent(
      target: InstrumentTarget.api,
      type: MetricType.latency,
      value: 120.5,
      metadata: {'endpoint': '/v1/users'},
    );

    expect(engine.events.length, 1);
    expect(engine.events.first.target, InstrumentTarget.api);
    expect(engine.events.first.value, 120.5);
  });

  test('Privacy Scrubber strictly blocks tokens and passwords', () {
    // 1. Password block
    expect(
      () => engine.logEvent(
        target: InstrumentTarget.database,
        type: MetricType.error,
        value: 1,
        metadata: {'user_password': 'plain_text_password'},
      ),
      throwsA(isA<PrivacyViolationException>().having((e) => e.toString(), 'msg', contains('Never log password'))),
    );

    // 2. Token block
    expect(
      () => engine.logEvent(
        target: InstrumentTarget.connectors,
        type: MetricType.providerError,
        value: 1,
        metadata: {'api_Token': 'sk_live_12345'},
      ),
      throwsA(isA<PrivacyViolationException>().having((e) => e.toString(), 'msg', contains('Never log token'))),
    );

    // 3. Location block
    expect(
      () => engine.logEvent(
        target: InstrumentTarget.maps,
        type: MetricType.success,
        value: 1,
        metadata: {'user_latitude': '40.7128'},
      ),
      throwsA(isA<PrivacyViolationException>().having((e) => e.toString(), 'msg', contains('Never log latitude'))),
    );

    // 4. AI Private Context block
    expect(
      () => engine.logEvent(
        target: InstrumentTarget.ai,
        type: MetricType.queueDepth,
        value: 5,
        metadata: {'private_ai_context_dump': 'User wants to build a bomb'},
      ),
      throwsA(isA<PrivacyViolationException>().having((e) => e.toString(), 'msg', contains('Never log private_ai_context'))),
    );

    // The event queue should remain empty since all were blocked
    expect(engine.events.length, 0);
  });
}
