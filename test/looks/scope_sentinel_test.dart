import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/ai/models/scope_sentinel_alert.dart';
import 'package:oneova/looks/ai/scopes/models/scope_frame_data.dart';
import 'package:oneova/looks/ai/services/scope_sentinel_engine.dart';

void main() {
  group('ScopeSentinelEngine Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('ScopeFrameData.fromLook calculates realistic histograms and clipping', () {
      const blownLook = OneovaLook(
        id: 'blown',
        name: 'Overexposed',
        primary: LookPrimary(exposure: 2.2, highlights: 0.5),
      );

      final data = ScopeFrameData.fromLook(blownLook);
      expect(data.highlightClippingPercent, greaterThan(2.5));
      expect(data.lumaHistogram.length, 256);
      expect(data.waveformColumns.length, 64);
      expect(data.vectorscopeHueBins.length, 36);
    });

    test('ScopeSentinelEngine triggers blown highlights alert and applies recovery fix', () {
      final engine = container.read(scopeSentinelEngineProvider);
      const look = OneovaLook(
        id: 'blown',
        name: 'Overexposed',
        primary: LookPrimary(exposure: 2.0, highlights: 0.3),
      );

      final frameData = ScopeFrameData.fromLook(look);
      final alert = engine.evaluateFrame(data: frameData, currentLook: look);

      expect(alert, isNotNull);
      expect(alert!.type, SentinelAlertType.blownHighlights);
      expect(alert.suggestedFixLabel, 'Recover');

      // Execute 1-tap fix
      final fixedLook = alert.applyFix(look);
      expect(fixedLook.primary!.highlights, lessThan(0.3));
      expect(fixedLook.primary!.exposure, lessThan(2.0));
    });

    test('ScopeSentinelEngine triggers crushed shadows alert and applies lift fix', () {
      final engine = container.read(scopeSentinelEngineProvider);
      const darkLook = OneovaLook(
        id: 'crushed',
        name: 'Dark Crush',
        primary: LookPrimary(exposure: -2.2, shadows: -0.5),
      );

      final frameData = ScopeFrameData.fromLook(darkLook);
      final alert = engine.evaluateFrame(data: frameData, currentLook: darkLook);

      expect(alert, isNotNull);
      expect(alert!.type, SentinelAlertType.crushedShadows);
      expect(alert.suggestedFixLabel, 'Lift');

      // Execute 1-tap fix
      final fixedLook = alert.applyFix(darkLook);
      expect(fixedLook.primary!.shadows, greaterThan(-0.5));
    });

    test('ScopeSentinelEngine triggers skin tone cast alert when chroma diverges from 57 degrees', () {
      final engine = container.read(scopeSentinelEngineProvider);
      const castLook = OneovaLook(
        id: 'cast',
        name: 'Blue Tint',
        color: LookColor(temperature: -35.0, tint: -10.0),
      );

      final frameData = ScopeFrameData.fromLook(castLook);
      final alert = engine.evaluateFrame(data: frameData, currentLook: castLook);

      expect(alert, isNotNull);
      expect(alert!.type, SentinelAlertType.skinToneCast);
      expect(alert.headline, contains('Skin Cast'));
      expect(alert.suggestedFixLabel, 'Balance');

      // Execute 1-tap fix
      final balancedLook = alert.applyFix(castLook);
      expect(balancedLook.color!.temperature, greaterThan(-35.0));
    });
  });
}
