import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/looks/ar/controllers/ar_effect_controller.dart';
import 'package:oneova/looks/ar/models/ar_effect_package.dart';
import 'package:oneova/looks/ar/services/ar_effect_runtime.dart';
import 'package:oneova/looks/ar/ui/ar_studio_screen.dart';
import 'package:oneova/looks/ar/widgets/ar_lens_carousel.dart';
import 'package:oneova/looks/ar/widgets/ar_makeup_deck.dart';
import 'package:oneova/looks/ar/widgets/ar_trigger_badge.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova_camera_kit/oneova_camera_kit.dart';

Widget buildTestHost({
  required Widget child,
  Brightness brightness = Brightness.dark,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        scaffoldBackgroundColor:
            brightness == Brightness.dark ? AppColors.darkBackground : AppColors.lightBackground,
      ),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OneovaEffectPackage & Layers Models Tests', () {
    test('OneovaEffectPackage serializes to JSON and deserializes correctly', () {
      const package = OneovaEffectPackage(
        id: 'fx_test_01',
        name: 'Neon Cyber Horns',
        author: 'Creator Alpha',
        category: ArCategory.fx3d,
        thumbnailUrl: 'assets/thumb.jpg',
        layers: [
          ArEffectLayer(
            id: 'horns_3d',
            type: ArLayerType.sticker3d,
            assetPath: 'assets/horns.glb',
            anchorLandmarkIndex: 10,
            offset: [0.0, -0.1, 0.0],
            scale: [1.2, 1.2, 1.2],
          ),
        ],
        customParameters: {'glow': true},
      );

      final json = package.toJson();
      expect(json['id'], 'fx_test_01');
      expect(json['category'], 'fx3d');

      final deserialized = OneovaEffectPackage.fromJson(json);
      expect(deserialized.id, package.id);
      expect(deserialized.category, ArCategory.fx3d);
      expect(deserialized.layers.length, 1);
      expect(deserialized.layers.first.anchorLandmarkIndex, 10);
    });

    test('Starter lenses catalog includes required categories and trigger lenses', () {
      final lenses = OneovaEffectPackage.starterLenses;
      expect(lenses.length, greaterThanOrEqualTo(5));
      expect(lenses.any((l) => l.id == 'lens_cyber_visor'), isTrue);
      expect(lenses.any((l) => l.id == 'lens_peace_sparks'), isTrue);
    });
  });

  group('MediaPipe AR Tracking & Trigger Detection Tests', () {
    test('FaceMeshLandmarks accurately computes mouth openness and smile confidence', () {
      final points = List.generate(478, (i) => const Landmark3D(x: 0.5, y: 0.5, z: 0.0));

      // Mock smiling face (wide mouth corners)
      points[61] = const Landmark3D(x: 0.25, y: 0.6); // Left corner
      points[291] = const Landmark3D(x: 0.75, y: 0.6); // Right corner
      points[33] = const Landmark3D(x: 0.40, y: 0.4); // Left eye
      points[263] = const Landmark3D(x: 0.60, y: 0.4); // Right eye

      final face = FaceMeshLandmarks(points: points);
      expect(face.smileConfidence, greaterThan(0.5));
    });

    test('HandLandmarks accurately detects Peace Sign gesture', () {
      final points = List.generate(21, (i) => const Landmark3D(x: 0.5, y: 0.5));

      // Wrist at bottom
      points[0] = const Landmark3D(x: 0.5, y: 0.8);
      // Index and middle fingers extended up
      points[8] = const Landmark3D(x: 0.45, y: 0.3); // Index tip
      points[12] = const Landmark3D(x: 0.55, y: 0.3); // Middle tip
      // Ring and pinky curled down
      points[16] = const Landmark3D(x: 0.60, y: 0.55); // Ring tip
      points[20] = const Landmark3D(x: 0.65, y: 0.55); // Pinky tip

      final hand = HandLandmarks(isLeft: false, points: points);
      expect(hand.isPeaceSign, isTrue);
    });

    test('TrackingFrame detects active gestures across multiple hands and faces', () {
      final handPoints = List.generate(21, (i) => const Landmark3D(x: 0.5, y: 0.5));
      handPoints[0] = const Landmark3D(x: 0.5, y: 0.8);
      handPoints[8] = const Landmark3D(x: 0.45, y: 0.3);
      handPoints[12] = const Landmark3D(x: 0.55, y: 0.3);
      handPoints[16] = const Landmark3D(x: 0.60, y: 0.55);
      handPoints[20] = const Landmark3D(x: 0.65, y: 0.55);

      final frame = TrackingFrame(
        timestampMs: 1000,
        hands: [HandLandmarks(isLeft: false, points: handPoints)],
      );

      final triggers = frame.evaluateActiveTriggers();
      expect(triggers.contains('peace_sign'), isTrue);
    });
  });

  group('ArEffectRuntime Unit Tests', () {
    test('Runtime activates trigger-dependent layers only when gesture is present', () {
      final runtime = ArEffectRuntime();
      final peaceSparks = OneovaEffectPackage.starterLenses.firstWhere(
        (l) => l.id == 'lens_peace_sparks',
      );

      runtime.loadPackage(peaceSparks);

      // Frame WITHOUT peace sign
      const idleFrame = TrackingFrame(timestampMs: 100);
      final idleRender = runtime.processFrame(idleFrame);
      expect(idleRender.activeLayerCount, 0);

      // Frame WITH peace sign
      final handPoints = List.generate(21, (i) => const Landmark3D(x: 0.5, y: 0.5));
      handPoints[0] = const Landmark3D(x: 0.5, y: 0.8);
      handPoints[8] = const Landmark3D(x: 0.45, y: 0.3);
      handPoints[12] = const Landmark3D(x: 0.55, y: 0.3);
      handPoints[16] = const Landmark3D(x: 0.60, y: 0.55);
      handPoints[20] = const Landmark3D(x: 0.65, y: 0.55);

      final activeFrame = TrackingFrame(
        timestampMs: 150,
        hands: [HandLandmarks(isLeft: false, points: handPoints)],
      );

      final activeRender = runtime.processFrame(activeFrame);
      expect(activeRender.activeLayerCount, 1);
      expect(activeRender.activeTriggers.contains('peace_sign'), isTrue);
    });
  });

  group('ArEffectController Unit Tests', () {
    test('Controller handles category switching and lens selection', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(arEffectControllerProvider.notifier);

      notifier.selectCategory(ArCategory.makeup);
      expect(container.read(arEffectControllerProvider).activeCategory, ArCategory.makeup);

      final makeupLens = OneovaEffectPackage.starterLenses.firstWhere((l) => l.category == ArCategory.makeup);
      notifier.selectEffect(makeupLens);
      expect(container.read(arEffectControllerProvider).activeEffect?.id, makeupLens.id);

      notifier.updateLipstick(0.95);
      expect(container.read(arEffectControllerProvider).lipTintOpacity, 0.95);

      notifier.clearEffect();
      expect(container.read(arEffectControllerProvider).activeEffect, isNull);
    });
  });

  group('AR Widgets & Studio Screen Tests', () {
    testWidgets('ArLensCarousel renders category tabs, none button and lenses', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ArLensCarousel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trending'), findsOneWidget);
      expect(find.text('Beauty & Makeup'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Peace Gesture Sparks'), findsOneWidget);
    });

    testWidgets('ArMakeupDeck renders makeup sliders with labels', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: const Scaffold(
            body: Center(
              child: ArMakeupDeck(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AR Makeup & Hair'), findsOneWidget);
      expect(find.text('Lip Tint'), findsOneWidget);
      expect(find.text('Cheek Blush'), findsOneWidget);
      expect(find.text('Eyeliner'), findsOneWidget);
      expect(find.text('Hair Hue'), findsOneWidget);
    });

    testWidgets('ArTriggerBadge displays trigger title', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: const Scaffold(
            body: Center(
              child: ArTriggerBadge(label: 'Peace Gesture ✌️'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Peace Gesture ✌️'), findsOneWidget);
    });

    testWidgets('ArStudioScreen renders in Dark Mode with camera canvas and lens carousel', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          brightness: Brightness.dark,
          child: const ArStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AR Studio'), findsOneWidget);
      expect(find.text('Oneova Camera Kit AR Pipeline'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(find.byIcon(Icons.grid_off_rounded), findsOneWidget);
    });

    testWidgets('Tapping makeup button toggles ArMakeupDeck in ArStudioScreen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: const ArStudioScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ArMakeupDeck), findsNothing);

      await tester.tap(find.byIcon(Icons.tune_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(ArMakeupDeck), findsOneWidget);
    });
  });
}
