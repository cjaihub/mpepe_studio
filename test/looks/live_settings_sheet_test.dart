import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/providers/looks_providers.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/social_hub/live/settings/live_advanced_settings_sheet.dart';

Widget _buildTestApp({required Widget child, bool isDark = true}) {
  return ProviderScope(
    overrides: [
      currentAuthUidProvider.overrideWithValue('test_user'),
      liveScenesStreamProvider.overrideWith((ref) => Stream.value([])),
      liveProfilesStreamProvider.overrideWith((ref) => Stream.value([])),
      liveSettingsStreamProvider.overrideWith((ref) => Stream.value(null)),
      lookCategoriesStreamProvider.overrideWith((ref) => Stream.value([])),
    ],
    child: MaterialApp(
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('LiveAdvancedSettingsSheet Widget Tests', () {
    testWidgets('renders properly in Dark mode without overflow', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        child: const LiveAdvancedSettingsSheet(),
        isDark: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Live Studio Settings'), findsOneWidget);
      expect(find.text('Looks, Boost Beauty & Stream Health'), findsOneWidget);
      expect(find.text('Realtime Look'), findsOneWidget);
      expect(find.text('Boost Beauty (On-Device GPU)'), findsOneWidget);
      expect(find.text('Natural Guard Active'), findsOneWidget);
    });

    testWidgets('renders properly in Light mode without overflow', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        child: const LiveAdvancedSettingsSheet(),
        isDark: false,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Live Studio Settings'), findsOneWidget);
      expect(find.text('Looks & Beauty'), findsOneWidget);
      expect(find.text('Format & Health'), findsOneWidget);
    });

    testWidgets('AI Live Director Fix button dismisses alert banner', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        child: const LiveAdvancedSettingsSheet(),
        isDark: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Backlit Lighting Detected'), findsOneWidget);
      final fixBtn = find.text('Fix');
      expect(fixBtn, findsOneWidget);

      await tester.tap(fixBtn);
      await tester.pumpAndSettle();

      // Alert should be dismissed
      expect(find.text('Backlit Lighting Detected'), findsNothing);
    });

    testWidgets('switching to Format & Health tab shows resolution selectors', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        child: const LiveAdvancedSettingsSheet(),
        isDark: true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Format & Health'));
      await tester.pumpAndSettle();

      expect(find.text('Stream Health HUD'), findsOneWidget);
      expect(find.text('Broadcast Resolution'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('1080p'), findsOneWidget);
      expect(find.text('Target Frame Rate'), findsOneWidget);
    });

    testWidgets('switching to Audio & FX tab shows toggles and background chips', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildTestApp(
        child: const LiveAdvancedSettingsSheet(),
        isDark: true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Audio & FX'));
      await tester.pumpAndSettle();

      expect(find.text('Background Mode'), findsOneWidget);
      expect(find.text('Depth Blur'), findsOneWidget);
      expect(find.text('Noise Suppression'), findsOneWidget);
      expect(find.text('Echo Cancellation'), findsOneWidget);
      expect(find.text('Voice Enhancement'), findsOneWidget);
    });
  });
}
