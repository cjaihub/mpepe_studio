import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/ai/models/scope_sentinel_alert.dart';
import 'package:oneova/looks/ai/scopes/models/scope_frame_data.dart';
import 'package:oneova/looks/ai/scopes/widgets/waveform_scope.dart';
import 'package:oneova/looks/ai/scopes/widgets/rgb_parade_scope.dart';
import 'package:oneova/looks/ai/scopes/widgets/vectorscope.dart';
import 'package:oneova/looks/ai/scopes/widgets/histogram_scope.dart';
import 'package:oneova/looks/ai/scopes/widgets/scope_sentinel_banner.dart';
import 'package:oneova/looks/ai/widgets/conversational_grader_sheet.dart';

Widget _wrap(Widget child, {bool dark = true}) {
  return ProviderScope(
    child: MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Scaffold(
        body: Center(child: child),
      ),
    ),
  );
}

void main() {
  final testScopeData = ScopeFrameData.fromLook(const OneovaLook(id: 'test', name: 'Test'));

  group('GPU Scopes Widget Tests', () {
    testWidgets('WaveformScope renders without error', (tester) async {
      await tester.pumpWidget(_wrap(WaveformScope(data: testScopeData)));
      await tester.pumpAndSettle();
      expect(find.text('WAVEFORM (100 IRE)'), findsOneWidget);
      expect(find.text('0 IRE'), findsOneWidget);
    });

    testWidgets('RgbParadeScope renders R, G, B channel headers', (tester) async {
      await tester.pumpWidget(_wrap(RgbParadeScope(data: testScopeData)));
      await tester.pumpAndSettle();
      expect(find.text('R'), findsOneWidget);
      expect(find.text('G'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('Vectorscope renders circular chroma graticule', (tester) async {
      await tester.pumpWidget(_wrap(Vectorscope(data: testScopeData)));
      await tester.pumpAndSettle();
      expect(find.text('VECTORSCOPE'), findsOneWidget);
    });

    testWidgets('HistogramScope renders luma and clipping metrics', (tester) async {
      await tester.pumpWidget(_wrap(HistogramScope(data: testScopeData)));
      await tester.pumpAndSettle();
      expect(find.text('HISTOGRAM (RGB + LUMA)'), findsOneWidget);
    });
  });

  group('ScopeSentinelBanner Widget Tests', () {
    testWidgets('Renders headline, description and triggers 1-tap fix', (tester) async {
      bool fixTapped = false;
      bool dismissTapped = false;

      final alert = ScopeSentinelAlert(
        id: 'test_alert',
        type: SentinelAlertType.blownHighlights,
        severity: SentinelSeverity.warning,
        headline: 'Highlight Clipping Detected',
        description: '4.2% pixels above 100 IRE',
        suggestedFixLabel: 'Recover',
        applyFix: (look) => look,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(_wrap(
        ScopeSentinelBanner(
          alert: alert,
          onApplyFix: () => fixTapped = true,
          onDismiss: () => dismissTapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SENTINEL'), findsOneWidget);
      expect(find.text('Highlight Clipping Detected'), findsOneWidget);
      expect(find.text('Recover'), findsOneWidget);

      await tester.tap(find.text('Recover'));
      await tester.pumpAndSettle();
      expect(fixTapped, true);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(dismissTapped, true);
    });
  });

  group('ConversationalGraderSheet Widget Tests', () {
    testWidgets('Renders in Dark mode without overflow', (tester) async {
      await tester.pumpWidget(_wrap(const ConversationalGraderSheet()));
      await tester.pumpAndSettle();

      expect(find.text('AI Color Grader'), findsOneWidget);
      expect(find.text('WAVEFORM'), findsOneWidget);
      expect(find.text('Skin Tones'), findsOneWidget);
    });

    testWidgets('Renders in Light mode without overflow', (tester) async {
      await tester.pumpWidget(_wrap(const ConversationalGraderSheet(), dark: false));
      await tester.pumpAndSettle();

      expect(find.text('AI Color Grader'), findsOneWidget);
      expect(find.text('WAVEFORM'), findsOneWidget);
    });
  });
}
