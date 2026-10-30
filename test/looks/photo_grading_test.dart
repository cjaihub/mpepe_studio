import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/looks/models/oneova_look.dart';
import 'package:oneova/looks/ai/models/ai_grade_command.dart';
import 'package:oneova/looks/photo/models/photo_grading_models.dart';
import 'package:oneova/looks/photo/controllers/photo_grading_controller.dart';
import 'package:oneova/looks/photo/services/photo_export_service.dart';
import 'package:oneova/looks/photo/services/photo_batch_grading_service.dart';
import 'package:oneova/looks/photo/ui/photo_grading_screen.dart';
import 'package:oneova/looks/photo/widgets/photo_simple_grading_deck.dart';
import 'package:oneova/looks/photo/widgets/photo_pro_nodes_deck.dart';
import 'package:oneova/looks/photo/widgets/photo_batch_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testImagePath;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('oneova_photo_test_');

    // Generate a valid 400x300 test JPEG
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(120, 140, 180));
    final jpgBytes = img.encodeJpg(image);

    final file = File('${tempDir.path}/test_source.jpg');
    await file.writeAsBytes(jpgBytes);
    testImagePath = file.path;
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PhotoGradingController Unit Tests', () {
    test('Initializes with default neutral look and Simple mode', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(photoGradingControllerProvider);
      expect(state.mode, equals(PhotoGradingMode.simple));
      expect(state.activeProTab, equals(PhotoProNodeTab.primary));
      expect(state.isScopesVisible, isFalse);
      expect(state.isComparing, isFalse);
      expect(state.currentLook.primary.exposure, equals(0.0));
      expect(state.currentLook.color.temperature, equals(0.0));
    });

    test('Mode and Pro Tab switching updates state properly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      controller.setMode(PhotoGradingMode.pro);
      expect(container.read(photoGradingControllerProvider).mode, equals(PhotoGradingMode.pro));

      controller.setActiveProTab(PhotoProNodeTab.wheels);
      expect(container.read(photoGradingControllerProvider).activeProTab, equals(PhotoProNodeTab.wheels));

      controller.setActiveProTab(PhotoProNodeTab.boostBeauty);
      expect(container.read(photoGradingControllerProvider).activeProTab, equals(PhotoProNodeTab.boostBeauty));
    });

    test('updatePrimary modifies exposure, contrast, highlights, and shadows', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      controller.updatePrimary(
        exposure: 0.75,
        contrast: 1.25,
        highlights: -0.3,
        shadows: 0.2,
      );

      final look = container.read(photoGradingControllerProvider).currentLook;
      expect(look.primary.exposure, equals(0.75));
      expect(look.primary.contrast, equals(1.25));
      expect(look.primary.highlights, equals(-0.3));
      expect(look.primary.shadows, equals(0.2));
    });

    test('updateColor adjusts warmth, tint, vibrance and saturation', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      controller.updateColor(
        temperature: 24.0,
        tint: -6.0,
        vibrance: 0.35,
        saturation: 1.15,
      );

      final look = container.read(photoGradingControllerProvider).currentLook;
      expect(look.color.temperature, equals(24.0));
      expect(look.color.tint, equals(-6.0));
      expect(look.color.vibrance, equals(0.35));
      expect(look.color.saturation, equals(1.15));
    });

    test('updateWheels sets 3-way Lift, Gamma, Gain and Offset', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      controller.updateWheels(
        lift: const ColorWheel(r: 0.1, b: -0.1, lum: -0.05),
        gamma: const ColorWheel(r: 0.05, g: 0.05, lum: 0.1),
        gain: const ColorWheel(b: 0.15, lum: 0.05),
      );

      final wheels = container.read(photoGradingControllerProvider).currentLook.wheels;
      expect(wheels.lift.r, equals(0.1));
      expect(wheels.lift.lum, equals(-0.05));
      expect(wheels.gamma.g, equals(0.05));
      expect(wheels.gain.b, equals(0.15));
    });

    test('updateBoostBeauty and updateBackground apply parameters', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      controller.updateBoostBeauty(
        isEnabled: true,
        smoothSkin: 0.6,
        evenTone: 0.4,
        eyeBrighten: 0.3,
        faceSlim: 0.25,
      );

      controller.updateBackground(
        mode: 'blur',
        blurLevel: 0.75,
      );

      final look = container.read(photoGradingControllerProvider).currentLook;
      expect(look.boostBeauty.isEnabled, isTrue);
      expect(look.boostBeauty.smoothSkin, equals(0.6));
      expect(look.boostBeauty.faceSlim, equals(0.25));
      expect(look.background.mode, equals('blur'));
      expect(look.background.blurLevel, equals(0.75));
    });

    test('Preset apply and baseline reset work reliably', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      const testPreset = OneovaLook(
        id: 'preset_test',
        name: 'Vintage Vibe',
        categories: ['vintage'],
        primary: LookPrimary(exposure: -0.2, contrast: 1.3),
      );

      controller.applyPreset(testPreset, intensity: 0.8);
      var state = container.read(photoGradingControllerProvider);
      expect(state.currentLook.id, equals('preset_test'));
      expect(state.currentLook.intensity, equals(0.8));

      controller.resetToBaseline();
      state = container.read(photoGradingControllerProvider);
      expect(state.currentLook.id, equals('photo_neutral'));
    });

    test('Batch queue management adds and removes paths', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      controller.addToBatchQueue(['/photos/img1.jpg', '/photos/img2.jpg']);
      var state = container.read(photoGradingControllerProvider);
      expect(state.batchQueue.length, equals(2));

      controller.removeFromBatchQueue('/photos/img1.jpg');
      state = container.read(photoGradingControllerProvider);
      expect(state.batchQueue.length, equals(1));
      expect(state.batchQueue.first, equals('/photos/img2.jpg'));

      controller.clearBatchQueue();
      state = container.read(photoGradingControllerProvider);
      expect(state.batchQueue, isEmpty);
    });

    test('applyAiResult updates currentLook from AI diff report', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(photoGradingControllerProvider.notifier);

      const updatedLook = OneovaLook(
        id: 'look_ai',
        name: 'AI Moody',
        primary: LookPrimary(exposure: -0.15, contrast: 1.2),
        color: LookColor(temperature: 15.0),
      );

      final aiResult = AiGradeResult(
        updatedLook: updatedLook,
        diffReport: const GradeDiffReport(
          previousParameters: {},
          updatedParameters: {'exposure': -0.15},
          modifiedNodes: ['primary', 'color'],
          visualDeltaSummary: 'Warm moody film aesthetic applied',
          artisticRationale: 'Golden hour palette',
          targetRegion: SemanticGradeRegion.entireFrame,
        ),
        assistantExplanation: 'Applied subtle warmth and contrast',
        suggestedNextPrompts: ['Add film halation'],
        isOfflineInference: true,
      );

      controller.applyAiResult(aiResult);
      final look = container.read(photoGradingControllerProvider).currentLook;
      expect(look.id, equals('look_ai'));
      expect(look.primary.exposure, equals(-0.15));
      expect(look.color.temperature, equals(15.0));
    });
  });

  group('Photo Export & Batch Services Tests', () {
    test('exportOriginalResolution exports full native dimensions without downsampling', () async {
      final exportService = PhotoExportService();
      const look = OneovaLook(
        id: 'look_graded',
        name: 'Graded',
        primary: LookPrimary(exposure: 0.2, contrast: 1.1),
        color: LookColor(temperature: 10.0, saturation: 1.1),
        optics: LookOptics(vignette: 0.3),
        film: LookFilm(grain: 0.15),
      );

      final result = await exportService.exportOriginalResolution(
        sourcePath: testImagePath,
        look: look,
      );

      expect(result.outputWidth, equals(400));
      expect(result.outputHeight, equals(300));
      expect(result.fileSizeBytes, greaterThan(0));
      expect(result.exifPreserved, isTrue);

      final outFile = File(result.outputPath);
      expect(await outFile.exists(), isTrue);
    });

    test('PhotoBatchGradingService processes multiple images and emits progress', () async {
      // Create a second image
      final img2 = img.Image(width: 300, height: 200);
      img.fill(img2, color: img.ColorRgb8(80, 160, 100));
      final file2 = File('${tempDir.path}/test_source_2.jpg');
      await file2.writeAsBytes(img.encodeJpg(img2));

      final batchService = PhotoBatchGradingService();
      const look = OneovaLook(
        id: 'batch_look',
        name: 'Batch Look',
        primary: LookPrimary(contrast: 1.15),
      );

      final progressEvents = <BatchProgressUpdate>[];

      final report = await batchService.executeBatch(
        photoPaths: [testImagePath, file2.path],
        look: look,
        onProgress: (u) => progressEvents.add(u),
      );

      expect(report.totalCount, equals(2));
      expect(report.successCount, equals(2));
      expect(report.failedCount, equals(0));
      expect(progressEvents.isNotEmpty, isTrue);
      expect(progressEvents.last.fraction, equals(1.0));
    });
  });

  group('Photo Grading UI Widget Tests', () {
    Widget buildTestHost({required Widget child, Brightness brightness = Brightness.dark}) {
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

    testWidgets('PhotoGradingScreen renders in Dark Mode with mode toggle and controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          brightness: Brightness.dark,
          child: PhotoGradingScreen(initialImagePath: testImagePath),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Simple'), findsOneWidget);
      expect(find.text('Pro Nodes'), findsOneWidget);
      expect(find.text('Look Intensity'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.byIcon(Icons.analytics_outlined), findsOneWidget);
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
    });

    testWidgets('PhotoGradingScreen renders in Light Mode without layout issues', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          brightness: Brightness.light,
          child: PhotoGradingScreen(initialImagePath: testImagePath),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Simple'), findsOneWidget);
      expect(find.text('Pro Nodes'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
    });

    testWidgets('Toggling between Simple and Pro mode displays Pro node tabs', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: PhotoGradingScreen(initialImagePath: testImagePath),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 'Pro Nodes'
      await tester.tap(find.text('Pro Nodes'));
      await tester.pumpAndSettle();

      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Wheels'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.byType(PhotoProNodesDeck), findsOneWidget);
    });

    testWidgets('Toggling scopes shows floating GPU scope overlay', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: PhotoGradingScreen(initialImagePath: testImagePath),
        ),
      );
      await tester.pumpAndSettle();

      // Tap scopes button
      await tester.tap(find.byIcon(Icons.analytics_outlined));
      await tester.pumpAndSettle();

      expect(find.text('WAVEFORM'), findsOneWidget);
    });

    testWidgets('PhotoBatchDialog opens, displays queue and allows actions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        buildTestHost(
          child: const PhotoBatchDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Batch Photo Grading'), findsOneWidget);
      expect(find.text('Run Batch'), findsOneWidget);
      expect(find.text('No photos in batch queue'), findsOneWidget);
    });
  });
}
