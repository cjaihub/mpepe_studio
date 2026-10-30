import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/camera/models/camera_smart_lock_state.dart';
import 'package:oneova/looks/camera/widgets/camera_smart_lock_hud.dart';
import 'package:oneova/looks/camera/widgets/camera_pro_controls_deck.dart';
import 'package:oneova/looks/camera/widgets/camera_looks_dock.dart';

Widget _wrap(Widget child, {bool dark = true}) {
  return MaterialApp(
    theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  group('CameraSmartLockHud Widget Tests', () {
    testWidgets('Renders nothing when no lock is active', (tester) async {
      await tester.pumpWidget(_wrap(
        const CameraSmartLockHud(
          smartLock: CameraSmartLockState(
            isSmartLockActive: false,
            aeLocked: false,
            afLocked: false,
            awbLocked: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SMART LOCK'), findsNothing);
    });

    testWidgets('Renders lock badges when smart lock is active', (tester) async {
      await tester.pumpWidget(_wrap(
        const CameraSmartLockHud(
          smartLock: CameraSmartLockState(
            isSmartLockActive: true,
            aeLocked: true,
            afLocked: true,
            awbLocked: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('SMART LOCK'), findsOneWidget);
      expect(find.text('AE'), findsOneWidget);
      expect(find.text('AF'), findsOneWidget);
      expect(find.text('AWB'), findsOneWidget);
    });

    testWidgets('Calls onUnlockTap when unlock icon tapped', (tester) async {
      bool unlockTapped = false;
      await tester.pumpWidget(_wrap(
        CameraSmartLockHud(
          smartLock: const CameraSmartLockState(
            isSmartLockActive: true,
            aeLocked: true,
          ),
          onUnlockTap: () => unlockTapped = true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(unlockTapped, true);
    });
  });

  group('CameraProControlsDeck Widget Tests', () {
    testWidgets('Renders tabs and allows tab switching', (tester) async {
      await tester.pumpWidget(_wrap(
        CameraProControlsDeck(
          state: const CameraSmartLockState(),
          onEvChanged: (_) {},
          onIsoChanged: (_) {},
          onShutterChanged: (_) {},
          onWbChanged: (_, {kelvin}) {},
          onFocusChanged: (_) {},
          onTogglePeaking: () {},
          onClose: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('EV'), findsOneWidget);
      expect(find.text('ISO'), findsOneWidget);
      expect(find.text('SHUTTER'), findsOneWidget);
      expect(find.text('WB'), findsOneWidget);
      expect(find.text('FOCUS'), findsOneWidget);

      // Switch to ISO tab
      await tester.tap(find.text('ISO'));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
      expect(find.text('200'), findsOneWidget);
      expect(find.text('400'), findsOneWidget);
    });
  });

  group('CameraLooksDock Widget Tests', () {
    testWidgets('Renders look items and allows selecting look', (tester) async {
      OneovaLook? selectedLook;
      await tester.pumpWidget(_wrap(
        CameraLooksDock(
          activeLook: const OneovaLook(id: 'neutral', name: 'Original'),
          onLookSelected: (look) => selectedLook = look,
          onIntensityChanged: (_) {},
          onOpenCatalog: () {},
          onClose: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('Cinematic'), findsNWidgets(2)); // Category chip + Look dial

      await tester.tap(find.text('Cinematic').last);
      await tester.pumpAndSettle();
      expect(selectedLook, isNotNull);
      expect(selectedLook!.name, 'Cinematic');
    });

    testWidgets('Renders in light mode without overflow or errors', (tester) async {
      await tester.pumpWidget(_wrap(
        CameraLooksDock(
          activeLook: const OneovaLook(id: 'neutral', name: 'Original'),
          onLookSelected: (_) {},
          onIntensityChanged: (_) {},
          onOpenCatalog: () {},
          onClose: () {},
        ),
        dark: false,
      ));
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
    });
  });
}
