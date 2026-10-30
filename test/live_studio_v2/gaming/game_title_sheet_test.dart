import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/social_hub/live/studio_v2/gaming/game_title_sheet.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester, void Function(String?) onResult) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () async => onResult(await showGameTitleSheet(c)),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows quick chips; a chip fills the field and submits it', (tester) async {
    String? result = 'unset';
    await pumpHost(tester, (r) => result = r);
    for (final g in [...kGameQuickPicks, kGameOtherChip]) {
      expect(find.text(g), findsOneWidget);
    }
    // Disabled while empty.
    await tester.tap(find.byKey(GameTitleSheet.startKey));
    await tester.pumpAndSettle();
    expect(find.byType(GameTitleSheet), findsOneWidget);

    await tester.tap(find.text('Free Fire'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(GameTitleSheet.fieldKey)).controller!.text, 'Free Fire');
    await tester.tap(find.byKey(GameTitleSheet.startKey));
    await tester.pumpAndSettle();
    expect(result, 'Free Fire');
  });

  testWidgets('Other clears the field; typed titles are trimmed and capped at 60', (tester) async {
    String? result;
    await pumpHost(tester, (r) => result = r);
    await tester.tap(find.text('Ludo'));
    await tester.pump();
    await tester.tap(find.text(kGameOtherChip));
    await tester.pump();
    final field = find.byKey(GameTitleSheet.fieldKey);
    expect(tester.widget<TextField>(field).controller!.text, '');

    await tester.enterText(field, '  ${'x' * 70}');
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text.length, lessThanOrEqualTo(60));

    await tester.enterText(field, '  Ludo King  ');
    await tester.pump();
    await tester.tap(find.byKey(GameTitleSheet.startKey));
    await tester.pumpAndSettle();
    expect(result, 'Ludo King');
  });

  testWidgets('dismissing returns null', (tester) async {
    String? result = 'unset';
    await pumpHost(tester, (r) => result = r);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
